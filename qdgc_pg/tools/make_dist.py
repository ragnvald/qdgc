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


# PGXN Meta Spec v1.0.0 <https://pgxn.org/meta/spec.txt>. PGXN validates the
# upload with a Perl module we cannot run here, so this catches the structural
# mistakes that would otherwise be rejected only after a manual upload.
REQUIRED_FIELDS = ("name", "version", "abstract", "maintainer", "license",
                   "provides", "meta-spec")

# The subset of spec licence strings worth allowing here; the full list is
# longer, but silently accepting a typo is the failure mode to avoid.
KNOWN_LICENSES = {"apache_2_0", "apache_1_1", "bsd", "mit", "postgresql",
                  "gpl_2", "gpl_3", "lgpl_2_1", "lgpl_3_0", "unrestricted"}


def validate_meta(meta: dict) -> None:
    missing = [f for f in REQUIRED_FIELDS if f not in meta]
    if missing:
        fail(f"META.json is missing required field(s): {', '.join(missing)}")

    if meta["license"] not in KNOWN_LICENSES:
        fail(f"META.json license '{meta['license']}' is not a recognised PGXN "
             f"licence string (expected one of: {', '.join(sorted(KNOWN_LICENSES))})")

    if not isinstance(meta["provides"], dict) or not meta["provides"]:
        fail("META.json 'provides' must be a non-empty object")

    for ext, spec in meta["provides"].items():
        for key in ("file", "version"):
            if key not in spec:
                fail(f"META.json provides.{ext} is missing '{key}'")

    if meta.get("meta-spec", {}).get("version") != "1.0.0":
        fail("META.json meta-spec.version must be '1.0.0'")


def main() -> int:
    meta_path = ROOT / "META.json"
    if not meta_path.is_file():
        fail("META.json not found")
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"META.json is not valid JSON: {exc}")
    validate_meta(meta)
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
