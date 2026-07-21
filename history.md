# History

Reverse-chronological log of meaningful changes. See `CLAUDE.md` for the entry
format and when to add one.

## 2026-07-21 — Rebuild qdgc_pg as a PostgreSQL extension; split out delivery
- What: Replaced the four standalone `create_function_*.sql` scripts with a pair
  of packaged extensions in `qdgc_pg/` — `qdgc` (pure SQL, zero dependencies,
  `trusted = true`) and `qdgc_postgis` (geometry/geography bindings) — at version
  0.1.0, mirroring the `h3` / `h3_postgis` split. Added ~20 documented functions
  covering encode, decode, hierarchy, level metrics, bbox fills and area fills;
  a PGXS `Makefile`; `tools/build_sql.py` to concatenate numbered sources into
  versioned install scripts; `tools/gen_parity_fixture.py` to generate test
  vectors from `qdgc_py.core`; and `tools/run_tests.py`, which can run the suite
  locally or over SSH against a remote host. Moved the country-GeoPackage
  production pipeline (`run_qdgc_*`, the FME workspace, the shipped readme) and
  the superseded plpython3u functions to a new `qdgc_delivery/`.
- Why: The old scripts could not be used from a server. `qdgc_getlonlat` was
  written in `plpython3u`, an untrusted language needing superuser and
  unavailable on most managed PostgreSQL; `qdgc_fillqdgc` hardcoded the table
  names `tbl_countries`/`tbl_qdgc`, dropped and recreated its output table, and
  returned nothing despite `RETURNS SETOF text`. There was no decode path at all.
  MESA's server imports backup packages into PostGIS and must be able to
  establish a QDGC geocode on demand, which needs composable functions.
- Impact: New capability, no change to any QDGC code ever produced — encoding is
  bit-for-bit identical to `qdgc_py`, verified by 22 053 encode vectors and 6 581
  decode cells generated from `core.py` and run against PostgreSQL 17.10 /
  PostGIS 3.6.4. Areas are now measured with `geography` instead of the
  hardcoded ESRI Africa Albers SRID 102022, which was wrong everywhere outside
  Africa and absent from stock PostGIS. `qdgc_polygon_to_cells` is a pruning
  quadtree descent rather than a full-envelope `ST_SquareGrid`. Callers of the
  old `qdgc_fillqdgc` should move to `qdgc_polygon_to_cells`; the legacy
  functions remain in `qdgc_delivery/legacy/` for reproducibility only.
  Known, documented divergences from `qdgc_py`: GEOS-vs-epsilon classification
  of cells that merely touch an AOI edge, and spheroidal-vs-equirectangular
  polygon area in the cell-count estimate.

## 2026-07-16 — Add working framework (CLAUDE.md, history.md, learning.md)
- What: Added `CLAUDE.md` as the repo's working framework, plus this
  `history.md` and `learning.md`.
- Why: Establish an H3-inspired, library-first direction for QDGC and carry
  decisions/lessons across sessions and contributors.
- Impact: Process only; no code or API change.

## 2026-07-16 — PyPI publishing setup for qdgc-py
- What: Added root `LICENSE` (verbatim GPL-3.0 from FSF), a tag-triggered
  release workflow (`.github/workflows/qdgc_py-release.yml`) using PyPI Trusted
  Publishing (OIDC), and Install/Publishing docs in `qdgc_py/README.md`.
- Why: Make `pip install qdgc-py` possible in the H3-style, and automate
  token-free releases from git tags.
- Impact: No code/API change. Manual step remaining: register the repo as a
  trusted publisher on pypi.org (environment `pypi`) and confirm the `qdgc-py`
  name is free.

## 2026-07-16 — Relicense qdgc-py from GPL-3.0 to Apache-2.0
- What: Replaced root `LICENSE` with verbatim Apache-2.0 text and updated
  `qdgc_py/pyproject.toml` license field and classifier accordingly.
- Why: Match H3 (Apache-2.0). The library-first goal needs a permissive license
  so projects under any license (commercial, MIT/Apache) can depend on it; GPL's
  strong copyleft would block that.
- Impact: Licensing only, no code/API change. Supersedes the GPL-3.0 choice from
  the earlier entry today.

## 2026-07-16 — Milestone: qdgc-py 0.1.0 published to PyPI
- What: First public release. Tag `v0.1.0` triggered the release workflow, which
  ran green end to end (tests, build, twine check, Trusted Publishing upload).
  `pip install qdgc-py` now works for everyone.
- Why: Deliver the H3-style goal — QDGC as an open, installable library.
- Impact: Package is public at https://pypi.org/project/qdgc-py/ under
  Apache-2.0. Version `0.1.0` is now permanently reserved on PyPI. Future
  releases follow the same bump-version -> tag -> push flow.

## 2026-07-16 — Announced qdgc-py on LinkedIn
- What: Ragnvald published a LinkedIn post announcing the qdgc-py library,
  tying it back to the 2009 extended-QDGC paper. Post: https://lnkd.in/p/eZCbfgGP
- Why: Public launch / outreach for the library to the GIS and biodiversity
  community.
- Impact: No code change. First external announcement of the package.

## 2026-07-16 — Added qdgc-py note to the ResearchGate article
- What: Posted a short update on the 2009 paper's ResearchGate page pointing to
  the qdgc-py library (used the ~300-char short form due to the field limit).
- Why: Connect the published method to its open-source implementation for
  researchers arriving via the paper.
- Impact: No code change. Second external announcement of the package (after
  LinkedIn).

## 2026-07-16 — Recorded MESA vendoring contract
- What: Documented that MESA 5 consumes qdgc_py as a hand-vendored, pip-free copy
  (frozen PyInstaller build), and the constraints that places on releases —
  captured in `learning.md` and `CLAUDE.md`. Also fixed MESA's
  `code/qdgc_py/VENDORED.md` (it still claimed qdgc-py "is not published on PyPI").
- Why: Manual re-vendoring means upstream changes must stay compatible or they
  silently break MESA's frozen build and generated grids.
- Impact: Docs only, no code change. Firm constraints going forward: zero runtime
  deps in `core.py`, public API stable at 0.1.0, and flag any release beyond
  0.1.0 for deliberate re-vendoring.

<!-- Add new entries above this line, newest first. -->
