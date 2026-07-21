"""Concatenate the numbered install sources into versioned extension scripts.

Authoring stays modular under sql/install/<extension>/NN-*.sql; PostgreSQL
wants a single <extension>--<version>.sql. This mirrors how h3-pg builds its
install script, minus the CMake.

Usage (from qdgc_pg/):
    python tools/build_sql.py
"""
from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
VERSION = "0.1.0"
EXTENSIONS = ("qdgc", "qdgc_postgis")

HEADER = """\
-- {ext}--{version}.sql
--
-- GENERATED FILE -- do not edit.
-- Built from sql/install/{ext}/*.sql by tools/build_sql.py.

\\echo Use "CREATE EXTENSION {ext}" to load this file. \\quit
"""


def build(ext: str) -> pathlib.Path:
    src_dir = ROOT / "sql" / "install" / ext
    sources = sorted(src_dir.glob("*.sql"))
    if not sources:
        raise SystemExit(f"no sources found in {src_dir}")

    parts = [HEADER.format(ext=ext, version=VERSION)]
    for path in sources:
        parts.append(f"\n-- ---------------------------------------------------------------\n"
                     f"-- {path.name}\n"
                     f"-- ---------------------------------------------------------------\n")
        parts.append(path.read_text(encoding="utf-8").rstrip() + "\n")

    out = ROOT / f"{ext}--{VERSION}.sql"
    out.write_text("".join(parts), encoding="utf-8", newline="\n")
    print(f"  {out.relative_to(ROOT)}  <- {len(sources)} source file(s)")
    return out


def main() -> int:
    print(f"building qdgc extension SQL, version {VERSION}")
    for ext in EXTENSIONS:
        build(ext)
    return 0


if __name__ == "__main__":
    sys.exit(main())
