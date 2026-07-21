Local credentials
=================

Connection details for the PostGIS instance used to run the `qdgc_pg` test
suite. **Everything in this folder except this README is gitignored** (see the
repo root `.gitignore`); nothing here should ever be committed.

Files
-----

| File | Purpose |
|---|---|
| `postgis.env` | libpq environment variables for the test database |

`postgis.env` format
--------------------

```
PGHOST=...
PGPORT=5432
PGDATABASE=...
PGUSER=...
PGPASSWORD=...
```

Usage
-----

`qdgc_pg/tools/run_tests.py` reads this file automatically when it exists:

```bash
cd qdgc_pg
python tools/run_tests.py
```

Shared-instance safety
----------------------

The instance this points at is **shared with other work**. The test runner is
therefore constrained to:

- a single database whose name it is given explicitly, and
- a single schema, `qdgc_test`, inside it.

It will not drop or create databases, and it will not touch any other schema.
If you point it at a database, expect the `qdgc_test` schema in that database to
be dropped and recreated on every run — nothing else.
