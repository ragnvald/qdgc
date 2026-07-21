-- qdgc_postgis--0.1.0.sql
--
-- GENERATED FILE -- do not edit.
-- Built from sql/install/qdgc_postgis/*.sql by tools/build_sql.py.

\echo Use "CREATE EXTENSION qdgc_postgis" to load this file. \quit

-- ---------------------------------------------------------------
-- 00-geometry.sql
-- ---------------------------------------------------------------
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

-- ---------------------------------------------------------------
-- 01-regions.sql
-- ---------------------------------------------------------------
-- qdgc_postgis: filling an area of interest with cells.
--
-- The fill is a pruning quadtree descent, not a grid over the whole envelope.
-- Starting from the 1-degree squares that meet the AOI, each cell is split into
-- its four children and a child is kept only if it still meets the AOI. Cost
-- therefore scales with the boundary of the AOI rather than with the area of
-- its bounding box, which is what makes deep fills of a coastline tractable.
-- Cells fully inside carry a `contained` flag so their descendants skip the
-- intersection test entirely.
--
-- Multi-part geometries are descended PER PART, each with its own envelope,
-- and the resulting codes unioned. This mirrors qdgc_py exactly -- see the
-- comment on the half-open envelope rule below.

CREATE FUNCTION qdgc_polygon_to_cells(
    geom geometry,
    level integer,
    predicate text DEFAULT 'intersects')
RETURNS SETOF text
LANGUAGE plpgsql STABLE PARALLEL SAFE
AS $$
DECLARE
    g    geometry;
    pred text := lower(btrim(predicate));
BEGIN
    IF geom IS NULL OR level IS NULL THEN
        RETURN;
    END IF;
    IF level < 0 THEN
        RAISE EXCEPTION 'level must be >= 0, got %', level
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF pred NOT IN ('intersects', 'centroid', 'contains') THEN
        RAISE EXCEPTION 'predicate must be one of: intersects, centroid, contains (got %)', predicate
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- SRID 0 is taken to be lon/lat already, but it must be stamped as 4326 or
    -- every ST_Intersects below fails with a mixed-SRID error.
    g := CASE
        WHEN ST_SRID(geom) = 0    THEN ST_SetSRID(geom, 4326)
        WHEN ST_SRID(geom) = 4326 THEN geom
        ELSE ST_Transform(geom, 4326)
    END;
    IF ST_IsEmpty(g) THEN
        RETURN;
    END IF;

    RETURN QUERY
    WITH RECURSIVE
    -- One row per part. Each part gets its OWN envelope, which is what makes
    -- the half-open rule below match qdgc_py: geocode_manage.qdgc_from_union
    -- splits a MultiPolygon and calls polygon_to_cells once per part, so a
    -- cell touching one part's upper edge is dropped even when it sits well
    -- inside the envelope of the whole collection.
    pbox AS (
        -- row_number, not d.path[1]: ST_Dump returns an EMPTY path array for a
        -- single Polygon, so path[1] would be NULL and every join on it would
        -- silently drop all rows.
        SELECT row_number() OVER () AS pid,
               d.geom                AS pgeom,
               ST_XMin(d.geom) AS minx, ST_YMin(d.geom) AS miny,
               ST_XMax(d.geom) AS maxx, ST_YMax(d.geom) AS maxy,
               -- Degree squares meeting this part. The upper bound is ceil - 1
               -- so a part ending exactly on a degree line does not pull in the
               -- square it merely touches. greatest() keeps a degenerate
               -- (point or axis-aligned) envelope from yielding nothing.
               greatest(-180, floor(ST_XMin(d.geom))::integer) AS lon_lo,
               least(179, greatest(greatest(-180, floor(ST_XMin(d.geom))::integer),
                                   ceil(ST_XMax(d.geom))::integer - 1)) AS lon_hi,
               greatest(-90, floor(ST_YMin(d.geom))::integer) AS lat_lo,
               least(89, greatest(greatest(-90, floor(ST_YMin(d.geom))::integer),
                                  ceil(ST_YMax(d.geom))::integer - 1)) AS lat_hi
        FROM ST_Dump(g) AS d
        WHERE NOT ST_IsEmpty(d.geom)
    ),
    seed AS (
        SELECT b.pid,
            CASE WHEN lon_i >= 0
                 THEN 'E' || lpad(lon_i::text, 3, '0')
                 ELSE 'W' || lpad((-lon_i - 1)::text, 3, '0') END
         || CASE WHEN lat_i >= 0
                 THEN 'N' || lpad(lat_i::text, 2, '0')
                 ELSE 'S' || lpad((-lat_i - 1)::text, 2, '0') END AS code,
            lon_i::double precision       AS x0,
            lat_i::double precision       AS y0,
            (lon_i + 1)::double precision AS x1,
            (lat_i + 1)::double precision AS y1
        FROM pbox b
        CROSS JOIN LATERAL generate_series(b.lon_lo, b.lon_hi) AS lon_i
        CROSS JOIN LATERAL generate_series(b.lat_lo, b.lat_hi) AS lat_i
    ),
    tree AS (
        SELECT s.pid, s.code, s.x0, s.y0, s.x1, s.y1, 0 AS lvl,
               ST_Contains(b.pgeom, ST_MakeEnvelope(s.x0, s.y0, s.x1, s.y1, 4326)) AS contained
        FROM seed s
        JOIN pbox b ON b.pid = s.pid
        -- The part's envelope is half-open on its upper edges, matching
        -- qdgc_py.core.bbox_to_cells (which uses ceil(...) - 1). Without this a
        -- cell lying wholly outside the part but sharing an edge with it would
        -- be kept, because ST_Intersects counts a zero-area touch. Safe to
        -- prune on: a child can never re-enter the envelope its parent left.
        WHERE s.x0 < b.maxx AND s.x1 > b.minx AND s.y0 < b.maxy AND s.y1 > b.miny
          AND ST_Intersects(b.pgeom, ST_MakeEnvelope(s.x0, s.y0, s.x1, s.y1, 4326))

        UNION ALL

        SELECT
            t.pid,
            t.code || q.letter,
            CASE WHEN q.east = 1 THEN (t.x0 + t.x1) / 2.0 ELSE t.x0 END,
            CASE WHEN q.north = 1 THEN (t.y0 + t.y1) / 2.0 ELSE t.y0 END,
            CASE WHEN q.east = 1 THEN t.x1 ELSE (t.x0 + t.x1) / 2.0 END,
            CASE WHEN q.north = 1 THEN t.y1 ELSE (t.y0 + t.y1) / 2.0 END,
            t.lvl + 1,
            t.contained
                OR ST_Contains(b.pgeom, ST_MakeEnvelope(
                       CASE WHEN q.east = 1 THEN (t.x0 + t.x1) / 2.0 ELSE t.x0 END,
                       CASE WHEN q.north = 1 THEN (t.y0 + t.y1) / 2.0 ELSE t.y0 END,
                       CASE WHEN q.east = 1 THEN t.x1 ELSE (t.x0 + t.x1) / 2.0 END,
                       CASE WHEN q.north = 1 THEN t.y1 ELSE (t.y0 + t.y1) / 2.0 END, 4326))
        FROM tree t
        JOIN pbox b ON b.pid = t.pid
        -- A = north-west, B = north-east, C = south-west, D = south-east.
        -- This orientation is locked; see qdgc_pg/README.md.
        CROSS JOIN (VALUES ('A', 0, 1), ('B', 1, 1),
                           ('C', 0, 0), ('D', 1, 0)) AS q(letter, east, north)
        WHERE t.lvl < level
          AND (CASE WHEN q.east = 1 THEN (t.x0 + t.x1) / 2.0 ELSE t.x0 END) < b.maxx
          AND (CASE WHEN q.east = 1 THEN t.x1 ELSE (t.x0 + t.x1) / 2.0 END) > b.minx
          AND (CASE WHEN q.north = 1 THEN (t.y0 + t.y1) / 2.0 ELSE t.y0 END) < b.maxy
          AND (CASE WHEN q.north = 1 THEN t.y1 ELSE (t.y0 + t.y1) / 2.0 END) > b.miny
          AND (t.contained OR ST_Intersects(b.pgeom, ST_MakeEnvelope(
                  CASE WHEN q.east = 1 THEN (t.x0 + t.x1) / 2.0 ELSE t.x0 END,
                  CASE WHEN q.north = 1 THEN (t.y0 + t.y1) / 2.0 ELSE t.y0 END,
                  CASE WHEN q.east = 1 THEN t.x1 ELSE (t.x0 + t.x1) / 2.0 END,
                  CASE WHEN q.north = 1 THEN t.y1 ELSE (t.y0 + t.y1) / 2.0 END, 4326)))
    )
    -- DISTINCT because adjacent parts can both claim a cell on their shared
    -- edge, exactly as the union of per-part code sets does in qdgc_py.
    SELECT DISTINCT t.code
    FROM tree t
    JOIN pbox b ON b.pid = t.pid
    WHERE t.lvl = level
      AND CASE pred
          WHEN 'intersects' THEN true          -- guaranteed by the descent
          WHEN 'contains'   THEN t.contained
          ELSE ST_Intersects(b.pgeom, ST_SetSRID(ST_MakePoint((t.x0 + t.x1) / 2.0,
                                                              (t.y0 + t.y1) / 2.0), 4326))
          END
    ORDER BY 1;
END;
$$;

COMMENT ON FUNCTION qdgc_polygon_to_cells(geometry, integer, text) IS
'QDGC cells at `level` related to a geometry. Predicates: ''intersects'' '
'(default), ''centroid'' (cell centre inside the geometry), ''contains'' (cell '
'wholly inside the geometry). Multi-part geometries are filled per part and '
'unioned. Mirrors qdgc_py.polygon_to_cells.';

-- Cell count for a geometry without materialising the fill. Mirrors
-- qdgc_py.core.estimate_cell_count: an area-based estimate, capped by the
-- exact envelope count. Use it as a guard before a large fill, the way MESA
-- uses qdgc_max_cells.
CREATE FUNCTION qdgc_estimate_cell_count(geom geometry, level integer)
RETURNS bigint
LANGUAGE plpgsql STABLE PARALLEL SAFE
AS $$
DECLARE
    g          geometry;
    bbox_count bigint;
    poly_area  double precision;
    cell_area  double precision;
    estimate   bigint;
BEGIN
    IF geom IS NULL OR level IS NULL THEN
        RETURN NULL;
    END IF;

    g := CASE
        WHEN ST_SRID(geom) = 0    THEN ST_SetSRID(geom, 4326)
        WHEN ST_SRID(geom) = 4326 THEN geom
        ELSE ST_Transform(geom, 4326)
    END;
    IF ST_IsEmpty(g) THEN
        RETURN 0;
    END IF;

    bbox_count := qdgc_bbox_cell_count(ST_XMin(g), ST_YMin(g), ST_XMax(g), ST_YMax(g), level);
    IF bbox_count = 0 THEN
        RETURN 0;
    END IF;

    poly_area := ST_Area(g::geography) / 1000000.0;
    cell_area := qdgc_average_cell_area(level, (ST_YMin(g) + ST_YMax(g)) / 2.0, 'km^2');
    IF cell_area <= 0 OR poly_area <= 0 THEN
        RETURN least(bbox_count, greatest(1, bbox_count));
    END IF;

    estimate := round(poly_area / cell_area)::bigint;
    RETURN greatest(1, least(bbox_count, estimate));
END;
$$;

COMMENT ON FUNCTION qdgc_estimate_cell_count(geometry, integer) IS
'Estimated number of cells a fill of this geometry would produce at `level`, '
'capped by the exact envelope count. Cheap guard before a large fill.';
