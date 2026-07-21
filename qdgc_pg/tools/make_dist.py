"""Build the PGXN release archive for the qdgc extensions.

PGXN takes an uploaded archive rather than reading the repository, so living in
a monorepo subdirectory is not a problem: the archive is built from qdgc_pg/
with a versioned top-level prefix, which is what PGXN expects.

    python tools/make_dist.py

Produces dist/qdgc-<version>.zip. Only files tracked by git are included, so a
stray local file can never leak into a release.
"""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO = ROOT.parent
DIST = ROOT / "dist"


def fail(message: str) -> None:
    raise SystemExit(f"make_dist: {message}")


def main() -> int:
    meta_path = ROOT / "META.json"
    if not meta_path.is_file():
        fail("META.json not found")
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    version = meta["version"]
    name = meta["name"]

    # The version has to agree in four places or the release is broken on
    # arrival: META.json, both control files, and the generated SQL filenames.
    for control in (f"{ext}.control" for ext in ("qdgc", "qdgc_postgis")):
        text = (ROOT / control).read_text(encoding="utf-8")
        if f"default_version = '{version}'" not in text:
            fail(f"{control} does not declare default_version = '{version}'")

    for provided in meta["provides"].values():
        sql = ROOT / provided["file"]
        if not sql.is_file():
            fail(f"{provided['file']} is missing -- run tools/build_sql.py")

    # Refuse to package a dirty tree: git archive reads HEAD, so uncommitted
    # edits would be silently absent from the release.
    status = subprocess.run(["git", "status", "--porcelain", "--", str(ROOT)],
                            cwd=REPO, capture_output=True, text=True)
    if status.returncode != 0:
        fail(f"git status failed: {status.stderr.strip()}")
    if status.stdout.strip():
        fail("qdgc_pg has uncommitted changes; commit them before building a release\n"
             + status.stdout.rstrip())

    DIST.mkdir(exist_ok=True)
    out = DIST / f"{name}-{version}.zip"
    if out.exists():
        out.unlink()

    result = subprocess.run(
        ["git", "archive", "--format=zip", f"--prefix={name}-{version}/",
         "-o", str(out), "HEAD:qdgc_pg"],
        cwd=REPO, capture_output=True, text=True)
    if result.returncode != 0:
        fail(f"git archive failed: {result.stderr.strip()}")

    print(f"built {out.relative_to(REPO)}  ({out.stat().st_size:,} bytes)")
    print()
    print("Upload it at https://manager.pgxn.org/upload")
    return 0


if __name__ == "__main__":
    sys.exit(main())
