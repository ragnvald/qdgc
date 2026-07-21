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
