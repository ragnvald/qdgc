-- Prepare a clean schema for the test run.
--
-- Installing via CREATE EXTENSION needs write access to the server's
-- share/extension directory, which a developer workstation usually does not
-- have. The runner therefore loads sql/install/**.sql straight into a
-- throwaway schema; the SQL under test is byte-identical either way.
\set ON_ERROR_STOP on

-- Only attempt to create PostGIS when it is genuinely missing. CREATE EXTENSION
-- needs privileges the test role may not have, and on a shared server PostGIS
-- is normally already installed by someone else.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis') THEN
        CREATE EXTENSION postgis;
    END IF;
END;
$$;

DROP SCHEMA IF EXISTS qdgc_test CASCADE;
CREATE SCHEMA qdgc_test;

SELECT postgis_lib_version() AS postgis_version, version() AS server_version;
