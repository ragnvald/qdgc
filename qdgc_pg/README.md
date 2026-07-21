qdgc for PostgreSQL / PostGIS
=============================

Extended Quarter Degree Grid Cell (QDGC) codes as a pair of PostgreSQL
extensions, so that grid generation can happen **inside the database** next to
the data instead of being exported, processed elsewhere and loaded back.

Two extensions, mirroring the way [h3-pg](https://github.com/postgis/h3-pg)
splits `h3` from `h3_postgis`:

| Extension | Requires | What it gives you |
|---|---|---|
| `qdgc` | nothing — pure SQL, `trusted` | encode, decode, hierarchy, level metrics, bbox fills |
| `qdgc_postgis` | `qdgc`, `postgis` | geometry/geography bindings and area fills |

Keeping the core free of PostGIS means it installs anywhere, including managed
platforms that will not accept a compiled extension.

Encoding is **bit-for-bit identical to `qdgc_py`**, which is the arbiter for
QDGC behaviour in this repository. That is enforced by a generated fixture, not
by hand-written expectations — see [Testing](#testing).

Install
-------

```bash
make install
psql -d yourdb -c "CREATE EXTENSION qdgc;"
psql -d yourdb -c "CREATE EXTENSION qdgc_postgis;"   # needs PostGIS
```

There is nothing to compile. `make install` only copies the `.control` files
and the generated `qdgc--0.1.0.sql` / `qdgc_postgis--0.1.0.sql` into the
server's extension directory.

Both extensions are relocatable, but the functions call each other by
unqualified name, so install them into a schema that is on your `search_path`
(the default, `public`, is fine).

API
---

### Encoding

| Function | Returns | Notes |
|---|---|---|
| `qdgc_encode(lon, lat, level)` | `text` | primary form, `(lon, lat)` order |
| `qdgc_latlng_to_cell(lat, lng, level)` | `text` | h3-style alias, reversed order |
| `qdgc_latlng_to_cell(geometry, level)` | `text` | transforms non-4326 input |
| `qdgc_latlng_to_cell(geography, level)` | `text` | |
| `qdgc_degree_prefix(lon, lat)` | `text` | the level 0 code, e.g. `E031N02` |

### Decoding

| Function | Returns |
|---|---|
| `qdgc_cell_to_bounds(cell)` | `(min_lon, min_lat, max_lon, max_lat)` |
| `qdgc_cell_to_lonlat(cell)` | `point` — x = lon, y = lat |
| `qdgc_cell_to_latlng(cell)` | `(lat, lng)`, h3-style |
| `qdgc_cell_to_geometry(cell)` | `POINT` geometry, EPSG:4326 |
| `qdgc_cell_to_boundary_geometry(cell)` | `POLYGON` geometry, EPSG:4326 |
| `qdgc_cell_to_geography(cell)` / `..._boundary_geography(cell)` | geography forms |
| `qdgc_get_level(cell)` | `integer`, `NULL` if the code is invalid |
| `qdgc_is_valid_cell(cell)` | `boolean` |

### Hierarchy

| Function | Returns |
|---|---|
| `qdgc_cell_to_parent(cell [, parent_level])` | `text` |
| `qdgc_cell_to_children(cell [, child_level])` | `setof text` |

QDGC codes are strings, and the hierarchy is plain **prefix containment**. A
descendant test is `child LIKE parent || '%'`, so a btree index on the code
column already serves ancestor range scans — no custom operator class needed.

### Areas of interest

| Function | Returns |
|---|---|
| `qdgc_polygon_to_cells(geometry, level [, predicate])` | `setof text` |
| `qdgc_bbox_to_cells(min_lon, min_lat, max_lon, max_lat, level)` | `setof text` |
| `qdgc_estimate_cell_count(geometry, level)` | `bigint` |
| `qdgc_bbox_cell_count(min_lon, min_lat, max_lon, max_lat, level)` | `bigint` |

`predicate` is `'intersects'` (default), `'centroid'` (cell centre inside the
geometry) or `'contains'` (cell wholly inside), matching
`qdgc_py.polygon_to_cells`.

`qdgc_polygon_to_cells` is a **pruning quadtree descent**, not a grid over the
bounding box: it starts from the degree squares that meet the AOI and splits
only cells that still meet it. Cost scales with the AOI boundary rather than
with the area of its envelope, which is what makes deep fills of a coastline
practical. Cells found to be wholly inside stop being tested at all.

Always guard a fill with `qdgc_estimate_cell_count` — a level 12 fill of a
large country is hundreds of millions of cells.

### Metrics

| Function | Returns |
|---|---|
| `qdgc_level_degrees(level)` | side length in degrees |
| `qdgc_get_num_cells(level)` | cells covering the globe |
| `qdgc_average_cell_area(level [, lat [, unit]])` | spherical estimate, `'km^2'` or `'m^2'` |
| `qdgc_cell_area_km2(cell)` | true area on the WGS84 spheroid |
| `qdgc_version()` | extension version |

Levels
------

| Level | Side | Approx. at equator | Cells on the globe |
|---|---|---|---|
| 0 | 1° | 111 km | 64 800 |
| 1 | 0.5° | 55.6 km | 259 200 |
| 2 | 0.25° | 27.8 km | 1 036 800 |
| 3 | 0.125° | 13.9 km | 4 147 200 |
| 5 | 0.031 25° | 3.5 km | 66 355 200 |
| 7 | 0.007 812 5° | 869 m | 1 061 683 200 |
| 10 | ~0.000 98° | 109 m | 67 947 724 800 |
| 12 | ~0.000 24° | 27 m | 1 087 163 596 800 |

Usage
-----

```sql
-- Encode
SELECT qdgc_encode(31.4, 2.7, 5);                      -- E031N02ADBAC
SELECT qdgc_latlng_to_cell(geom, 7) FROM observations; -- straight from a geometry

-- Decode
SELECT qdgc_cell_to_boundary_geometry('E031N02ADBAC');
SELECT qdgc_cell_area_km2('E031N02ADBAC');

-- Establish a geocode layer for an area of interest
INSERT INTO geocode_cells (code, level, geom)
SELECT c, 7, qdgc_cell_to_boundary_geometry(c)
FROM qdgc_polygon_to_cells((SELECT geom FROM areas WHERE name = 'Uganda'), 7) AS c;

-- Check the size first
SELECT qdgc_estimate_cell_count((SELECT geom FROM areas WHERE name = 'Uganda'), 7);

-- Roll observations up to a coarser level
SELECT qdgc_cell_to_parent(code, 3) AS parent, count(*)
FROM observations_qdgc GROUP BY 1;

-- All descendants of a cell, straight off the index
SELECT * FROM observations_qdgc WHERE code LIKE 'E031N02AB%';
```

Testing
-------

```bash
python tools/gen_parity_fixture.py    # regenerate vectors from qdgc_py
python tools/run_tests.py             # run the suite
```

`gen_parity_fixture.py` produces ~22 000 encode vectors and ~6 500 decode
vectors **from `qdgc_py.core`**, deliberately weighted towards the cases that
break naive implementations: exact quadrant midpoints, signed zeros, the poles
and antimeridian, and the legacy quirk where exactly ±1.0 is not reduced to a
fraction. The SQL is then required to match them exactly. If `core.py` ever
changes, regenerate and the suite will tell you what moved.

Test files assert with `RAISE EXCEPTION`, so there are no expected-output files
to drift. `tools/run_tests.py` loads `sql/install/**.sql` into a throwaway
schema, which needs no write access to the server's extension directory.

Known divergences from `qdgc_py`
--------------------------------

Encoding, decoding and hierarchy are exact. Two things are deliberately not:

- **Area fill boundaries.** `qdgc_polygon_to_cells` uses GEOS predicates while
  `qdgc_py.polygon_to_cells` uses its own pure-stdlib point-in-polygon with an
  epsilon. Cells that merely *touch* the AOI edge can therefore be classified
  differently. Interior cells always agree.
- **Cell count estimates.** `qdgc_estimate_cell_count` measures polygon area on
  the WGS84 spheroid; `qdgc_py` uses an equirectangular approximation. Both are
  estimates used as guards, and both are capped by the exact envelope count.

Relationship to the rest of the repository
------------------------------------------

- `qdgc_py/` is the reference implementation and the arbiter when variants
  disagree.
- `qdgc_delivery/` holds the historical country-GeoPackage production pipeline
  (the `run_qdgc_*` batches and the FME export) that used to live here, plus the
  superseded `plpython3u` functions it was built on.

Reference
---------

Larsen, R., Holmern, T., Prager, S. D., Maliti, H., and Røskaft, E. (2009).
Using the extended quarter degree grid cell system to unify mapping and sharing
of biodiversity data. African Journal of Ecology.
https://doi.org/10.1111/j.1365-2028.2008.00997.x
