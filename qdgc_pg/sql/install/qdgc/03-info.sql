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
