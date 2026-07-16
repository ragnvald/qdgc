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

<!-- Add new learnings below as they emerge. -->
