"""Compare and benchmark area fills: qdgc_pg vs qdgc_py vs the legacy approach.

Encoding parity is already guaranteed by the test suite. What this measures is
the part that cannot be exact -- which cells an area fill selects -- and whether
the pruning quadtree descent is actually faster than the full-envelope
ST_SquareGrid the legacy qdgc_fillqdgc used.

    python tools/compare_fill.py

Reports, per area of interest and level:
  * cell counts from qdgc_pg and from qdgc_py, and the size of the disagreement
  * whether every disagreeing cell merely touches the AOI boundary, which is
    the documented and accepted divergence
  * wall-clock for the quadtree descent against the legacy grid-and-filter
"""
from __future__ import annotations

import math
import pathlib
import re
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT.parent / "qdgc_py" / "src"))

from pgexec import Executor  # noqa: E402
from qdgc_py import core  # noqa: E402

TIME_RE = re.compile(r"^Time:\s*([0-9.]+)\s*ms", re.MULTILINE)


def ring_wkt(ring) -> str:
    return "(" + ", ".join(f"{x!r} {y!r}" for x, y in ring) + ")"


def polygon_wkt(exterior, holes=()) -> str:
    parts = [ring_wkt(exterior)] + [ring_wkt(h) for h in holes]
    return "POLYGON(" + ", ".join(parts) + ")"


def close(ring):
    return ring if ring[0] == ring[-1] else ring + [ring[0]]


def radial_polygon(cx, cy, n, base, wobble, freq, phase=0.0):
    """A simple, non-self-intersecting blob with a long, convoluted boundary.

    Radius varies with angle, so the ring can never cross itself, but the
    perimeter-to-area ratio is high -- which is exactly what stresses a
    boundary-driven fill.
    """
    pts = []
    for i in range(n):
        theta = 2.0 * math.pi * i / n
        r = base + wobble * (math.sin(freq * theta + phase)
                             + 0.45 * math.sin(2.7 * freq * theta + 1.3))
        pts.append((round(cx + r * math.cos(theta), 9),
                    round(cy + r * math.sin(theta) * 0.75, 9)))
    return close(pts)


def build_aois():
    box = close([(30.0, 2.0), (31.0, 2.0), (31.0, 3.0), (30.0, 3.0)])
    triangle = close([(30.0, 2.0), (32.0, 2.0), (30.0, 4.0)])
    coast = radial_polygon(30.5, 2.5, 240, 0.30, 0.11, 9.0)
    outer = close([(30.0, 2.0), (31.5, 2.0), (31.5, 3.5), (30.0, 3.5)])
    hole = close([(30.4, 2.4), (31.1, 2.4), (31.1, 3.1), (30.4, 3.1)])

    # An interior notch: cells sit against a re-entrant edge well inside the
    # envelope. qdgc_py counts a point on a segment as inside, so it keeps
    # those -- the opposite of what it does at the envelope's upper edge.
    notch = close([(30.0, 2.0), (31.0, 2.0), (31.0, 3.0), (30.5, 3.0),
                   (30.5, 2.5), (30.25, 2.5), (30.25, 3.0), (30.0, 3.0)])

    # A thin diagonal band: tiny area, huge envelope. This is the shape a real
    # coastline or river corridor resembles, and where pruning should pay.
    band = close([(30.0, 2.0), (30.15, 2.0), (33.0, 4.85), (33.0, 5.0),
                  (32.85, 5.0), (30.0, 2.15)])

    return [
        ("box 1x1 deg", box, [], (3, 5, 7), (8, 9)),
        ("triangle, diagonal edge", triangle, [], (3, 5, 7), (8, 9)),
        ("convoluted blob, 240 vertices", coast, [], (3, 5, 7), (8, 9)),
        ("square with a square hole", outer, [hole], (3, 5, 7), (8,)),
        ("interior notch", notch, [], (3, 5, 7), (8,)),
        ("thin diagonal band, sparse envelope", band, [], (3, 5, 7), (8, 9)),
    ]


def timed(ex: Executor, sql: str) -> tuple[list[str], float]:
    out = ex.run("\\timing on\n" + sql, args=["-tA"])
    match = TIME_RE.search(out)
    ms = float(match.group(1)) if match else float("nan")
    rows = [ln for ln in out.splitlines()
            if ln.strip() and not ln.startswith("Time:") and not ln.startswith("Timing")]
    return rows, ms


def main() -> int:
    ex = Executor()
    print(f"target: {ex.describe()}")
    print(f"qdgc extension version: {ex.scalar('SELECT qdgc_version();')}")
    print(f"postgis: {ex.scalar('SELECT postgis_lib_version();')}")
    print()

    total_mismatch = 0
    total_boundary_only = 0

    for name, exterior, holes, parity_levels, bench_levels in build_aois():
        wkt = polygon_wkt(exterior, holes)
        geom = f"ST_GeomFromText('{wkt}', 4326)"
        print(f"=== {name} ===")

        for level in parity_levels:
            sql_cells, ms = timed(ex, f"SELECT c FROM qdgc_polygon_to_cells({geom}, {level}) c;")
            py_cells = core.polygon_to_cells(exterior, level, holes=list(holes),
                                             predicate="intersects")

            sql_set, py_set = set(sql_cells), set(py_cells)
            only_sql = sql_set - py_set
            only_py = py_set - sql_set
            diff = only_sql | only_py
            total_mismatch += len(diff)

            verdict = "identical"
            if diff:
                # Classify: is every disagreement a cell that merely touches the
                # AOI boundary? That is the accepted GEOS-vs-epsilon divergence.
                values = ", ".join(f"('{c}')" for c in sorted(diff))
                touching = int(ex.scalar(f"""
                    WITH d(code) AS (VALUES {values}), a AS (SELECT {geom} AS g)
                    SELECT count(*) FROM d, a
                    WHERE ST_Intersects(ST_Boundary(a.g),
                                        qdgc_cell_to_boundary_geometry(d.code));
                """) or 0)
                total_boundary_only += touching
                verdict = (f"{len(diff)} differ ({len(only_sql)} sql-only, "
                           f"{len(only_py)} py-only), {touching} touch the boundary"
                           + (" -- all accounted for" if touching == len(diff)
                              else " -- INTERIOR DISAGREEMENT"))

            print(f"  level {level:<2}  qdgc_pg {len(sql_set):>7}  "
                  f"qdgc_py {len(py_set):>7}  {ms:>8.1f} ms   {verdict}")

        for level in bench_levels:
            side = core.level_degrees(level)
            _, quad_ms = timed(
                ex, f"SELECT count(*) FROM qdgc_polygon_to_cells({geom}, {level});")
            rows, grid_ms = timed(ex, f"""
                SELECT count(*) FROM ST_SquareGrid({side!r}, {geom}) g
                WHERE ST_Intersects({geom}, g.geom);
            """)
            n = rows[-1] if rows else "?"
            speedup = grid_ms / quad_ms if quad_ms else float("nan")
            print(f"  level {level:<2}  bench   {n:>7} cells  "
                  f"quadtree {quad_ms:>9.1f} ms   ST_SquareGrid {grid_ms:>9.1f} ms   "
                  f"{speedup:>5.1f}x")
        print()

    if total_mismatch == 0:
        print("RESULT: qdgc_pg and qdgc_py select identical cell sets on every AOI.")
        return 0
    print(f"total disagreeing cells: {total_mismatch}, "
          f"of which boundary-touching: {total_boundary_only}")
    if total_mismatch != total_boundary_only:
        print("RESULT: some disagreements are NOT boundary-touching -- investigate.")
        return 1
    print("RESULT: all disagreements are boundary-touching.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
