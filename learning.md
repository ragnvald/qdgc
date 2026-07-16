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

## Architecture notes

- Core geometry in `qdgc_py` is **pure stdlib** (own point-in-polygon,
  segment-intersection, ring handling) — deliberately no shapely/numpy in the
  required path.
- When variants disagree (SQL `qdgc_pg`, FME `qdgc_fme`, Python `qdgc_py`),
  `qdgc_py` + tests are authoritative — except on legacy-compat questions, where
  `qdgc_lib.py` wins.

<!-- Add new learnings below as they emerge. -->
