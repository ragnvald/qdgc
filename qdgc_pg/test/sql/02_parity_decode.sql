-- Decoding must reproduce qdgc_py.core.decode_bounds exactly. Bounds are
-- dyadic rationals, so exact float equality is the right comparison here.
\set ON_ERROR_STOP on

DROP TABLE IF EXISTS parity_decode;
CREATE TABLE parity_decode (
    code         text,
    level        integer,
    min_lon      double precision,
    min_lat      double precision,
    max_lon      double precision,
    max_lat      double precision,
    centroid_lon double precision,
    centroid_lat double precision
);

\copy parity_decode FROM 'test/data/parity_decode.csv' WITH (FORMAT csv, HEADER true)

DO $$
DECLARE
    total   bigint;
    bad     bigint;
    example record;
BEGIN
    SELECT count(*) INTO total FROM parity_decode;
    IF total = 0 THEN
        RAISE EXCEPTION 'decode fixture is empty -- run tools/gen_parity_fixture.py';
    END IF;

    SELECT count(*) INTO bad
    FROM parity_decode p, LATERAL qdgc_cell_to_bounds(p.code) b
    WHERE (b.min_lon, b.min_lat, b.max_lon, b.max_lat)
       IS DISTINCT FROM (p.min_lon, p.min_lat, p.max_lon, p.max_lat);

    IF bad > 0 THEN
        FOR example IN
            SELECT p.code, p.min_lon, p.min_lat, p.max_lon, p.max_lat,
                   b.min_lon AS got_min_lon, b.min_lat AS got_min_lat,
                   b.max_lon AS got_max_lon, b.max_lat AS got_max_lat
            FROM parity_decode p, LATERAL qdgc_cell_to_bounds(p.code) b
            WHERE (b.min_lon, b.min_lat, b.max_lon, b.max_lat)
               IS DISTINCT FROM (p.min_lon, p.min_lat, p.max_lon, p.max_lat)
            LIMIT 5
        LOOP
            RAISE WARNING 'bounds mismatch % expected=(%,%,%,%) got=(%,%,%,%)',
                example.code, example.min_lon, example.min_lat,
                example.max_lon, example.max_lat,
                example.got_min_lon, example.got_min_lat,
                example.got_max_lon, example.got_max_lat;
        END LOOP;
        RAISE EXCEPTION 'decode parity FAILED: % of % cells differ from qdgc_py', bad, total;
    END IF;

    RAISE NOTICE 'decode parity OK: % cells match qdgc_py exactly', total;
END;
$$;

DO $$
DECLARE
    bad bigint;
BEGIN
    SELECT count(*) INTO bad FROM parity_decode WHERE qdgc_get_level(code) IS DISTINCT FROM level;
    IF bad > 0 THEN
        RAISE EXCEPTION 'qdgc_get_level disagrees with qdgc_py on % cells', bad;
    END IF;

    SELECT count(*) INTO bad
    FROM parity_decode p, LATERAL qdgc_cell_to_latlng(p.code) c
    WHERE (c.lng, c.lat) IS DISTINCT FROM (p.centroid_lon, p.centroid_lat);
    IF bad > 0 THEN
        RAISE EXCEPTION 'qdgc_cell_to_latlng disagrees with qdgc_py on % cells', bad;
    END IF;

    RAISE NOTICE 'level and centroid accessors OK';
END;
$$;

-- Round trip: encoding a cell's own centroid must return that cell.
DO $$
DECLARE
    bad bigint;
BEGIN
    SELECT count(*) INTO bad
    FROM parity_decode p
    WHERE qdgc_encode(p.centroid_lon, p.centroid_lat, p.level) IS DISTINCT FROM p.code;
    IF bad > 0 THEN
        RAISE EXCEPTION 'centroid round trip FAILED for % cells', bad;
    END IF;
    RAISE NOTICE 'centroid round trip OK';
END;
$$;
