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
