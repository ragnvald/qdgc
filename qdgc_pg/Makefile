# PGXS makefile for the qdgc / qdgc_postgis extensions.
#
# Pure SQL: there is nothing to compile, so this only installs files.
#
#   make install                 # copy control + SQL into the extension dir
#   make sql                     # regenerate the versioned install scripts
#   make dist                    # build the PGXN release archive
#
# Tests are not wired to pg_regress. They live in test/sql/ and are driven by
# tools/run_tests.py, which asserts with RAISE EXCEPTION rather than diffing
# expected output, and can run against a local or a remote server:
#
#   python3 tools/run_tests.py
#
# See README.md. The GitHub workflow runs the same suite across PostgreSQL
# versions after a real `make install`.

EXTENSION = qdgc qdgc_postgis
EXTVERSION = 0.1.0

DATA = qdgc--$(EXTVERSION).sql qdgc_postgis--$(EXTVERSION).sql

PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

.PHONY: sql dist

# Regenerate the concatenated install scripts from sql/install/.
sql:
	python3 tools/build_sql.py

# Build the PGXN release archive.
dist:
	python3 tools/make_dist.py
