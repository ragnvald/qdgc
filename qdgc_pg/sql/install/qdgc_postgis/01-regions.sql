-- qdgc_postgis: filling an area of interest with cells.
--
-- The fill is a pruning quadtree descent, not a grid over the whole envelope.
-- Starting from the 1-degree squares that meet the AOI, each cell is split
-- into its four children and a child is kept only if it still meets the AOI.
-- Cost therefore scales with the boundary of the AOI rather than with the area
-- of its bounding box, which is what makes level 10+ fills of a coastline
-- tractable. Cells fully inside the AOI carry a `contained` flag so their
-- descendants skip the intersection test entirely.

CREATE FUNCTION qdgc_polygon_to_cells(
    geom geometry,
    level integer,
    predicate text DEFAULT 'intersects')
RETURNS SETOF text
LANGUAGE plpgsql STABLE PARALLEL SAFE
AS $$
DECLARE
    g       geometry;
    pred    text := lower(btrim(predicate));
    minx    double precision;
    miny    double precision;
    maxx    double precision;
    maxy    double precision;
    lon_lo  integer;
    lon_hi  integer;
    lat_lo  integer;
    lat_hi  integer;
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

    minx := ST_XMin(g); miny := ST_YMin(g);
    maxx := ST_XMax(g); maxy := ST_YMax(g);

    -- Degree squares meeting the envelope. Upper bound is ceil - 1 so a box
    -- ending exactly on a degree line does not pull in the square it merely
    -- touches, matching qdgc_py.core. The greatest() keeps a degenerate
    -- (point or vertical/horizontal) envelope from yielding nothing.
    lon_lo := greatest(-180, floor(minx)::integer);
    lon_hi := least(179, greatest(lon_lo, ceil(maxx)::integer - 1));
    lat_lo := greatest(-90, floor(miny)::integer);
    lat_hi := least(89, greatest(lat_lo, ceil(maxy)::integer - 1));

    IF lon_hi < lon_lo OR lat_hi < lat_lo THEN
        RETURN;
    END IF;

    RETURN QUERY
    WITH RECURSIVE seed AS (
        SELECT
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
        FROM generate_series(lon_lo, lon_hi) AS lon_i
        CROSS JOIN generate_series(lat_lo, lat_hi) AS lat_i
    ),
    tree AS (
        SELECT s.code, s.x0, s.y0, s.x1, s.y1, 0 AS lvl,
               ST_Contains(g, ST_MakeEnvelope(s.x0, s.y0, s.x1, s.y1, 4326)) AS contained
        FROM seed s
        WHERE ST_Intersects(g, ST_MakeEnvelope(s.x0, s.y0, s.x1, s.y1, 4326))

        UNION ALL

        SELECT
            t.code || q.letter,
            CASE WHEN q.east = 1 THEN (t.x0 + t.x1) / 2.0 ELSE t.x0 END,
            CASE WHEN q.north = 1 THEN (t.y0 + t.y1) / 2.0 ELSE t.y0 END,
            CASE WHEN q.east = 1 THEN t.x1 ELSE (t.x0 + t.x1) / 2.0 END,
            CASE WHEN q.north = 1 THEN t.y1 ELSE (t.y0 + t.y1) / 2.0 END,
            t.lvl + 1,
            t.contained
                OR ST_Contains(g, ST_MakeEnvelope(
                       CASE WHEN q.east = 1 THEN (t.x0 + t.x1) / 2.0 ELSE t.x0 END,
                       CASE WHEN q.north = 1 THEN (t.y0 + t.y1) / 2.0 ELSE t.y0 END,
                       CASE WHEN q.east = 1 THEN t.x1 ELSE (t.x0 + t.x1) / 2.0 END,
                       CASE WHEN q.north = 1 THEN t.y1 ELSE (t.y0 + t.y1) / 2.0 END, 4326))
        FROM tree t
        -- A = north-west, B = north-east, C = south-west, D = south-east.
        -- This orientation is locked; see qdgc_pg/README.md.
        CROSS JOIN (VALUES ('A', 0, 1), ('B', 1, 1),
                           ('C', 0, 0), ('D', 1, 0)) AS q(letter, east, north)
        WHERE t.lvl < level
          AND (t.contained OR ST_Intersects(g, ST_MakeEnvelope(
                  CASE WHEN q.east = 1 THEN (t.x0 + t.x1) / 2.0 ELSE t.x0 END,
                  CASE WHEN q.north = 1 THEN (t.y0 + t.y1) / 2.0 ELSE t.y0 END,
                  CASE WHEN q.east = 1 THEN t.x1 ELSE (t.x0 + t.x1) / 2.0 END,
                  CASE WHEN q.north = 1 THEN t.y1 ELSE (t.y0 + t.y1) / 2.0 END, 4326)))
    )
    SELECT t.code
    FROM tree t
    WHERE t.lvl = level
      AND CASE pred
          WHEN 'intersects' THEN true          -- guaranteed by the descent
          WHEN 'contains'   THEN t.contained
          ELSE ST_Intersects(g, ST_SetSRID(ST_MakePoint((t.x0 + t.x1) / 2.0,
                                                        (t.y0 + t.y1) / 2.0), 4326))
          END
    ORDER BY t.code;
END;
$$;

COMMENT ON FUNCTION qdgc_polygon_to_cells(geometry, integer, text) IS
'QDGC cells at `level` related to a geometry. Predicates: ''intersects'' '
'(default), ''centroid'' (cell centre inside the geometry), ''contains'' (cell '
'wholly inside the geometry). Mirrors qdgc_py.polygon_to_cells.';

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
