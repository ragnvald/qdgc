-- qdgc: bounding-box fills, without any PostGIS dependency.
--
-- Mirrors qdgc_py.core.bbox_to_cells and core._bbox_cell_count, including
-- antimeridian handling: pass min_lon > max_lon to cross it.

-- Longitude wrapped into [-180, 180], with -180 normalised to 180 the way
-- core._wrap_lon does it.
CREATE FUNCTION qdgc_wrap_lon(lon double precision)
RETURNS double precision
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT CASE
        WHEN abs(w - (-180.0)) <= 1e-12 THEN 180.0
        ELSE w
    END
    FROM (SELECT (((lon + 180.0)::numeric % 360.0 + 360.0) % 360.0)::double precision - 180.0 AS w) s;
$$;

COMMENT ON FUNCTION qdgc_wrap_lon(double precision) IS
'Wrap a longitude into [-180, 180], mapping -180 to 180.';

-- Half-open cell index range covering [min_value, max_value] on an axis.
-- Returns NULL when the range is empty. Mirrors core._index_range.
CREATE FUNCTION qdgc_index_range(
    min_value double precision,
    max_value double precision,
    origin double precision,
    step double precision,
    size bigint,
    OUT idx_start bigint,
    OUT idx_end bigint)
LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE
AS $$
BEGIN
    idx_start := greatest(0, floor((min_value - origin) / step)::bigint);
    idx_end   := least(size - 1, ceil((max_value - origin) / step)::bigint - 1);
    IF idx_end < idx_start THEN
        idx_start := NULL;
        idx_end   := NULL;
    END IF;
END;
$$;

COMMENT ON FUNCTION qdgc_index_range(double precision, double precision, double precision, double precision, bigint) IS
'Inclusive cell index range on one axis, or NULLs when the range is empty.';

-- Every cell at `level` whose extent meets the bounding box.
CREATE FUNCTION qdgc_bbox_to_cells(
    min_lon double precision,
    min_lat double precision,
    max_lon double precision,
    max_lat double precision,
    level integer)
RETURNS SETOF text
LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE
AS $$
DECLARE
    step      double precision;
    lon_cells bigint;
    lat_cells bigint;
    lo        double precision := min_lat;
    hi        double precision := max_lat;
    lat_r     record;
    seg       record;
BEGIN
    IF level < 0 THEN
        RAISE EXCEPTION 'level must be >= 0, got %', level
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    IF lo > hi THEN
        SELECT hi, lo INTO lo, hi;
    END IF;
    lo := greatest(-90.0, lo);
    hi := least(90.0, hi);
    IF hi <= -90.0 OR lo >= 90.0 THEN
        RETURN;
    END IF;

    step      := qdgc_level_degrees(level);
    lon_cells := round(360.0 / step)::bigint;
    lat_cells := round(180.0 / step)::bigint;

    lat_r := qdgc_index_range(lo, hi, -90.0, step, lat_cells);
    IF lat_r.idx_start IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    WITH segments AS (
        -- A span of a full turn or more covers every longitude; otherwise a
        -- wrapped box that crosses the antimeridian becomes two segments.
        SELECT -180.0::double precision AS seg_min, 180.0::double precision AS seg_max
        WHERE max_lon - min_lon >= 360.0
        UNION ALL
        SELECT w.lo_w, w.hi_w
        FROM (SELECT qdgc_wrap_lon(min_lon) AS lo_w, qdgc_wrap_lon(max_lon) AS hi_w) w
        WHERE max_lon - min_lon < 360.0 AND w.lo_w <= w.hi_w
        UNION ALL
        SELECT v.bound_lo, v.bound_hi
        FROM (SELECT qdgc_wrap_lon(min_lon) AS lo_w, qdgc_wrap_lon(max_lon) AS hi_w) w
        CROSS JOIN LATERAL (VALUES (w.lo_w, 180.0::double precision),
                                   (-180.0::double precision, w.hi_w)) AS v(bound_lo, bound_hi)
        WHERE max_lon - min_lon < 360.0 AND w.lo_w > w.hi_w
    ),
    ranges AS (
        SELECT r.idx_start, r.idx_end
        FROM segments s
        CROSS JOIN LATERAL qdgc_index_range(s.seg_min, s.seg_max, -180.0, step, lon_cells) r
        WHERE r.idx_start IS NOT NULL
    )
    SELECT DISTINCT qdgc_encode(-180.0 + (lon_i + 0.5) * step,
                                -90.0 + (lat_i + 0.5) * step,
                                level)
    FROM ranges
    CROSS JOIN LATERAL generate_series(ranges.idx_start, ranges.idx_end) AS lon_i
    CROSS JOIN generate_series(lat_r.idx_start, lat_r.idx_end) AS lat_i
    ORDER BY 1;
END;
$$;

COMMENT ON FUNCTION qdgc_bbox_to_cells(double precision, double precision, double precision, double precision, integer) IS
'All QDGC cells at `level` meeting the bounding box. Pass min_lon > max_lon to '
'cross the antimeridian. Mirrors qdgc_py.core.bbox_to_cells.';

-- Cell count for a bounding box without materialising the codes.
CREATE FUNCTION qdgc_bbox_cell_count(
    min_lon double precision,
    min_lat double precision,
    max_lon double precision,
    max_lat double precision,
    level integer)
RETURNS bigint
LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE
AS $$
DECLARE
    step      double precision;
    lon_cells bigint;
    lat_cells bigint;
    lo        double precision := min_lat;
    hi        double precision := max_lat;
    lat_r     record;
    lon_r     record;
    lon_r2    record;
    lo_w      double precision;
    hi_w      double precision;
    lat_count bigint;
    lon_count bigint;
BEGIN
    IF level < 0 THEN
        RAISE EXCEPTION 'level must be >= 0, got %', level
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    IF lo > hi THEN
        SELECT hi, lo INTO lo, hi;
    END IF;
    lo := greatest(-90.0, lo);
    hi := least(90.0, hi);

    step      := qdgc_level_degrees(level);
    lon_cells := round(360.0 / step)::bigint;
    lat_cells := round(180.0 / step)::bigint;

    lat_r := qdgc_index_range(lo, hi, -90.0, step, lat_cells);
    IF lat_r.idx_start IS NULL THEN
        RETURN 0;
    END IF;
    lat_count := lat_r.idx_end - lat_r.idx_start + 1;

    IF max_lon - min_lon >= 360.0 THEN
        lon_count := lon_cells;
    ELSE
        lo_w := qdgc_wrap_lon(min_lon);
        hi_w := qdgc_wrap_lon(max_lon);
        IF lo_w <= hi_w THEN
            lon_r := qdgc_index_range(lo_w, hi_w, -180.0, step, lon_cells);
            lon_count := COALESCE(lon_r.idx_end - lon_r.idx_start + 1, 0);
        ELSE
            lon_r  := qdgc_index_range(lo_w, 180.0, -180.0, step, lon_cells);
            lon_r2 := qdgc_index_range(-180.0, hi_w, -180.0, step, lon_cells);
            lon_count := COALESCE(lon_r.idx_end - lon_r.idx_start + 1, 0)
                       + COALESCE(lon_r2.idx_end - lon_r2.idx_start + 1, 0);
        END IF;
    END IF;

    RETURN lat_count * lon_count;
END;
$$;

COMMENT ON FUNCTION qdgc_bbox_cell_count(double precision, double precision, double precision, double precision, integer) IS
'Number of cells a bounding box fill would produce at `level`, without '
'materialising them. Use this as a guard before a large fill.';
