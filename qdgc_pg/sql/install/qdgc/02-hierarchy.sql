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
