-- Public API behaviour: the locked boundary conventions, hierarchy, level
-- metrics, and the error cases.
\set ON_ERROR_STOP on

DO $$
DECLARE
    got text;
BEGIN
    -- The locked (0,0) convention: resolves E/N, then the lower-left subcell.
    got := qdgc_encode(0, 0, 1);
    IF got <> 'E000N00C' THEN
        RAISE EXCEPTION 'locked (0,0) convention broken: expected E000N00C, got %', got;
    END IF;

    IF qdgc_encode(0, 0, 0) <> 'E000N00' THEN
        RAISE EXCEPTION 'level 0 of (0,0) should be the bare degree square';
    END IF;

    -- Hemispheres.
    IF qdgc_degree_prefix(31.4, 2.7) <> 'E031N02' THEN
        RAISE EXCEPTION 'north-east prefix wrong: %', qdgc_degree_prefix(31.4, 2.7);
    END IF;
    IF qdgc_degree_prefix(-31.4, -2.7) <> 'W031S02' THEN
        RAISE EXCEPTION 'south-west prefix wrong: %', qdgc_degree_prefix(-31.4, -2.7);
    END IF;

    RAISE NOTICE 'boundary conventions OK';
END;
$$;

-- A/B/C/D orientation is locked: A=NW, B=NE, C=SW, D=SE.
DO $$
DECLARE
    b record;
BEGIN
    SELECT * INTO b FROM qdgc_cell_to_bounds('E000N00A') AS t;
    IF (b.min_lon, b.min_lat, b.max_lon, b.max_lat) <> (0.0, 0.5, 0.5, 1.0) THEN
        RAISE EXCEPTION 'A is not the north-west subcell: (%,%,%,%)',
            b.min_lon, b.min_lat, b.max_lon, b.max_lat;
    END IF;
    SELECT * INTO b FROM qdgc_cell_to_bounds('E000N00B') AS t;
    IF (b.min_lon, b.min_lat, b.max_lon, b.max_lat) <> (0.5, 0.5, 1.0, 1.0) THEN
        RAISE EXCEPTION 'B is not the north-east subcell';
    END IF;
    SELECT * INTO b FROM qdgc_cell_to_bounds('E000N00C') AS t;
    IF (b.min_lon, b.min_lat, b.max_lon, b.max_lat) <> (0.0, 0.0, 0.5, 0.5) THEN
        RAISE EXCEPTION 'C is not the south-west subcell';
    END IF;
    SELECT * INTO b FROM qdgc_cell_to_bounds('E000N00D') AS t;
    IF (b.min_lon, b.min_lat, b.max_lon, b.max_lat) <> (0.5, 0.0, 1.0, 0.5) THEN
        RAISE EXCEPTION 'D is not the south-east subcell';
    END IF;
    RAISE NOTICE 'A/B/C/D orientation OK';
END;
$$;

-- Validity.
DO $$
BEGIN
    IF NOT qdgc_is_valid_cell('E031N02ABCD') THEN
        RAISE EXCEPTION 'valid code rejected';
    END IF;
    IF qdgc_is_valid_cell('E031N02ABXD') THEN
        RAISE EXCEPTION 'code with an illegal letter accepted';
    END IF;
    IF qdgc_is_valid_cell('E31N02') THEN
        RAISE EXCEPTION 'code with a short degree field accepted';
    END IF;
    IF qdgc_is_valid_cell('E181N02') THEN
        RAISE EXCEPTION 'code outside the WGS84 extent accepted';
    END IF;
    IF qdgc_get_level('nonsense') IS NOT NULL THEN
        RAISE EXCEPTION 'qdgc_get_level should be NULL for an invalid code';
    END IF;
    RAISE NOTICE 'validity checks OK';
END;
$$;

-- Hierarchy, including the prefix property that makes btree range scans work.
DO $$
DECLARE
    kids text[];
BEGIN
    IF qdgc_cell_to_parent('E031N02ABCD') <> 'E031N02ABC' THEN
        RAISE EXCEPTION 'immediate parent wrong: %', qdgc_cell_to_parent('E031N02ABCD');
    END IF;
    IF qdgc_cell_to_parent('E031N02ABCD', 0) <> 'E031N02' THEN
        RAISE EXCEPTION 'parent at level 0 wrong';
    END IF;
    IF qdgc_cell_to_parent('E031N02ABCD', 4) <> 'E031N02ABCD' THEN
        RAISE EXCEPTION 'parent at own level should be the cell itself';
    END IF;

    SELECT array_agg(c ORDER BY c) INTO kids FROM qdgc_cell_to_children('E000N00') c;
    IF kids <> ARRAY['E000N00A', 'E000N00B', 'E000N00C', 'E000N00D'] THEN
        RAISE EXCEPTION 'immediate children wrong: %', kids;
    END IF;

    IF (SELECT count(*) FROM qdgc_cell_to_children('E000N00', 3)) <> 64 THEN
        RAISE EXCEPTION 'expected 64 grandchildren at level 3';
    END IF;

    -- Every descendant is prefixed by its ancestor.
    IF EXISTS (SELECT 1 FROM qdgc_cell_to_children('E031N02AB', 5) c
               WHERE c NOT LIKE 'E031N02AB%') THEN
        RAISE EXCEPTION 'prefix containment broken';
    END IF;

    RAISE NOTICE 'hierarchy OK';
END;
$$;

-- Level metrics.
DO $$
BEGIN
    IF qdgc_level_degrees(0) <> 1.0 THEN
        RAISE EXCEPTION 'level 0 should be one degree';
    END IF;
    IF qdgc_level_degrees(2) <> 0.25 THEN
        RAISE EXCEPTION 'level 2 should be a quarter degree';
    END IF;
    IF qdgc_get_num_cells(0) <> 64800 THEN
        RAISE EXCEPTION 'level 0 should have 360*180 cells, got %', qdgc_get_num_cells(0);
    END IF;
    IF qdgc_get_num_cells(2) <> 64800 * 16 THEN
        RAISE EXCEPTION 'level 2 cell count wrong';
    END IF;
    -- Equatorial level 0 cell is about 12360 km2.
    IF abs(qdgc_average_cell_area(0) - 12363.0) > 20.0 THEN
        RAISE EXCEPTION 'equatorial level 0 area looks wrong: %', qdgc_average_cell_area(0);
    END IF;
    -- Cells shrink towards the poles.
    IF qdgc_average_cell_area(0, 60.0) >= qdgc_average_cell_area(0, 0.0) THEN
        RAISE EXCEPTION 'area at 60N should be smaller than at the equator';
    END IF;
    IF abs(qdgc_average_cell_area(0, 0.0, 'm^2') - qdgc_average_cell_area(0) * 1e6) > 1.0 THEN
        RAISE EXCEPTION 'm^2 unit conversion wrong';
    END IF;
    RAISE NOTICE 'level metrics OK';
END;
$$;

-- Error cases must raise rather than return something plausible.
DO $$
DECLARE
    ok boolean;
BEGIN
    ok := false;
    BEGIN
        PERFORM qdgc_cell_to_bounds('not-a-code');
    EXCEPTION WHEN invalid_parameter_value THEN ok := true;
    END;
    IF NOT ok THEN RAISE EXCEPTION 'invalid code should raise'; END IF;

    ok := false;
    BEGIN
        PERFORM qdgc_encode(0, 0, -1);
    EXCEPTION WHEN invalid_parameter_value THEN ok := true;
    END;
    IF NOT ok THEN RAISE EXCEPTION 'negative level should raise'; END IF;

    ok := false;
    BEGIN
        PERFORM qdgc_cell_to_parent('E000N00');
    EXCEPTION WHEN invalid_parameter_value THEN ok := true;
    END;
    IF NOT ok THEN RAISE EXCEPTION 'level 0 parent should raise'; END IF;

    ok := false;
    BEGIN
        PERFORM qdgc_average_cell_area(0, 0, 'furlongs^2');
    EXCEPTION WHEN invalid_parameter_value THEN ok := true;
    END;
    IF NOT ok THEN RAISE EXCEPTION 'bad unit should raise'; END IF;

    RAISE NOTICE 'error handling OK';
END;
$$;

-- Bounding-box fills, including the antimeridian.
DO $$
DECLARE
    n bigint;
BEGIN
    SELECT count(*) INTO n FROM qdgc_bbox_to_cells(0, 0, 2, 2, 0);
    IF n <> 4 THEN RAISE EXCEPTION 'expected 4 degree squares, got %', n; END IF;

    IF qdgc_bbox_cell_count(0, 0, 2, 2, 0) <> 4 THEN
        RAISE EXCEPTION 'bbox count disagrees with the fill';
    END IF;
    IF qdgc_bbox_cell_count(0, 0, 2, 2, 1) <> 16 THEN
        RAISE EXCEPTION 'level 1 bbox count wrong';
    END IF;

    -- Crossing the antimeridian: min_lon > max_lon.
    SELECT count(*) INTO n FROM qdgc_bbox_to_cells(179, 0, -179, 1, 0);
    IF n <> 2 THEN RAISE EXCEPTION 'antimeridian fill should give 2 cells, got %', n; END IF;
    IF NOT EXISTS (SELECT 1 FROM qdgc_bbox_to_cells(179, 0, -179, 1, 0) c WHERE c = 'E179N00')
    OR NOT EXISTS (SELECT 1 FROM qdgc_bbox_to_cells(179, 0, -179, 1, 0) c WHERE c = 'W179N00') THEN
        RAISE EXCEPTION 'antimeridian fill returned the wrong cells';
    END IF;

    RAISE NOTICE 'bbox fills OK';
END;
$$;
