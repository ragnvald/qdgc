-- Prepare a clean schema for the test run.
--
-- Installing via CREATE EXTENSION needs write access to the server's
-- share/extension directory, which a developer workstation usually does not
-- have. The runner therefore loads sql/install/**.sql straight into a
-- throwaway schema; the SQL under test is byte-identical either way.
\set ON_ERROR_STOP on

CREATE EXTENSION IF NOT EXISTS postgis;

DROP SCHEMA IF EXISTS qdgc_test CASCADE;
CREATE SCHEMA qdgc_test;

SELECT postgis_lib_version() AS postgis_version, version() AS server_version;
