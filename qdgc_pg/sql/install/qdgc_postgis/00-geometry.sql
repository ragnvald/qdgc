-- qdgc_postgis: geometry and geography bindings for the qdgc extension.
--
-- The core `qdgc` extension has no PostGIS dependency so it can be installed
-- anywhere, including as a trusted extension. Everything that touches a
-- geometry lives here, mirroring the h3 / h3_postgis split.

CREATE FUNCTION qdgc_latlng_to_cell(geom geometry, level integer)
RETURNS text
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT qdgc_encode(ST_X(p), ST_Y(p), level)
    FROM (SELECT CASE
              WHEN ST_SRID(geom) IN (0, 4326) THEN geom
              ELSE ST_Transform(geom, 4326)
          END AS p) s;
$$;

COMMENT ON FUNCTION qdgc_latlng_to_cell(geometry, integer) IS
'Encode a point geometry to a QDGC code. Non-4326 input is transformed; SRID 0 '
'is assumed to already be lon/lat.';

CREATE FUNCTION qdgc_latlng_to_cell(geog geography, level integer)
RETURNS text
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT qdgc_encode(ST_X(geog::geometry), ST_Y(geog::geometry), level);
$$;

COMMENT ON FUNCTION qdgc_latlng_to_cell(geography, integer) IS
'Encode a point geography to a QDGC code.';

-- Cell centroid as a point geometry.
CREATE FUNCTION qdgc_cell_to_geometry(cell text)
RETURNS geometry
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT ST_SetSRID(ST_MakePoint((b.min_lon + b.max_lon) / 2.0,
                                   (b.min_lat + b.max_lat) / 2.0), 4326)
    FROM qdgc_cell_to_bounds(cell) AS b;
$$;

COMMENT ON FUNCTION qdgc_cell_to_geometry(text) IS
'Centroid of a QDGC cell as a POINT geometry in EPSG:4326.';

CREATE FUNCTION qdgc_cell_to_geography(cell text)
RETURNS geography
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT qdgc_cell_to_geometry(cell)::geography;
$$;

COMMENT ON FUNCTION qdgc_cell_to_geography(text) IS
'Centroid of a QDGC cell as a POINT geography.';

-- Cell outline. Vertex order matches qdgc_py.core.cell_to_polygon: starting at
-- the south-west corner and running counter-clockwise in (lon, lat).
CREATE FUNCTION qdgc_cell_to_boundary_geometry(cell text)
RETURNS geometry
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT ST_SetSRID(ST_MakePolygon(ST_MakeLine(ARRAY[
        ST_MakePoint(b.min_lon, b.min_lat),
        ST_MakePoint(b.max_lon, b.min_lat),
        ST_MakePoint(b.max_lon, b.max_lat),
        ST_MakePoint(b.min_lon, b.max_lat),
        ST_MakePoint(b.min_lon, b.min_lat)
    ])), 4326)
    FROM qdgc_cell_to_bounds(cell) AS b;
$$;

COMMENT ON FUNCTION qdgc_cell_to_boundary_geometry(text) IS
'Outline of a QDGC cell as a POLYGON geometry in EPSG:4326, south-west corner '
'first. Mirrors h3_cell_to_boundary_geometry.';

CREATE FUNCTION qdgc_cell_to_boundary_geography(cell text)
RETURNS geography
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT qdgc_cell_to_boundary_geometry(cell)::geography;
$$;

COMMENT ON FUNCTION qdgc_cell_to_boundary_geography(text) IS
'Outline of a QDGC cell as a POLYGON geography.';

-- True cell area on the WGS84 spheroid.
--
-- This deliberately replaces the legacy `ST_Area(ST_Transform(geom, 102022))`
-- approach, which hardcoded ESRI Africa Albers and was therefore wrong for
-- every area outside Africa -- and which is not present in a stock PostGIS
-- spatial_ref_sys at all.
CREATE FUNCTION qdgc_cell_area_km2(cell text)
RETURNS double precision
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT ST_Area(qdgc_cell_to_boundary_geography(cell)) / 1000000.0;
$$;

COMMENT ON FUNCTION qdgc_cell_area_km2(text) IS
'Area of a QDGC cell in square kilometres, measured on the WGS84 spheroid.';
