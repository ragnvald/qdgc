"""Minimal psql executor shared by the qdgc tooling.

Reads connection settings from ../secrets/postgis.env and, when
../secrets/remote.env supplies REMOTE_HOST/REMOTE_USER, runs psql on that host
over ssh instead of locally. SQL is always piped over stdin, so nothing has to
be quoted for a remote shell.
"""
from __future__ import annotations

import glob
import os
import pathlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
SECRETS = ROOT.parent / "secrets"


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


def _find_psql() -> str:
    found = shutil.which("psql")
    if found:
        return found
    for base in sorted(glob.glob(r"C:\Program Files\PostgreSQL\*\bin\psql.exe"), reverse=True):
        return base
    raise SystemExit("psql not found on PATH")


class Executor:
    def __init__(self) -> None:
        pg = read_env_file(SECRETS / "postgis.env")
        remote = read_env_file(SECRETS / "remote.env")
        if not pg.get("PGDATABASE"):
            raise SystemExit("secrets/postgis.env is missing or has no PGDATABASE")

        self.dbname = pg["PGDATABASE"]
        self.user = pg.get("PGUSER", "postgres")
        self.host = pg.get("PGHOST", "127.0.0.1")
        self.port = pg.get("PGPORT", "5432")
        self.password = pg.get("PGPASSWORD", "")
        self.remote_host = remote.get("REMOTE_HOST")
        self.remote_user = remote.get("REMOTE_USER")
        key = SECRETS / "id_alienmind"
        self.key = key if key.is_file() else None

    def describe(self) -> str:
        where = f"ssh {self.remote_user}@{self.remote_host}" if self.remote_host else "local"
        return f"{self.user}@{self.host}:{self.port}/{self.dbname} via {where}"

    def run(self, sql: str, *, args: list[str] | None = None) -> str:
        """Execute SQL piped over stdin and return psql's combined output."""
        flags = ["-v", "ON_ERROR_STOP=1", "--no-psqlrc", "-w",
                 "-h", self.host, "-p", self.port, "-U", self.user, "-d", self.dbname]
        flags += args or []

        if self.remote_host:
            ssh = ["ssh"]
            if self.key:
                ssh += ["-i", str(self.key)]
            ssh += ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
                    f"{self.remote_user}@{self.remote_host}"]
            # PGPASSWORD is exported inside the remote command, never written to
            # disk or to shell history on that host.
            remote_cmd = f"PGPASSWORD='{self.password}' psql " + " ".join(flags) + " -f -"
            proc = subprocess.run(ssh + [remote_cmd], input=sql,
                                  capture_output=True, text=True)
        else:
            env = dict(os.environ)
            env["PGCLIENTENCODING"] = "UTF8"
            if self.password:
                env["PGPASSWORD"] = self.password
            proc = subprocess.run([_find_psql()] + flags + ["-f", "-"], input=sql,
                                  env=env, capture_output=True, text=True)

        out = (proc.stdout or "") + (proc.stderr or "")
        if proc.returncode != 0:
            raise RuntimeError(f"psql failed:\n{out.strip()}")
        return out

    def rows(self, sql: str) -> list[str]:
        """Execute SQL and return the unaligned, tuples-only result lines."""
        out = self.run(sql, args=["-tA"])
        return [line for line in out.splitlines() if line.strip()]

    def scalar(self, sql: str) -> str:
        rows = self.rows(sql)
        return rows[0] if rows else ""
