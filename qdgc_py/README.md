# qdgc-py

`qdgc-py` is a lightweight Python package for Extended Quarter Degree Grid Cell
(QDGC) codes.

It modernizes the legacy scripts in this repository into a reusable API that can
be imported by other projects.

QDGC is a hierarchical lon/lat square grid in EPSG:4326:

- level 0 cells are 1 deg x 1 deg
- each level splits each cell into 4 quadrants
- side length in degrees is `1.0 / (2 ** level)`

## Quickstart

From `qdgc/qdgc_py`:

```bash
pip install -e .
pytest -q
```

## API

```python
from qdgc_py import (
	encode,
	decode_bounds,
	decode_centroid,
	cell_to_boundary,
	cell_to_polygon,
	polygon_to_cells,
	bbox_to_cells,
	cell_to_parent,
	cell_to_children,
	average_cell_area,
	estimate_cell_count,
)

code = encode(38.98754324, -9.87548764, level=5)
bounds = decode_bounds(code)
center = decode_centroid(code)

ring_latlon = cell_to_boundary(code)  # (lat, lon)
ring_lonlat = cell_to_polygon(code)   # (lon, lat)

exterior = [
	(10.0, 20.0),
	(12.0, 20.0),
	(12.0, 22.0),
	(10.0, 22.0),
	(10.0, 20.0),
]
cells = polygon_to_cells(exterior, level=4, predicate="intersects")
bbox_cells = bbox_to_cells(10.0, 20.0, 12.0, 22.0, level=4)

parent = cell_to_parent(code)
children = cell_to_children(parent)

area_km2 = average_cell_area(4, lat=45.0)
estimate = estimate_cell_count(exterior, 4)
```

## API summary

- `encode(lon, lat, level)` -> `str`
- `encode_many(points, level)` -> `list[str]`
- `decode_bounds(code)` -> `QDGCCell`
- `decode_centroid(code)` -> `(lon, lat)`
- `cell_to_boundary(code)` -> `list[(lat, lon)]`
- `cell_to_polygon(code)` -> `list[(lon, lat)]`
- `bbox_to_cells(min_lon, min_lat, max_lon, max_lat, level)` -> `list[str]`
- `polygon_to_cells(exterior, level, holes=None, predicate="intersects")` -> `list[str]`
- `cell_to_parent(code, parent_level=None)` -> `str`
- `cell_to_children(code, child_level=None)` -> `list[str]`
- `level_degrees(level)` -> `float`
- `average_cell_area(level, lat=None, unit="km^2")` -> `float`
- `estimate_cell_count(exterior, level, bbox=None)` -> `int`
- `is_valid_cell(code)` -> `bool`

H3-style convenience aliases are also available:

- `latlng_to_cell(lat, lng, res)`
- `cell_to_latlng(cell)`
- `average_hexagon_area(res, unit="km^2")`

## Level table

Approximate side lengths and equatorial cell areas:

| level | side (deg) | side at equator (km) | area at equator (km^2) |
|---|---:|---:|---:|
| 0 | 1.0 | 111.32 | 12364.35 |
| 1 | 0.5 | 55.66 | 3091.09 |
| 2 | 0.25 | 27.83 | 772.77 |
| 3 | 0.125 | 13.92 | 193.19 |
| 4 | 0.0625 | 6.96 | 48.30 |
| 5 | 0.03125 | 3.48 | 12.07 |
| 6 | 0.015625 | 1.74 | 3.02 |

Values are approximate because metric size varies with latitude.

Boundary behavior at origin is deterministic and legacy-compatible:

```python
encode(0.0, 0.0, 1)  # E000N00C
encode(0.0, 0.0, 2)  # E000N00CC
```

## Current scope

- Deterministic `encode()` implementation compatible with legacy `qdgc_lib.py`
- Decode helpers for bounds and centroid
- Cell geometry, hierarchy, validation, and area estimation helpers
- Polygon/bbox to cells fill helpers in pure stdlib Python (no shapely dependency)
- Compatibility tests against legacy implementation plus AOI fill edge cases

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

- Performance tuning for very large AOIs and high levels
- Publish tagged releases to PyPI when API is stable
