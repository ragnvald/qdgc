Changelog
=========

All notable changes to the `qdgc` and `qdgc_postgis` extensions.

Encoding output is stable within a major version. Any change to a code this
library produces is a major bump, flagged loudly — see `CLAUDE.md` in the
repository root.

0.1.0 — unreleased
------------------

First release.

### `qdgc` (pure SQL, no dependencies, trusted)

- Encoding: `qdgc_encode`, `qdgc_latlng_to_cell`, `qdgc_degree_prefix`,
  `qdgc_normalize_fraction`.
- Decoding: `qdgc_cell_to_bounds`, `qdgc_cell_to_lonlat`, `qdgc_cell_to_latlng`,
  `qdgc_get_level`, `qdgc_is_valid_cell`, `qdgc_code_pattern`.
- Hierarchy: `qdgc_cell_to_parent`, `qdgc_cell_to_children`.
- Metrics: `qdgc_level_degrees`, `qdgc_get_num_cells`, `qdgc_average_cell_area`,
  `qdgc_version`.
- Bounding-box fills: `qdgc_bbox_to_cells`, `qdgc_bbox_cell_count`,
  `qdgc_wrap_lon`, `qdgc_index_range`. Antimeridian-crossing boxes are supported
  by passing `min_lon > max_lon`.

### `qdgc_postgis` (requires PostGIS)

- Geometry and geography bindings: `qdgc_latlng_to_cell(geometry|geography)`,
  `qdgc_cell_to_geometry`, `qdgc_cell_to_geography`,
  `qdgc_cell_to_boundary_geometry`, `qdgc_cell_to_boundary_geography`,
  `qdgc_cell_area_km2`.
- Area fills: `qdgc_polygon_to_cells` with `intersects`, `centroid` and
  `contains` predicates, implemented as a pruning quadtree descent; and
  `qdgc_estimate_cell_count` as a guard before a large fill.

### Compatibility

Encoding, decoding, hierarchy and area fills are bit-for-bit identical to the
[`qdgc-py`](https://pypi.org/project/qdgc-py/) reference implementation,
enforced by a fixture generated from it — 22 053 encode vectors and 6 581
decode cells, weighted towards exact quadrant midpoints, signed zeros, the
poles, the antimeridian, and the legacy convention that exactly ±1.0 is not
reduced to a fraction.

Cell-count estimates differ slightly by design: this extension measures polygon
area on the WGS84 spheroid, while `qdgc-py` uses an equirectangular
approximation. Both are guards, and both are capped by the exact envelope count.

Areas are measured with `geography`, replacing the earlier scripts' hardcoded
`ST_Transform(geom, 102022)` (ESRI Africa Albers), which was applied to every
region regardless of location and is absent from a stock PostGIS
`spatial_ref_sys`.
