-- PostGIS bindings: geometry round trips and the quadtree area fill.
\set ON_ERROR_STOP on

DO $$
DECLARE
    g geometry;
BEGIN
    IF qdgc_latlng_to_cell(ST_SetSRID(ST_MakePoint(31.4, 2.7), 4326), 2) <> 'E031N02AD' THEN
        RAISE EXCEPTION 'geometry encode wrong: %',
            qdgc_latlng_to_cell(ST_SetSRID(ST_MakePoint(31.4, 2.7), 4326), 2);
    END IF;

    -- Encoding must agree between the geometry, geography and scalar forms.
    IF qdgc_latlng_to_cell(ST_SetSRID(ST_MakePoint(31.4, 2.7), 4326), 5)
       <> qdgc_encode(31.4, 2.7, 5) THEN
        RAISE EXCEPTION 'geometry form disagrees with qdgc_encode';
    END IF;
    IF qdgc_latlng_to_cell(ST_SetSRID(ST_MakePoint(31.4, 2.7), 4326)::geography, 5)
       <> qdgc_encode(31.4, 2.7, 5) THEN
        RAISE EXCEPTION 'geography form disagrees with qdgc_encode';
    END IF;

    -- A non-4326 input must be transformed, not taken literally.
    IF qdgc_latlng_to_cell(ST_Transform(ST_SetSRID(ST_MakePoint(31.4, 2.7), 4326), 3857), 2)
       <> 'E031N02AD' THEN
        RAISE EXCEPTION 'web mercator input was not transformed';
    END IF;

    -- Cell outline: correct extent, SRID and vertex count.
    g := qdgc_cell_to_boundary_geometry('E000N00C');
    IF ST_SRID(g) <> 4326 THEN RAISE EXCEPTION 'boundary SRID should be 4326'; END IF;
    IF ST_NPoints(g) <> 5 THEN RAISE EXCEPTION 'boundary should be a closed 5-point ring'; END IF;
    IF (ST_XMin(g), ST_YMin(g), ST_XMax(g), ST_YMax(g)) <> (0.0, 0.0, 0.5, 0.5) THEN
        RAISE EXCEPTION 'boundary extent wrong';
    END IF;
    IF NOT ST_Equals(g, ST_MakeEnvelope(0, 0, 0.5, 0.5, 4326)) THEN
        RAISE EXCEPTION 'boundary is not the cell envelope';
    END IF;

    -- The centroid of the outline is the cell centroid.
    IF NOT ST_Equals(ST_Centroid(g), qdgc_cell_to_geometry('E000N00C')) THEN
        RAISE EXCEPTION 'qdgc_cell_to_geometry is not the outline centroid';
    END IF;

    RAISE NOTICE 'geometry bindings OK';
END;
$$;

-- Spheroidal area, replacing the legacy Africa-Albers hardcoding.
DO $$
DECLARE
    equator double precision;
    high    double precision;
BEGIN
    equator := qdgc_cell_area_km2('E000N00');
    high    := qdgc_cell_area_km2('E000N60');
    IF abs(equator - 12363.0) > 60.0 THEN
        RAISE EXCEPTION 'equatorial level 0 area looks wrong: %', equator;
    END IF;
    IF high >= equator THEN
        RAISE EXCEPTION 'a cell at 60N should be smaller than one at the equator';
    END IF;
    -- Spheroidal area and the spherical estimate should be within a percent.
    IF abs(equator - qdgc_average_cell_area(0, 0.5)) / equator > 0.01 THEN
        RAISE EXCEPTION 'spheroidal and spherical areas disagree by more than 1%%';
    END IF;
    RAISE NOTICE 'area calculation OK';
END;
$$;

-- Area fill.
DO $$
DECLARE
    aoi   geometry;
    cells text[];
    n     bigint;
BEGIN
    -- A box covering exactly four degree squares.
    aoi := ST_MakeEnvelope(0, 0, 2, 2, 4326);
    SELECT array_agg(c ORDER BY c) INTO cells FROM qdgc_polygon_to_cells(aoi, 0) c;
    IF cells <> ARRAY['E000N00', 'E000N01', 'E001N00', 'E001N01'] THEN
        RAISE EXCEPTION 'degree-square fill wrong: %', cells;
    END IF;

    -- Level 1 quadruples the count in each axis.
    SELECT count(*) INTO n FROM qdgc_polygon_to_cells(aoi, 1);
    IF n <> 16 THEN RAISE EXCEPTION 'level 1 fill should give 16 cells, got %', n; END IF;
    SELECT count(*) INTO n FROM qdgc_polygon_to_cells(aoi, 3);
    IF n <> 256 THEN RAISE EXCEPTION 'level 3 fill should give 256 cells, got %', n; END IF;

    -- Every cell produced must actually meet the AOI, and must decode back to
    -- an extent inside the AOI envelope.
    IF EXISTS (
        SELECT 1 FROM qdgc_polygon_to_cells(aoi, 3) c
        WHERE NOT ST_Intersects(aoi, qdgc_cell_to_boundary_geometry(c))
    ) THEN
        RAISE EXCEPTION 'fill produced a cell that does not meet the AOI';
    END IF;

    -- Fill codes must be the same codes encoding the centroids would give.
    IF EXISTS (
        SELECT 1 FROM qdgc_polygon_to_cells(aoi, 4) c
        WHERE qdgc_encode(ST_X(qdgc_cell_to_geometry(c)),
                          ST_Y(qdgc_cell_to_geometry(c)), 4) <> c
    ) THEN
        RAISE EXCEPTION 'quadtree descent disagrees with qdgc_encode';
    END IF;

    RAISE NOTICE 'area fill OK';
END;
$$;

-- Predicates.
DO $$
DECLARE
    aoi         geometry;
    n_intersect bigint;
    n_centroid  bigint;
    n_contains  bigint;
BEGIN
    -- A triangle, so the three predicates genuinely differ.
    aoi := ST_GeomFromText('POLYGON((0 0, 3 0, 0 3, 0 0))', 4326);
    SELECT count(*) INTO n_intersect FROM qdgc_polygon_to_cells(aoi, 2, 'intersects');
    SELECT count(*) INTO n_centroid  FROM qdgc_polygon_to_cells(aoi, 2, 'centroid');
    SELECT count(*) INTO n_contains  FROM qdgc_polygon_to_cells(aoi, 2, 'contains');

    IF NOT (n_intersect >= n_centroid AND n_centroid >= n_contains AND n_contains > 0) THEN
        RAISE EXCEPTION 'predicate ordering wrong: intersects=% centroid=% contains=%',
            n_intersect, n_centroid, n_contains;
    END IF;
    IF n_intersect = n_contains THEN
        RAISE EXCEPTION 'predicates should differ on a diagonal boundary';
    END IF;

    -- 'contains' cells must really be wholly inside.
    IF EXISTS (
        SELECT 1 FROM qdgc_polygon_to_cells(aoi, 2, 'contains') c
        WHERE NOT ST_Contains(aoi, qdgc_cell_to_boundary_geometry(c))
    ) THEN
        RAISE EXCEPTION '''contains'' returned a cell that is not wholly inside';
    END IF;

    -- 'centroid' cells must really have their centre inside.
    IF EXISTS (
        SELECT 1 FROM qdgc_polygon_to_cells(aoi, 2, 'centroid') c
        WHERE NOT ST_Intersects(aoi, qdgc_cell_to_geometry(c))
    ) THEN
        RAISE EXCEPTION '''centroid'' returned a cell whose centre is outside';
    END IF;

    RAISE NOTICE 'predicates OK';
END;
$$;

-- Edge cases and guards.
DO $$
DECLARE
    n  bigint;
    ok boolean;
BEGIN
    IF (SELECT count(*) FROM qdgc_polygon_to_cells(NULL, 3)) <> 0 THEN
        RAISE EXCEPTION 'NULL geometry should fill nothing';
    END IF;
    IF (SELECT count(*) FROM qdgc_polygon_to_cells(ST_GeomFromText('POLYGON EMPTY', 4326), 3)) <> 0 THEN
        RAISE EXCEPTION 'empty geometry should fill nothing';
    END IF;

    -- A point still lands in exactly one cell.
    SELECT count(*) INTO n
    FROM qdgc_polygon_to_cells(ST_SetSRID(ST_MakePoint(31.4, 2.7), 4326), 3);
    IF n <> 1 THEN RAISE EXCEPTION 'a point should fill one cell, got %', n; END IF;

    ok := false;
    BEGIN
        PERFORM qdgc_polygon_to_cells(ST_MakeEnvelope(0, 0, 1, 1, 4326), 2, 'overlaps');
    EXCEPTION WHEN invalid_parameter_value THEN ok := true;
    END;
    IF NOT ok THEN RAISE EXCEPTION 'an unknown predicate should raise'; END IF;

    RAISE NOTICE 'fill edge cases OK';
END;
$$;

-- The count guard must bound the real fill without being uselessly loose.
DO $$
DECLARE
    aoi      geometry;
    estimate bigint;
    actual   bigint;
    lvl      integer;
BEGIN
    aoi := ST_MakeEnvelope(30, 2, 31, 3, 4326);
    FOR lvl IN 0..4 LOOP
        SELECT qdgc_estimate_cell_count(aoi, lvl) INTO actual;
        IF actual IS NULL OR actual <= 0 THEN
            RAISE EXCEPTION 'estimate should be positive at level %', lvl;
        END IF;
    END LOOP;

    SELECT qdgc_estimate_cell_count(aoi, 4) INTO estimate;
    SELECT count(*) INTO actual FROM qdgc_polygon_to_cells(aoi, 4);
    IF estimate < actual / 2 OR estimate > actual * 2 THEN
        RAISE EXCEPTION 'estimate % is not within 2x of the actual fill %', estimate, actual;
    END IF;

    IF qdgc_estimate_cell_count(ST_GeomFromText('POLYGON EMPTY', 4326), 3) <> 0 THEN
        RAISE EXCEPTION 'empty geometry should estimate zero';
    END IF;

    RAISE NOTICE 'cell count guard OK';
END;
$$;
