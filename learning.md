# Learning

Durable knowledge, gotchas, and settled decisions for this project. Check here
before solving a problem; add to it when you learn something worth keeping. This
is a knowledge base, not a changelog — for the timeline see `history.md`.

## Model and goals

- The north star is **H3**: a small, stable, well-documented public API usable
  as a library across languages. `qdgc_py` is the reference implementation and
  already ships H3-style aliases (`latlng_to_cell`, `cell_to_latlng`,
  `average_hexagon_area`).

## Encoding: locked conventions (do not change silently)

- **Levels:** level 0 cells are 1° × 1°; each level splits into 4 quadrants;
  side length in degrees is `1.0 / (2 ** level)`.
- **Level-0 code:** hemisphere-prefixed degree cells — `E/W` + 3-digit longitude,
  `N/S` + 2-digit latitude (e.g. `E000N00`).
- **Subcell letters:** `A = upper-left`, `B = upper-right`, `C = lower-left`,
  `D = lower-right`. This orientation is legacy and must not be reordered.
- **Boundary behavior at split lines is deterministic and legacy-compatible.**
  At `(lon=0, lat=0)` encoding resolves east/north, then to the lower-left
  subcell at each level: level 1 → `E000N00C`, level 2 → `E000N00CC`.
- The authority for encoding output is `qdgc_py_legacy/tools/qdgc_lib.py`, guarded
  by the compat tests in `qdgc_py/tests/test_qdgc_py.py`. Changing output = major
  version bump, flagged loudly.

## Licensing

- **The project is Apache-2.0**, matching H3. This is a deliberate, settled
  decision: a permissive license is required for the library-first goal so any
  project (commercial, MIT/Apache) can depend on `qdgc-py`. GPL's strong copyleft
  would block broad adoption, so do not relicense back to GPL/LGPL without an
  explicit maintainer decision.
- Keep three things in sync if the license ever changes: root `LICENSE`,
  `pyproject.toml` `license` field, and the `License ::` trove classifier.

## Downstream consumer: MESA vendors qdgc_py (contract)

MESA (a desktop geospatial app) uses this library, but **not via pip**. It carries a
verbatim vendored copy of `__init__.py` + `core.py` at `code/qdgc_py/` (copied from
`src/qdgc_py/`), imported as `import qdgc_py`, and bundled into a frozen PyInstaller
build. MESA 5 stays on the vendored copy; a pip migration (like `h3==4.2.2`) is a future
release, not v5. Updates reach MESA only by manual re-vendoring, so upstream changes
must honor this contract:

- **Zero runtime dependencies in the core.** `core.py` must stay pure stdlib — no
  transitive deps. Adding a runtime import breaks the vendoring contract and the frozen
  build. (This hardens the existing "dependency-light" rule into a firm one.)
- **Public API backward-compatible with 0.1.0.** Hand re-vendoring makes silent
  signature/behavior drift costly. The surface MESA actually calls:
  - `polygon_to_cells(exterior, level, holes=..., predicate="intersects")`
  - `cell_to_polygon(code)`
  - `estimate_cell_count(None, level, bbox=(minx, miny, maxx, maxy))`
  - `__version__`
- **Treat as a stable contract** the `(lon, lat)` coordinate convention, the `predicate`
  semantics, and the QDGC code/quadrant encoding. Changing any of these changes MESA's
  generated grids — it is a major, loudly-flagged change, not a silent one.
- **Flag any release beyond 0.1.0.** MESA re-vendors deliberately (bumping the version
  note in its `code/qdgc_py/VENDORED.md`), never automatically. New releases should be
  announced so downstream vendoring is intentional.

## Architecture notes

- Core geometry in `qdgc_py` is **pure stdlib** (own point-in-polygon,
  segment-intersection, ring handling) — deliberately no shapely/numpy in the
  required path.
- When variants disagree (SQL `qdgc_pg`, FME `qdgc_fme`, Python `qdgc_py`),
  `qdgc_py` + tests are authoritative — except on legacy-compat questions, where
  `qdgc_lib.py` wins.

## Encoding: how the quadrant algorithm actually works

The legacy encoder (`qdgc_lib.py`, mirrored in `core._step`) is written as a
four-way quadrant tree with sixteen branches. It is tempting to "simplify" that
into `abs()` plus two fixed hemisphere flags. **That is wrong**, and the failure
is subtle enough to survive a million random test points.

Two things make it wrong:

1. **The quadrant is re-derived from the *current* residual at every step**, not
   fixed once from the input. Signs are preserved as the residual is doubled, so
   the flags usually look constant — until a residual lands exactly on `0.0`.
2. **A residual of exactly `0.0` falls into the positive branch**, because the
   branch order tests `>= 0` before `<= 0`. From then on the cell resolves
   south-west at every remaining level.

That is why deep codes tail off in `C`, not `B`: `encode(-77.25, -72.25, 4)` is
`W077S72BCCC`, and a fixed-flag implementation produces `W077S72BCBB`. Random
interior points never expose this; only coordinates whose residual reaches zero
do.

The correct reduction — verified bit-for-bit against `core.encode` over ~1.2M
cases, and what `qdgc_pg` implements — keeps two *signed* accumulators and
recomputes per step:

```
east_pos  = u >= 0
north_pos = (v >= 0) if east_pos else (v > 0)
far_lon   = (u >= 0.5) if east_pos  else (u <= -0.5)
far_lat   = (v >= 0.5) if north_pos else (v <= -0.5)
is_east   = far_lon if east_pos  else not far_lon
is_north  = far_lat if north_pos else not far_lat
letter    = B if (north and east) else A if north else D if east else C
```

Also locked, and easy to "fix" by accident: **`_normalize_fraction` only reduces
values strictly outside `[-1, 1]`**, so exactly `±1.0` is left alone and behaves
as a permanent "far half" residual. `encode(1.0, ...)` therefore yields all `B`
or all `D`. This is legacy behaviour and part of the contract.

## Quadtree descent is equivalent to encoding centroids

`decode_bounds` subdivides with a fixed orientation (A = NW, B = NE, C = SW,
D = SE) that does **not** depend on hemisphere, unlike the encoder's letter
choice. Descending that quadtree and concatenating letters produces exactly the
code that `encode(cell_centroid, level)` produces — verified over 16 380 cells
across all four hemispheres.

This is what lets `qdgc_pg.qdgc_polygon_to_cells` fill an area by pruning
descent instead of encoding points: start from the degree squares meeting the
AOI, split only cells that still meet it, and never call the encoder at all.
Cost scales with the AOI *boundary* rather than its envelope area. Cells found
wholly inside carry a `contained` flag so their descendants skip predicate
tests entirely.

## PostgreSQL gotchas found the hard way

- **`GREATEST`/`LEAST` ignore NULL arguments** rather than propagating them:
  `least(90.0, NULL)` is `90.0`, not `NULL`. A clamp written as
  `COALESCE(greatest(-90, least(90, lat)), 0)` silently turns "no latitude
  given" into "latitude 90" — which returned a polar sliver (27 km²) instead of
  an equatorial cell (12 364 km²). Handle NULL *before* the clamp. This is the
  opposite of Python's `min`/`max`.
- **A record variable cannot be assigned from a function call.**
  `b := qdgc_cell_to_bounds(code)` fails; use
  `SELECT * INTO b FROM qdgc_cell_to_bounds(code) AS t`.
- **`FOR x IN SELECT generate_series(...)` makes `x` a `bigint`**, which will
  not match an `integer` parameter and produces a "function does not exist"
  error. Use `FOR x IN 0..n` when you want an integer.
- **SRID 0 must be stamped, not assumed.** Passing a SRID-0 geometry straight
  into `ST_Intersects` against a 4326 geometry raises a mixed-SRID error;
  `ST_SetSRID(geom, 4326)` first.
- **`ST_Dump` returns an EMPTY `path` array for a single Polygon.** So
  `(ST_Dump(g)).path[1]` is NULL for the most common input, and any join keyed
  on it silently matches nothing. Use `row_number() OVER ()` to number parts.
- **`array_agg` over zero rows returns NULL, and `NULL <> ARRAY[...]` is NULL,
  not true.** A test written as `IF result <> expected THEN RAISE` therefore
  passes silently when the query returns nothing — which is exactly the failure
  it was meant to catch. Always test `IS NULL` explicitly first. This hid the
  `ST_Dump` bug above through a full test run.

## Multi-part fills must be per part, not per collection

`geocode_manage.qdgc_from_union` splits a MultiPolygon and calls
`qdgc_py.polygon_to_cells` once per part, unioning the code sets. **Each part
therefore gets its own half-open envelope.** Filling a MultiPolygon against one
shared envelope keeps cells hugging an inner part's upper edge — 258 extra
cells at level 7 on a two-square test, all along the first square's edge.

This matters because a real AOI (a union of buffered assets) is usually
multi-part, and the error is invisible on any single-polygon test.

## PGXN packaging notes

- The distribution is `qdgc` and provides **both** extensions; one PGXN
  distribution can declare several in `provides`.
- PGXN takes an **uploaded archive**, not a repository, so living in a monorepo
  subdirectory is fine. `git archive --prefix=qdgc-<version>/ HEAD:qdgc_pg`
  produces exactly what is wanted and cannot include untracked files.
- **The archive carries no licence unless one is inside `qdgc_pg/`.** The root
  `LICENSE` is not in the build context. `META.json` declaring `apache_2_0` is
  metadata, not a licence grant.
- The version must agree in **four** places: `META.json`, `qdgc.control`,
  `qdgc_postgis.control` and the generated `qdgc--<version>.sql` filenames.
  `tools/make_dist.py` refuses to build otherwise.
- **Do not ship a `REGRESS` line you cannot satisfy.** PGXN users run
  `make installcheck`; naming test files that do not exist, with no
  `expected/*.out`, is worse than having no test target at all.
- Account approval on PGXN Manager is **manual** and includes a free-text "why
  do you want an account?" field. Register early; the wait is the long pole.

## Cross-variant parity: how it is enforced

`qdgc_pg` does not carry hand-written expected values. `tools/gen_parity_fixture.py`
generates ~22 000 encode vectors and ~6 500 decode vectors **from `qdgc_py.core`**,
weighted towards the cases above (exact midpoints, signed zeros, poles,
antimeridian, the `±1.0` quirk), and the SQL suite is required to match them
exactly. If `core.py` changes, regenerate and the suite reports what moved.

Area fills are exact too, verified by `tools/compare_fill.py` over six shapes.
Reaching that required matching two rules of `qdgc_py` that pull in **opposite**
directions, and getting only one of them produces a fill that looks right on
simple shapes:

- **The AOI envelope is half-open on its upper edges.** `bbox_to_cells` derives
  candidates with `ceil(...) - 1`, so a cell lying outside the AOI but sharing
  an edge with it is excluded. `ST_Intersects` disagrees — it reports a
  zero-area touch as an intersection — so the descent must apply the envelope
  test explicitly. This is invisible when the AOI happens to align to degree
  lines, which is why an aligned test box hid it.
- **A cell touching an *interior* edge is included**, because
  `_point_on_segment` makes `_point_in_ring` return True for points lying on
  the boundary. So the fix is *not* "exclude anything that merely touches" —
  that would drop cells against a re-entrant notch.

Only one divergence remains, deliberately: **cell-count estimates**. The SQL
measures polygon area on the WGS84 spheroid; `qdgc_py` uses an equirectangular
approximation. Both are guards, both capped by the exact envelope count.

## Fill performance: when the quadtree descent actually wins

Measured on PostgreSQL 17.10 / PostGIS 3.6.4 against the legacy full-envelope
`ST_SquareGrid` + `ST_Intersects`, at level 9:

| AOI | Fill vs envelope | Speedup |
|---|---|---|
| Thin diagonal band | sparse | **8.5x** |
| Convoluted blob, 240 vertices | moderate | 1.3x |
| Triangle | half | 1.2x |
| Aligned 1x1 degree box | dense | **0.5x** |

The descent is not universally faster, and claiming so would be wrong. It wins
when the AOI is sparse within its bounding box — countries, coastlines, river
corridors — and loses about 2x when the AOI nearly fills its envelope, because
it pays log-depth work per cell that a flat grid does not. Real AOIs are
sparse, so this is the right trade, but a dense-rectangle benchmark will make
it look like a regression.

## PostGIS packaging decisions

- **Two extensions, mirroring h3 / h3_postgis.** `qdgc` is pure SQL with zero
  dependencies and `trusted = true`; `qdgc_postgis` holds everything touching a
  geometry. Keeping the core PostGIS-free is what allows it to install on
  managed platforms that reject compiled extensions.
- **Codes stay `text`; no custom type.** H3 needs an `h3index` type because its
  cells are 64-bit integers. QDGC codes are strings whose hierarchy *is* prefix
  containment, so `child LIKE parent || '%'` is a btree range scan and ancestor
  queries need no operator class at all. h3-pg had to ship spgist and gist
  opclasses to get the equivalent.
- **Every scalar function is `IMMUTABLE STRICT PARALLEL SAFE`**, copied from
  h3-pg. This is what makes expression indexes and parallel plans work.
- **Areas use `geography`, never a projected SRID.** The legacy SQL hardcoded
  `ST_Transform(geom, 102022)` (ESRI Africa Albers) for every region including
  Asia and South America, and that SRID is not in a stock PostGIS
  `spatial_ref_sys` at all.

## H3 for PostgreSQL: do not build one

Verified 2026-07-21. `h3-pg` is the only living H3 binding for Postgres, and it
moved: `zachasme/h3-pg` was archived 2025-12-30, development is now at
**`postgis/h3-pg`** under the PostGIS org (v4.5.0, Apache-2.0). It is a C
extension requiring CMake and the H3 C library.

Practical notes for anything that has to run both grids:

- The function is **`h3_latlng_to_cell`**, not `h3_lat_lng_to_cell` — renamed in
  4.2.3.
- v4.5.0 fixed a btree comparator sign bug that caused **reversed `ORDER BY` and
  wrong range scans**; indexes must be rebuilt when upgrading past it.
- Available on AWS RDS/Aurora, Neon and Crunchy Bridge; **not** on Azure
  Flexible Server, Google Cloud SQL or Supabase.
- The official `postgis/postgis` Docker image bundles h3 only in `-master` tags,
  which track a development branch. For a stable base, install the PGDG package
  (`postgresql-NN-h3`) onto a released tag instead.
- No QDGC Postgres extension exists anywhere else, and no pure-SQL/no-compile
  DGGS of any kind exists for Postgres — which is why `qdgc` being `trusted` and
  PGXN/pg_tle-eligible is worth preserving.

<!-- Add new learnings below as they emerge. -->
