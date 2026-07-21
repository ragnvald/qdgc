# PGXS makefile for the qdgc / qdgc_postgis extensions.
#
# Pure SQL: there is nothing to compile, so this only installs files and runs
# the regression tests.
#
#   make install
#   make installcheck        # needs a running server; see README.md

EXTENSION = qdgc qdgc_postgis
EXTVERSION = 0.1.0

DATA = qdgc--$(EXTVERSION).sql qdgc_postgis--$(EXTVERSION).sql

REGRESS = qdgc_encode qdgc_decode qdgc_hierarchy qdgc_parity qdgc_postgis
REGRESS_OPTS = --inputdir=test --load-extension=postgis

PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Regenerate the concatenated install scripts from sql/install/.
.PHONY: sql
sql:
	python3 tools/build_sql.py
