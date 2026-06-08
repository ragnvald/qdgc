# qdgc-py

`qdgc-py` is a lightweight Python package for Extended Quarter Degree Grid Cell
(QDGC) codes.

It modernizes the legacy scripts in this repository into a reusable API that can
be imported by other projects (for example MESA geocode providers).

## Install (local)

```bash
pip install -e .
```

Run from the `qdgc_python/qdgc_py` folder.

## API

```python
from qdgc_py import encode, decode_bounds, decode_centroid

code = encode(38.98754324, -9.87548764, level=5)
bounds = decode_bounds(code)
center = decode_centroid(code)
```

## Current scope

- Deterministic `encode()` implementation compatible with legacy `qdgc_lib.py`
- Decode helpers for bounds and centroid
- Batch encoding helper
- Compatibility tests against legacy implementation

## Next steps for MESA integration

- Add polygon-to-cells helpers for AOI generation
- Add provider adapter so MESA can switch between H3 and QDGC
- Publish tagged releases to PyPI when API is stable
