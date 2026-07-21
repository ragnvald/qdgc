-- qdgc--0.1.0.sql
--
-- GENERATED FILE -- do not edit.
-- Built from sql/install/qdgc/*.sql by tools/build_sql.py.

\echo Use "CREATE EXTENSION qdgc" to load this file. \quit

-- ---------------------------------------------------------------
-- 00-encode.sql
-- ---------------------------------------------------------------
-- qdgc: encoding lon/lat to Extended QDGC codes.
--
-- Bit-for-bit compatible with qdgc_py.core.encode, which is itself compatible
-- with qdgc_py_legacy/tools/qdgc_lib.py. See qdgc_pg/README.md and the repo
-- learning.md before changing anything here: the boundary conventions are a
-- locked contract, not an implementation detail.

-- Degree-square prefix, e.g. E031N02. Mirrors core._lonlat_prefix.
CREATE FUNCTION qdgc_degree_prefix(lon double precision, lat double precision)
RETURNS text
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT CASE WHEN lon < 0 THEN 'W' ELSE 'E' END
        || lpad(trunc(abs(lon))::int::text, 3, '0')
        || CASE WHEN lat < 0 THEN 'S' ELSE 'N' END
        || lpad(trunc(abs(lat))::int::text, 2, '0');
$$;

COMMENT ON FUNCTION qdgc_degree_prefix(double precision, double precision) IS
'Degree-square prefix of a QDGC code, e.g. E031N02. This is the level 0 cell.';

-- Strip whole degrees, keeping the legacy rule exactly: only values strictly
-- outside [-1, 1] are reduced, so +/-1.0 is deliberately left alone.
-- Mirrors core._normalize_fraction.
CREATE FUNCTION qdgc_normalize_fraction(value double precision)
RETURNS double precision
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT CASE
        WHEN value > 1 THEN value - floor(value)
        WHEN value < -1 THEN value + abs(ceil(value))
        ELSE value
    END;
$$;

COMMENT ON FUNCTION qdgc_normalize_fraction(double precision) IS
'Reduce a coordinate to its within-degree residual, preserving the legacy rule '
'that exactly +/-1.0 is not reduced.';

-- Encode a point to a QDGC code. Argument order is (lon, lat), matching
-- qdgc_py.core.encode and PostGIS ST_X/ST_Y ordering.
--
-- Implementation note: the legacy algorithm is written as a four-way quadrant
-- tree, but it reduces to two signed accumulators as long as the quadrant is
-- re-derived from the *current* residual on every step. Residuals that land
-- exactly on 0.0 move into the positive branch, which is why deep codes tail
-- off in C rather than B. This equivalence is verified exhaustively against
-- core.py by tools/gen_parity_fixture.py.
CREATE FUNCTION qdgc_encode(lon double precision, lat double precision, level integer)
RETURNS text
LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE
AS $$
DECLARE
    u          double precision;
    v          double precision;
    east_pos   boolean;
    north_pos  boolean;
    far_lon    boolean;
    far_lat    boolean;
    is_east    boolean;
    is_north   boolean;
    path       text := '';
    i          integer;
BEGIN
    IF level < 0 THEN
        RAISE EXCEPTION 'level must be >= 0, got %', level
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    u := qdgc_normalize_fraction(lon);
    v := qdgc_normalize_fraction(lat);

    FOR i IN 1..level LOOP
        east_pos  := u >= 0;
        north_pos := CASE WHEN east_pos THEN v >= 0 ELSE v > 0 END;

        IF east_pos THEN
            far_lon := u >= 0.5;
            u := CASE WHEN far_lon THEN (u - 0.5) * 2 ELSE u * 2 END;
            is_east := far_lon;
        ELSE
            far_lon := u <= -0.5;
            u := CASE WHEN far_lon THEN (u + 0.5) * 2 ELSE u * 2 END;
            is_east := NOT far_lon;
        END IF;

        IF north_pos THEN
            far_lat := v >= 0.5;
            v := CASE WHEN far_lat THEN (v - 0.5) * 2 ELSE v * 2 END;
            is_north := far_lat;
        ELSE
            far_lat := v <= -0.5;
            v := CASE WHEN far_lat THEN (v + 0.5) * 2 ELSE v * 2 END;
            is_north := NOT far_lat;
        END IF;

        path := path || CASE
            WHEN is_north AND is_east THEN 'B'
            WHEN is_north             THEN 'A'
            WHEN is_east              THEN 'D'
            ELSE                           'C'
        END;
    END LOOP;

    RETURN qdgc_degree_prefix(lon, lat) || path;
END;
$$;

COMMENT ON FUNCTION qdgc_encode(double precision, double precision, integer) IS
'Encode (lon, lat) in EPSG:4326 to an Extended QDGC code at the given level. '
'Bit-for-bit compatible with qdgc_py.core.encode.';

-- h3-style alias: (lat, lng, level) argument order, matching
-- qdgc_py.latlng_to_cell and h3_latlng_to_cell.
CREATE FUNCTION qdgc_latlng_to_cell(lat double precision, lng double precision, level integer)
RETURNS text
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT qdgc_encode(lng, lat, level);
$$;

COMMENT ON FUNCTION qdgc_latlng_to_cell(double precision, double precision, integer) IS
'Encode (lat, lng) to a QDGC code. h3-style alias for qdgc_encode with '
'reversed coordinate order.';

-- ---------------------------------------------------------------
-- 01-decode.sql
-- ---------------------------------------------------------------
-- qdgc: decoding QDGC codes back to geographic bounds.
--
-- Mirrors qdgc_py.core.decode_bounds. The A/B/C/D subcell orientation is
-- locked: A = north-west, B = north-east, C = south-west, D = south-east.
-- Reordering these silently changes every code ever produced.

CREATE FUNCTION qdgc_code_pattern()
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT '^([EW])([0-9]{3})([NS])([0-9]{2})([ABCD]*)$';
$$;

COMMENT ON FUNCTION qdgc_code_pattern() IS
'Regular expression a syntactically valid QDGC code must match.';

-- Level of a cell, i.e. the number of subdivision steps below the degree
-- square. Returns NULL for a syntactically invalid code.
CREATE FUNCTION qdgc_get_level(cell text)
RETURNS integer
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT CASE
        WHEN btrim(cell) ~ qdgc_code_pattern() THEN length(btrim(cell)) - 7
        ELSE NULL
    END;
$$;

COMMENT ON FUNCTION qdgc_get_level(text) IS
'Subdivision level of a QDGC cell (0 for a whole degree square). NULL if the '
'code is not syntactically valid. Mirrors h3_get_resolution.';

-- Bounding box of a cell. Errors on an invalid code, so that a typo in a
-- pipeline fails loudly instead of producing a silently wrong extent.
CREATE FUNCTION qdgc_cell_to_bounds(
    cell text,
    OUT min_lon double precision,
    OUT min_lat double precision,
    OUT max_lon double precision,
    OUT max_lat double precision)
LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE
AS $$
DECLARE
    parts    text[];
    lon_deg  integer;
    lat_deg  integer;
    path     text;
    c        text;
    mid_lon  double precision;
    mid_lat  double precision;
    i        integer;
BEGIN
    parts := regexp_match(btrim(cell), qdgc_code_pattern());
    IF parts IS NULL THEN
        RAISE EXCEPTION 'invalid QDGC code: %', cell
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    lon_deg := parts[2]::integer;
    lat_deg := parts[4]::integer;
    path    := parts[5];

    IF parts[1] = 'E' THEN
        min_lon := lon_deg;
        max_lon := lon_deg + 1;
    ELSE
        min_lon := -(lon_deg + 1);
        max_lon := -lon_deg;
    END IF;

    IF parts[3] = 'N' THEN
        min_lat := lat_deg;
        max_lat := lat_deg + 1;
    ELSE
        min_lat := -(lat_deg + 1);
        max_lat := -lat_deg;
    END IF;

    FOR i IN 1..length(path) LOOP
        c := substr(path, i, 1);
        mid_lon := (min_lon + max_lon) / 2.0;
        mid_lat := (min_lat + max_lat) / 2.0;
        CASE c
            WHEN 'A' THEN max_lon := mid_lon; min_lat := mid_lat;  -- north-west
            WHEN 'B' THEN min_lon := mid_lon; min_lat := mid_lat;  -- north-east
            WHEN 'C' THEN max_lon := mid_lon; max_lat := mid_lat;  -- south-west
            ELSE          min_lon := mid_lon; max_lat := mid_lat;  -- south-east
        END CASE;
    END LOOP;
END;
$$;

COMMENT ON FUNCTION qdgc_cell_to_bounds(text) IS
'Geographic bounds (min_lon, min_lat, max_lon, max_lat) of a QDGC cell in '
'EPSG:4326. Raises on an invalid code.';

-- True when the code is syntactically valid and lands inside the WGS84 extent.
CREATE FUNCTION qdgc_is_valid_cell(cell text)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE
AS $$
DECLARE
    b record;
BEGIN
    IF btrim(cell) !~ qdgc_code_pattern() THEN
        RETURN false;
    END IF;
    SELECT * INTO b FROM qdgc_cell_to_bounds(cell) AS t;
    RETURN b.min_lon >= -180.0 AND b.max_lon <= 180.0 AND b.min_lon < b.max_lon
       AND b.min_lat >= -90.0  AND b.max_lat <= 90.0  AND b.min_lat < b.max_lat;
END;
$$;

COMMENT ON FUNCTION qdgc_is_valid_cell(text) IS
'True when the code is syntactically valid and geographically inside WGS84.';

-- Centroid as a built-in point, with x = longitude and y = latitude, matching
-- ST_MakePoint argument order.
CREATE FUNCTION qdgc_cell_to_lonlat(cell text)
RETURNS point
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT point((b.min_lon + b.max_lon) / 2.0, (b.min_lat + b.max_lat) / 2.0)
    FROM qdgc_cell_to_bounds(cell) AS b;
$$;

COMMENT ON FUNCTION qdgc_cell_to_lonlat(text) IS
'Centroid of a QDGC cell as a point with x = longitude, y = latitude.';

-- h3-style alias returning (lat, lng) order, matching qdgc_py.cell_to_latlng.
CREATE FUNCTION qdgc_cell_to_latlng(
    cell text,
    OUT lat double precision,
    OUT lng double precision)
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT (b.min_lat + b.max_lat) / 2.0, (b.min_lon + b.max_lon) / 2.0
    FROM qdgc_cell_to_bounds(cell) AS b;
$$;

COMMENT ON FUNCTION qdgc_cell_to_latlng(text) IS
'Centroid of a QDGC cell as (lat, lng). h3-style alias for qdgc_cell_to_lonlat.';

-- ---------------------------------------------------------------
-- 02-hierarchy.sql
-- ---------------------------------------------------------------
-- qdgc: parent/child navigation.
--
-- QDGC codes are strings whose hierarchy is plain prefix containment, so a
-- descendant test is `child LIKE parent || '%'` and a btree index on the code
-- column serves ancestor range scans with no operator class of our own.
-- This is the one place where a text-based DGGS beats a 64-bit one.

CREATE FUNCTION qdgc_cell_to_parent(cell text, parent_level integer DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
    trimmed text := btrim(cell);
    lvl     integer;
    target  integer;
BEGIN
    IF cell IS NULL THEN
        RETURN NULL;
    END IF;

    lvl := qdgc_get_level(trimmed);
    IF lvl IS NULL THEN
        RAISE EXCEPTION 'invalid QDGC code: %', cell
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    IF parent_level IS NULL THEN
        IF lvl = 0 THEN
            RAISE EXCEPTION 'level 0 cells do not have a parent'
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        target := lvl - 1;
    ELSE
        IF parent_level < 0 THEN
            RAISE EXCEPTION 'parent_level must be >= 0, got %', parent_level
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        IF parent_level > lvl THEN
            RAISE EXCEPTION 'parent_level (%) must be <= cell level (%)', parent_level, lvl
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        target := parent_level;
    END IF;

    RETURN substr(trimmed, 1, 7 + target);
END;
$$;

COMMENT ON FUNCTION qdgc_cell_to_parent(text, integer) IS
'Ancestor of a QDGC cell at parent_level, or the immediate parent when '
'parent_level is omitted. Mirrors h3_cell_to_parent.';

CREATE FUNCTION qdgc_cell_to_children(cell text, child_level integer DEFAULT NULL)
RETURNS SETOF text
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
    trimmed text := btrim(cell);
    lvl     integer;
    target  integer;
BEGIN
    IF cell IS NULL THEN
        RETURN;
    END IF;

    lvl := qdgc_get_level(trimmed);
    IF lvl IS NULL THEN
        RAISE EXCEPTION 'invalid QDGC code: %', cell
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    target := COALESCE(child_level, lvl + 1);
    IF target < lvl THEN
        RAISE EXCEPTION 'child_level (%) must be >= cell level (%)', target, lvl
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    IF target = lvl THEN
        RETURN NEXT trimmed;
        RETURN;
    END IF;

    RETURN QUERY
    WITH RECURSIVE descend(code, depth) AS (
        SELECT trimmed, lvl
        UNION ALL
        SELECT d.code || q.letter, d.depth + 1
        FROM descend d
        CROSS JOIN (VALUES ('A'), ('B'), ('C'), ('D')) AS q(letter)
        WHERE d.depth < target
    )
    SELECT code FROM descend WHERE depth = target ORDER BY code;
END;
$$;

COMMENT ON FUNCTION qdgc_cell_to_children(text, integer) IS
'Descendants of a QDGC cell at child_level, or the four immediate children '
'when child_level is omitted. Mirrors h3_cell_to_children.';

-- ---------------------------------------------------------------
-- 03-info.sql
-- ---------------------------------------------------------------
-- qdgc: level metrics and library metadata.

CREATE FUNCTION qdgc_level_degrees(level integer)
RETURNS double precision
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT CASE
        WHEN level < 0 THEN NULL
        ELSE 1.0 / (2::double precision ^ level)
    END;
$$;

COMMENT ON FUNCTION qdgc_level_degrees(integer) IS
'Cell side length in degrees at the given level. Level 0 is one degree.';

-- Total number of cells covering the globe at a level.
CREATE FUNCTION qdgc_get_num_cells(level integer)
RETURNS bigint
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT CASE
        WHEN level < 0 THEN NULL
        ELSE (360::numeric * 180 * (4::numeric ^ level))::bigint
    END;
$$;

COMMENT ON FUNCTION qdgc_get_num_cells(integer) IS
'Number of QDGC cells covering the whole globe at the given level. '
'Mirrors h3_get_num_cells.';

-- Approximate cell area on the sphere. With lat omitted this is the equatorial
-- upper bound; with lat supplied it is the area of a cell centred there.
-- Mirrors qdgc_py.core.average_cell_area, including the R = 6371.0088 km mean
-- radius, so server-side and desktop-side area estimates agree.
CREATE FUNCTION qdgc_average_cell_area(
    level integer,
    lat double precision DEFAULT NULL,
    unit text DEFAULT 'km^2')
RETURNS double precision
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
    earth_radius_km CONSTANT double precision := 6371.0088;
    side_deg    double precision;
    center_lat  double precision;
    half        double precision;
    lat1        double precision;
    lat2        double precision;
    dlon        double precision;
    area_km2    double precision;
    scale       double precision;
BEGIN
    IF level IS NULL OR level < 0 THEN
        RAISE EXCEPTION 'level must be >= 0, got %', level
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    scale := CASE lower(btrim(unit))
        WHEN 'km^2' THEN 1.0
        WHEN 'm^2'  THEN 1000000.0
        ELSE NULL
    END;
    IF scale IS NULL THEN
        RAISE EXCEPTION 'unit must be ''km^2'' or ''m^2'', got %', unit
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    side_deg := qdgc_level_degrees(level);

    -- NOTE: PostgreSQL's GREATEST/LEAST *ignore* NULL arguments rather than
    -- propagating them, so least(90.0, NULL) is 90.0, not NULL. Wrapping the
    -- clamp in COALESCE would therefore silently turn "no latitude given" into
    -- "latitude 90" and return a polar sliver. The NULL case must be handled
    -- before the clamp, not after it.
    center_lat := CASE WHEN lat IS NULL THEN 0.0
                       ELSE greatest(-90.0, least(90.0, lat)) END;

    half := side_deg / 2.0;
    lat1       := greatest(-90.0, center_lat - half);
    lat2       := least(90.0, center_lat + half);

    dlon     := radians(side_deg);
    area_km2 := (earth_radius_km ^ 2) * dlon
                * abs(sin(radians(lat2)) - sin(radians(lat1)));

    RETURN area_km2 * scale;
END;
$$;

COMMENT ON FUNCTION qdgc_average_cell_area(integer, double precision, text) IS
'Approximate area of a QDGC cell at the given level, optionally at a given '
'latitude. Units are ''km^2'' (default) or ''m^2''.';

CREATE FUNCTION qdgc_version()
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT '0.1.0'::text;
$$;

COMMENT ON FUNCTION qdgc_version() IS
'Version of the qdgc extension. Encoding output is stable within a major '
'version; a change to any produced code is a major bump.';

-- ---------------------------------------------------------------
-- 04-regions.sql
-- ---------------------------------------------------------------
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
