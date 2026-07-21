QDGC delivery pipeline
======================

Production and distribution of country-specific QDGC GeoPackages. This is a
**delivery pipeline**, not library code: it is the batch process that produced
the published per-country QDGC datasets.

It was split out of `qdgc_pg/` so that folder could become a clean, reusable
PostgreSQL extension. Grid generation now belongs to the `qdgc` /
`qdgc_postgis` extensions; this folder is only about turning that into
distributable files.

Contents
--------

| Path | What it is |
|---|---|
| `run_qdgc_africa.sql` | 47 country batch calls, level 7 |
| `run_qdgc_asia.sql` | 3 country batch calls |
| `run_qdgc_southamerica.sql` | 9 country batch calls |
| `qdgc_export_to_geopackage.fmw` | FME 2020.2 workspace: PostGIS → GeoPackage, fanned out per country and level |
| `geopackage_readme.txt` | The readme shipped inside the GeoPackage deliverable |
| `legacy/` | The original `plpython3u` + plpgsql functions these batches call |

Running the export
------------------

```bat
"C:\Program Files\FME\fme.exe" qdgc_export_to_geopackage.fmw ^
    --SourceDataset_POSTGIS "qdgc@postgis13@localhost" ^
    --DestDataset_OGCGEOPACKAGE "D:\code\qdgc\output"
```

Status and known problems
-------------------------

These files are kept for reproducibility of the published datasets. They are
**not** maintained as a supported interface, and they carry real defects:

- `run_qdgc_africa.sql` is syntactically broken in two places — a stray `);`
  on the Libya call and an unterminated call for South Africa that swallows the
  following line. It also lists Angola and Sudan twice.
- `run_qdgc_southamerica.sql` lists Peru twice.
- `legacy/create_function_qdgc_fillqdgc.sql` computes `area_km2` as
  `ST_Area(ST_Transform(geom, 102022))`, which is ESRI Africa Albers Equal
  Area. It is applied unconditionally, so areas outside Africa are wrong, and
  SRID 102022 is not present in a stock PostGIS `spatial_ref_sys` at all.
- `legacy/create_function_qdgc_getlonlat.sql` is written in `plpython3u`, an
  untrusted procedural language that requires superuser to install and is
  unavailable on most managed PostgreSQL services.
- `qdgc_fillqdgc` hardcodes the table names `tbl_countries` and `tbl_qdgc`,
  drops and recreates its output table, and declares `RETURNS SETOF text`
  while never returning anything.

Rebuilding this on the extension
--------------------------------

All of the above is fixed in `qdgc_pg/`. A modern equivalent of
`qdgc_fillqdgc` needs no bespoke functions and no plpython3u:

```sql
CREATE TABLE tbl_qdgc AS
SELECT
    c                                  AS qdgc,
    a.name                             AS area_reference,
    qdgc_get_level(c)                  AS level_qdgc,
    qdgc_level_degrees(qdgc_get_level(c)) AS cellsize_degrees,
    ST_X(qdgc_cell_to_geometry(c))     AS lon_center,
    ST_Y(qdgc_cell_to_geometry(c))     AS lat_center,
    qdgc_cell_area_km2(c)              AS area_km2,
    qdgc_cell_to_boundary_geometry(c)  AS geom
FROM areas a
CROSS JOIN LATERAL generate_series(1, 7) AS lvl
CROSS JOIN LATERAL qdgc_polygon_to_cells(a.geom, lvl) AS c
WHERE a.name = 'Uganda';
```

That version works on any area table with any column names, computes areas
correctly worldwide, and can be composed into a larger query instead of writing
to a fixed global table.
