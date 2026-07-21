"""Generate the legacy-parity fixture for the SQL extension from qdgc_py.

`qdgc_py` is the arbiter for QDGC behaviour (see CLAUDE.md), so the SQL is
tested against vectors produced by core.py rather than against hand-written
expectations. Regenerate whenever core.py changes:

    python tools/gen_parity_fixture.py

Writes test/data/parity_encode.csv and test/data/parity_decode.csv.
"""
from __future__ import annotations

import csv
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT.parent / "qdgc_py" / "src"))

from qdgc_py import core  # noqa: E402

OUT_DIR = ROOT / "test" / "data"
SEED = 20260721


def encode_points() -> list[tuple[float, float, int]]:
    """(lon, lat, level) triples worth pinning down."""
    rng = random.Random(SEED)
    rows: list[tuple[float, float, int]] = []

    # Adversarial: exact quadrant midpoints, signed zeros, the +/-1.0 legacy
    # quirk, and the poles/antimeridian.
    edge_fracs = (0.0, 0.25, 0.5, 0.75, 1.0, -0.25, -0.5, -0.75, -1.0)
    edge_bases = (-2, -1, 0, 1, 2, 31, -31)
    edges = [float(b) + f for b in edge_bases for f in edge_fracs]
    for lon in edges:
        for lat in edges:
            for level in (0, 1, 2, 5, 7):
                rows.append((lon, lat, level))

    for lon, lat in ((0.0, 0.0), (-0.0, 0.0), (0.0, -0.0), (-0.0, -0.0),
                     (180.0, 90.0), (-180.0, -90.0), (-180.0, 90.0), (180.0, -90.0),
                     (-0.5, 0.0), (-0.25, 0.0), (0.0, -0.5), (-1.0, 0.0)):
        for level in range(0, 9):
            rows.append((lon, lat, level))

    # Random interior points across the globe.
    for _ in range(1500):
        rows.append((rng.uniform(-180, 180), rng.uniform(-90, 90),
                     rng.choice([0, 1, 3, 5, 7, 10, 12])))

    # Cell centres, which is what an area fill actually produces.
    for level in (1, 4, 7, 10):
        side = core.level_degrees(level)
        for _ in range(150):
            rows.append((-180.0 + (rng.randrange(int(360 / side)) + 0.5) * side,
                         -90.0 + (rng.randrange(int(180 / side)) + 0.5) * side,
                         level))

    return rows


def decode_codes(encode_rows) -> list[str]:
    """Codes to check bounds/level/parent round-trips against."""
    codes = {core.encode(lon, lat, level) for lon, lat, level in encode_rows}
    # A few explicit ones so the fixture is readable even if the random part
    # changes: the locked (0,0) case and one cell per hemisphere.
    codes.update({"E000N00", "E000N00C", "E031N02ABCD", "W001S01",
                  "W180S90", "E179N89DDDD", "W077S72BCCC"})
    return sorted(codes)


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    rows = encode_points()
    enc_path = OUT_DIR / "parity_encode.csv"
    with enc_path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(["lon", "lat", "level", "code"])
        for lon, lat, level in rows:
            w.writerow([repr(lon), repr(lat), level, core.encode(lon, lat, level)])
    print(f"  {enc_path.relative_to(ROOT)}  {len(rows)} encode vectors")

    codes = decode_codes(rows)
    dec_path = OUT_DIR / "parity_decode.csv"
    with dec_path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(["code", "level", "min_lon", "min_lat", "max_lon", "max_lat",
                    "centroid_lon", "centroid_lat"])
        for code in codes:
            cell = core.decode_bounds(code)
            clon, clat = cell.centroid
            w.writerow([code, cell.level,
                        repr(cell.min_lon), repr(cell.min_lat),
                        repr(cell.max_lon), repr(cell.max_lat),
                        repr(clon), repr(clat)])
    print(f"  {dec_path.relative_to(ROOT)}  {len(codes)} decode vectors")

    print(f"generated from qdgc_py {getattr(core, '__version__', 'core')} "
          f"at {ROOT.parent / 'qdgc_py'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
