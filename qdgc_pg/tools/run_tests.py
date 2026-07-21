"""Run the qdgc SQL test suite against a PostgreSQL server.

Every test file raises an exception on failure, so a clean exit means the suite
passed -- there are no expected-output files to drift.

    python tools/run_tests.py

Connection settings come from ../secrets/postgis.env, then from the standard
libpq environment variables (PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD),
then from the flags below -- later sources win.

Two modes:

* local  -- psql runs on this machine against PGHOST.
* remote -- when ../secrets/remote.env supplies REMOTE_HOST/REMOTE_USER, the
            SQL and fixtures are copied to the remote host over scp and psql
            runs there. This is what you want when the server only listens on
            its own loopback. Force with --remote / --local.

SHARED INSTANCE SAFETY: this runner never creates or drops a database. It owns
exactly one schema, `qdgc_test`, in whichever database it is pointed at, and
drops and recreates only that. Nothing outside that schema is touched.
"""
from __future__ import annotations

import argparse
import glob
import os
import pathlib
import shlex
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
SECRETS = ROOT.parent / "secrets"
REMOTE_DIR = "/tmp/qdgc_pg_test"


def read_env_file(path: pathlib.Path) -> dict:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def find_psql() -> str:
    found = shutil.which("psql")
    if found:
        return found
    # Windows installs rarely put psql on PATH.
    for base in sorted(glob.glob(r"C:\Program Files\PostgreSQL\*\bin\psql.exe"), reverse=True):
        return base
    raise SystemExit("psql not found; add it to PATH or pass --psql")


class LocalBackend:
    """Run psql on this machine."""

    def __init__(self, psql: str, conn: list[str], env: dict):
        self.psql = psql
        self.conn = conn
        self.env = env

    def describe(self) -> str:
        return "local psql"

    def prepare(self) -> None:
        pass

    def psql_file(self, rel_path: str) -> subprocess.CompletedProcess:
        cmd = [self.psql, "-v", "ON_ERROR_STOP=1", "--no-psqlrc", "-w"] + self.conn + ["-f", rel_path]
        return subprocess.run(cmd, env=self.env, cwd=ROOT, capture_output=True, text=True)


class RemoteBackend:
    """Copy the suite to a host over scp and run psql there."""

    def __init__(self, host: str, user: str, key: pathlib.Path | None, conn: list[str], env: dict):
        self.target = f"{user}@{host}"
        self.key = key
        self.conn = conn
        self.env = env
        self.ssh_opts = ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new"]
        if key:
            self.ssh_opts = ["-i", str(key)] + self.ssh_opts

    def describe(self) -> str:
        return f"remote psql over ssh to {self.target}"

    def _ssh(self, command: str) -> subprocess.CompletedProcess:
        return subprocess.run(["ssh"] + self.ssh_opts + [self.target, command],
                              capture_output=True, text=True)

    def prepare(self) -> None:
        res = self._ssh(f"rm -rf {REMOTE_DIR} && mkdir -p {REMOTE_DIR}")
        if res.returncode != 0:
            raise SystemExit(f"could not prepare {REMOTE_DIR}: {res.stderr.strip()}")

        scp_opts = ["-q", "-r"]
        if self.key:
            scp_opts = ["-i", str(self.key)] + scp_opts
        scp_opts += ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new"]
        payload = [str(ROOT / "sql"), str(ROOT / "test")]
        res = subprocess.run(["scp"] + scp_opts + payload + [f"{self.target}:{REMOTE_DIR}/"],
                             capture_output=True, text=True)
        if res.returncode != 0:
            raise SystemExit(f"scp failed: {res.stderr.strip()}")
        print(f"copied sql/ and test/ to {self.target}:{REMOTE_DIR}")

    def psql_file(self, rel_path: str) -> subprocess.CompletedProcess:
        # PGPASSWORD is passed inline so it never lands in the remote shell
        # history or in a file on the remote host.
        assignments = " ".join(
            f"{k}={shlex.quote(v)}" for k, v in sorted(self.env.items())
            if k.startswith("PG")
        )
        conn = " ".join(shlex.quote(c) for c in self.conn)
        command = (f"cd {REMOTE_DIR} && {assignments} "
                   f"psql -v ON_ERROR_STOP=1 --no-psqlrc -w {conn} -f {shlex.quote(rel_path)}")
        return self._ssh(command)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dbname", default=None)
    ap.add_argument("--host", default=None)
    ap.add_argument("--port", default=None)
    ap.add_argument("--user", default=None)
    ap.add_argument("--psql", default=None)
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--remote", action="store_true", help="force running psql on the remote host")
    mode.add_argument("--local", action="store_true", help="force running psql on this machine")
    args = ap.parse_args()

    pg = read_env_file(SECRETS / "postgis.env")
    remote = read_env_file(SECRETS / "remote.env")
    if pg:
        print(f"loaded connection settings from {SECRETS / 'postgis.env'}")

    dbname = args.dbname or pg.get("PGDATABASE") or os.environ.get("PGDATABASE")
    host = args.host or pg.get("PGHOST") or os.environ.get("PGHOST", "127.0.0.1")
    port = args.port or pg.get("PGPORT") or os.environ.get("PGPORT", "5432")
    user = args.user or pg.get("PGUSER") or os.environ.get("PGUSER", "postgres")
    password = pg.get("PGPASSWORD") or os.environ.get("PGPASSWORD", "")
    if not dbname:
        raise SystemExit("no database given: set PGDATABASE in secrets/postgis.env or pass --dbname")

    conn = ["-h", host, "-p", str(port), "-U", user, "-d", dbname]
    env = dict(os.environ)
    env["PGCLIENTENCODING"] = "UTF8"
    if password:
        env["PGPASSWORD"] = password

    use_remote = args.remote or (bool(remote.get("REMOTE_HOST")) and not args.local)
    if use_remote:
        if not remote.get("REMOTE_HOST"):
            raise SystemExit("--remote given but secrets/remote.env has no REMOTE_HOST")
        key = SECRETS / "id_alienmind"
        backend: LocalBackend | RemoteBackend = RemoteBackend(
            remote["REMOTE_HOST"], remote.get("REMOTE_USER", "root"),
            key if key.is_file() else None,
            conn, {"PGPASSWORD": password} if password else {})
    else:
        backend = LocalBackend(args.psql or find_psql(), conn, env)

    print(f"target: {user}@{host}:{port}/{dbname}, schema qdgc_test, via {backend.describe()}")
    backend.prepare()

    steps: list[pathlib.Path] = [ROOT / "test" / "sql" / "00_install.sql"]
    for ext in ("qdgc", "qdgc_postgis"):
        steps += sorted((ROOT / "sql" / "install" / ext).glob("*.sql"))
    tests = [p for p in sorted((ROOT / "test" / "sql").glob("*.sql"))
             if p.name != "00_install.sql"]

    print(f"preparing schema and loading {len(steps) - 1} install source(s)")
    for path in steps:
        rel = path.relative_to(ROOT).as_posix()
        res = backend.psql_file(rel)
        if res.returncode != 0:
            print((res.stdout or "") + (res.stderr or ""))
            raise SystemExit(f"setup failed at {rel}")

    failures = 0
    for path in tests:
        rel = path.relative_to(ROOT).as_posix()
        res = backend.psql_file(rel)
        out = (res.stdout or "") + (res.stderr or "")
        if res.returncode != 0:
            failures += 1
            print(f"FAIL  {path.name}")
            for line in out.splitlines():
                if line.strip():
                    print(f"        {line.rstrip()}")
            continue
        print(f"ok    {path.name}")
        # psql prefixes notices with "psql:<file>:<line>: NOTICE:  ".
        for line in out.splitlines():
            _, sep, message = line.partition("NOTICE:")
            if sep:
                print(f"        {message.strip()}")

    print()
    if failures:
        print(f"RESULT: {failures} of {len(tests)} test file(s) FAILED")
        return 1
    print(f"RESULT: all {len(tests)} test file(s) passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
