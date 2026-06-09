# qdgc-py

`qdgc-py` is a lightweight Python package for Extended Quarter Degree Grid Cell
(QDGC) codes.

It modernizes the legacy scripts in this repository into a reusable API that can
be imported by other projects.

## Quickstart

From `qdgc/qdgc_py`:

```bash
pip install -e .
pytest -q
```

## API

```python
from qdgc_py import encode, decode_bounds, decode_centroid

code = encode(38.98754324, -9.87548764, level=5)
bounds = decode_bounds(code)
center = decode_centroid(code)
```

Boundary behavior at origin is deterministic and legacy-compatible:

```python
encode(0.0, 0.0, 1)  # E000N00C
encode(0.0, 0.0, 2)  # E000N00CC
```

## Current scope

- Deterministic `encode()` implementation compatible with legacy `qdgc_lib.py`
- Decode helpers for bounds and centroid
- Batch encoding helper
- Compatibility tests against legacy implementation

## Legacy compatibility and boundary behavior

This package intentionally preserves legacy QDGC behavior from `qdgc_lib.py`.

- Level 0 uses hemisphere-prefixed degree cells (`E/W` + 3-digit longitude,
	`N/S` + 2-digit latitude), consistent with the extended QDGC description.
- Subdivision letters follow the original QDGC orientation:
	`A=upper-left`, `B=upper-right`, `C=lower-left`, `D=lower-right`.
- Boundary points are deterministic. At `(lon=0, lat=0)`, encoding resolves to
	east/north and then to the lower-left subcell at each level, e.g.:
	- level 1: `E000N00C`
	- level 2: `E000N00CC`

The boundary choice at exact split lines is a legacy convention and is kept for
backward compatibility.

## Reference

Larsen, R., Holmern, T., Prager, S. D., Maliti, H., and Røskaft, E. (2009).
Using the extended quarter degree grid cell system to unify mapping and
sharing of biodiversity data. African Journal of Ecology.
https://doi.org/10.1111/j.1365-2028.2008.00997.x

## Versioning and releases

- Current package version is defined in `pyproject.toml` (`project.version`).
- Bump the version when behavior or public API changes.
- Tag releases in git using the same version (for example `v0.1.1`).

## Next steps

- Add polygon-to-cells helpers for AOI generation
- Publish tagged releases to PyPI when API is stable
