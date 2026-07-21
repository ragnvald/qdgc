-- Legacy-compatibility contract: SQL encoding must be bit-for-bit identical to
-- qdgc_py.core.encode. Vectors come from tools/gen_parity_fixture.py.
\set ON_ERROR_STOP on

DROP TABLE IF EXISTS parity_encode;
CREATE TABLE parity_encode (
    lon   double precision,
    lat   double precision,
    level integer,
    code  text
);

\copy parity_encode FROM 'test/data/parity_encode.csv' WITH (FORMAT csv, HEADER true)

DO $$
DECLARE
    total    bigint;
    bad      bigint;
    example  record;
BEGIN
    SELECT count(*) INTO total FROM parity_encode;
    IF total = 0 THEN
        RAISE EXCEPTION 'parity fixture is empty -- run tools/gen_parity_fixture.py';
    END IF;

    SELECT count(*) INTO bad
    FROM parity_encode
    WHERE qdgc_encode(lon, lat, level) IS DISTINCT FROM code;

    IF bad > 0 THEN
        FOR example IN
            SELECT lon, lat, level, code AS expected,
                   qdgc_encode(lon, lat, level) AS got
            FROM parity_encode
            WHERE qdgc_encode(lon, lat, level) IS DISTINCT FROM code
            LIMIT 5
        LOOP
            RAISE WARNING 'encode mismatch lon=% lat=% level=% expected=% got=%',
                example.lon, example.lat, example.level, example.expected, example.got;
        END LOOP;
        RAISE EXCEPTION 'encode parity FAILED: % of % vectors differ from qdgc_py', bad, total;
    END IF;

    RAISE NOTICE 'encode parity OK: % vectors match qdgc_py exactly', total;
END;
$$;

-- The h3-style alias must agree with the (lon, lat) form.
DO $$
DECLARE
    bad bigint;
BEGIN
    SELECT count(*) INTO bad
    FROM parity_encode
    WHERE qdgc_latlng_to_cell(lat, lon, level) IS DISTINCT FROM code;
    IF bad > 0 THEN
        RAISE EXCEPTION 'qdgc_latlng_to_cell disagrees with qdgc_encode on % rows', bad;
    END IF;
    RAISE NOTICE 'qdgc_latlng_to_cell alias OK';
END;
$$;
