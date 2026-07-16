# CLAUDE.md

Working framework for this repository. Read this first, every session, before
touching code.

## Mission

Turn QDGC (Extended Quarter Degree Grid Cell) into an **open, reusable library
framework** — the way [H3](https://h3geo.org/) is for hexagons. The goal is not
a set of one-off scripts, but clean, well-documented, importable libraries that
any project can use to generate, decode, and reason about QDGC codes.

H3 is the model to aim for:

- A small, stable, well-named public API (`latlng_to_cell`, `cell_to_boundary`,
  `polygon_to_cells`, parent/children hierarchy, area helpers…).
- Deterministic, documented behavior — including boundary/edge cases.
- Language bindings that share one conceptual model.
- Excellent docs and a level/resolution reference table.
- Semantic versioning and tagged releases.

The reference package `qdgc_py/` already exposes H3-style aliases
(`latlng_to_cell`, `cell_to_latlng`, `average_hexagon_area`). Keep leaning that
direction: **API ergonomics and documentation are first-class features, not
afterthoughts.**

## Repository layout

The repo holds several variants of the same QDGC concept in one branch. Work on
shared ideas in one place; keep variant-specific changes in the matching folder.

- `qdgc_py/` — **the reference implementation.** Reusable Python library
  (`qdgc-py`), pure stdlib, tested. New capability work starts here.
- `qdgc_py_legacy/` — legacy Python / ESRI-oriented scripts. Source of truth for
  historical/compatible behavior. Do not extend; port forward into `qdgc_py`.
- `qdgc_pg/` — Postgres/SQL implementation and run scripts.
- `qdgc_fme/` — FME workflow and packaging scripts/output.

The canonical algorithm lives in `qdgc_py/src/qdgc_py/core.py`. When another
variant (SQL, FME) and the Python package disagree, `qdgc_py` + its tests are
the arbiter — unless the disagreement is legacy-compatibility (see below).

## Non-negotiables

1. **Legacy compatibility is a contract.** Encoding must stay bit-for-bit
   compatible with `qdgc_py_legacy/tools/qdgc_lib.py`, including the deterministic
   boundary conventions (`A/B/C/D` subcell orientation; `(0,0)` resolves E/N then
   lower-left, e.g. level 1 → `E000N00C`). Compatibility tests guard this. If you
   ever intend to change encoding output, that is a **major** version bump and
   must be flagged loudly — never a silent change.
2. **`qdgc_py` stays dependency-light.** Pure stdlib for core geometry (no
   shapely/numpy in the required path). Optional extras are fine behind
   `[project.optional-dependencies]`.
3. **Every public function is tested.** Add cases to
   `qdgc_py/tests/test_qdgc_py.py`. Cover the happy path, a boundary/edge case,
   and legacy-compat where relevant.
4. **Public API is documented where it lives.** Update `qdgc_py/README.md` (API
   summary, level table, examples) in the same change that adds or alters API.
5. **Semantic versioning.** Bump `pyproject.toml` `project.version` when public
   behavior or API changes; tag releases (`vX.Y.Z`). Additive = minor,
   fixes = patch, output/API change = major.

## Working protocol — history.md and learning.md

Two living documents at the repo root carry memory across sessions and
contributors. **Keeping them current is part of "done," not optional cleanup.**

### `history.md` — what changed and why

An append-only, reverse-chronological log of meaningful work. After a change
that alters behavior, API, structure, or a decision worth remembering, add an
entry:

```
## YYYY-MM-DD — <short title>
- What: <what actually changed>
- Why: <the reason / problem it solved>
- Impact: <API/behavior/version effects, migrations needed>
```

This is the narrative git history can't give at a glance. Skip trivial edits.

### `learning.md` — durable knowledge and decisions

The accumulated "how this project thinks." Not a changelog — a knowledge base.
Add to it when you discover a gotcha, settle a design question, or establish a
convention that future work should honor. Examples of what belongs here:

- Why the `(0,0)` boundary resolves the way it does (and that it's locked).
- The A/B/C/D subcell orientation and why it must not be reordered.
- H3 API-mapping decisions (which H3 names we mirror, which we deliberately don't).
- Performance findings for large AOIs / high levels.
- Cross-variant discrepancies (SQL vs Python) and which is authoritative.

Before solving a problem, **check `learning.md` first** — it may already be
answered. When you learn something the hard way, write it down so the next
session doesn't relearn it.

## Commits and attribution

- **Commits are authored in the maintainer's name.** Do not add AI co-author
  trailers, "Generated with…" lines, or any AI attribution to commit messages.
- AI assistance is disclosed once, in the root `README.md` ("Development"
  section) — not per commit.
- Write plain, descriptive commit messages focused on what changed and why.

## Definition of done

- [ ] Code + tests updated together; `pytest -q` passes in `qdgc_py/`.
- [ ] Public API change reflected in `qdgc_py/README.md`.
- [ ] Legacy-compat tests still green (or a deliberate, flagged major bump).
- [ ] Version bumped if public behavior/API changed.
- [ ] `history.md` updated with what/why/impact.
- [ ] `learning.md` updated if a durable lesson or decision emerged.

## Quick commands

```bash
# from qdgc_py/
pip install -e .
pytest -q
```

## Reference

Larsen, R., Holmern, T., Prager, S. D., Maliti, H., and Røskaft, E. (2009).
Using the extended quarter degree grid cell system to unify mapping and sharing
of biodiversity data. African Journal of Ecology.
https://doi.org/10.1111/j.1365-2028.2008.00997.x
