# QDGC Repository

Extended Quarter Degree Grid Cell (QDGC) — a discrete global grid system for
sharing generalised biodiversity and environmental data. This repository holds
several implementations of the same concept in one branch.

## Packages

| Package | Install | What it is |
|---|---|---|
| [`qdgc_py/`](qdgc_py/) | `pip install qdgc-py` | The reference implementation. Pure stdlib Python, and the arbiter when variants disagree. |
| [`qdgc_pg/`](qdgc_pg/) | `pgxn install qdgc` | PostgreSQL extensions. `qdgc` is pure SQL with no dependencies; `qdgc_postgis` adds geometry bindings. |

Encoding is bit-for-bit identical across both, enforced by a generated parity
fixture rather than hand-written expectations.

## Structure

- `qdgc_py/` — reusable Python library (`qdgc-py`); **start here**
- `qdgc_pg/` — the `qdgc` and `qdgc_postgis` PostgreSQL extensions
- `qdgc_delivery/` — historical country-GeoPackage production pipeline
- `qdgc_fme/` — FME workflow and packaging scripts
- `qdgc_py_legacy/` — legacy Python/ESRI-oriented scripts and templates

Work on shared changes in one place and keep variant-specific changes in the
matching folder. See `CLAUDE.md` for the working framework, `history.md` for
what changed and why, and `learning.md` for accumulated decisions and gotchas.

## Licence

Apache-2.0, matching [H3](https://h3geo.org/). A permissive licence is a
deliberate choice: the goal is a library any project can depend on.

## Reference

Larsen, R., Holmern, T., Prager, S. D., Maliti, H., and Røskaft, E. (2009).
Using the extended quarter degree grid cell system to unify mapping and sharing
of biodiversity data. African Journal of Ecology.
https://doi.org/10.1111/j.1365-2028.2008.00997.x

## Development

This project is developed by Ragnvald Larsen with the assistance of AI coding
tools. All commits are authored and reviewed by the maintainer.
