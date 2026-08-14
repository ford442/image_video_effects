#!/usr/bin/env python3
"""Shared DreamHost/SFTP credentials for deploy and shader-sync scripts.

Never hardcode passwords in the repo. Load them from, in order:
  1. already-set environment variables
  2. repo-root `.env.deploy` (gitignored)
  3. `~/.config/pixelocity/deploy.env`
  4. a local SSH private key (DEPLOY_KEY or ~/.ssh/id_ed25519 / id_rsa)
  5. an interactive password prompt, only when stdin is a TTY

Accepted env keys (first match wins):
  host:     DEPLOY_HOST, FTP_HOST
  port:     DEPLOY_PORT, FTP_PORT
  user:     DEPLOY_USER, FTP_USER
  password: DEPLOY_PASS, FTP_PASS, SHADER_SYNC_PASSWORD
  key:      DEPLOY_KEY, FTP_KEY
"""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Optional

_SCRIPTS = Path(__file__).resolve().parent
REPO_ROOT = _SCRIPTS.parent

DEFAULT_HOST = "1ink.us"
DEFAULT_PORT = 22
DEFAULT_USER = "ford442"
DEFAULT_KEY_CANDIDATES = (
    Path.home() / ".ssh" / "id_ed25519",
    Path.home() / ".ssh" / "id_rsa",
)

HOST_KEYS = ("DEPLOY_HOST", "FTP_HOST")
PORT_KEYS = ("DEPLOY_PORT", "FTP_PORT")
USER_KEYS = ("DEPLOY_USER", "FTP_USER")
PASS_KEYS = ("DEPLOY_PASS", "FTP_PASS", "SHADER_SYNC_PASSWORD")
KEY_KEYS = ("DEPLOY_KEY", "FTP_KEY")


@dataclass
class DeployCredentials:
    host: str = DEFAULT_HOST
    port: int = DEFAULT_PORT
    username: str = DEFAULT_USER
    password: str = ""
    key_path: Optional[str] = None
    source: str = "defaults"


def env_file_candidates() -> list[Path]:
    return [
        REPO_ROOT / ".env.deploy",
        Path.home() / ".config" / "pixelocity" / "deploy.env",
    ]


def parse_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        if line.lower().startswith("export "):
            line = line[7:].lstrip()
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        if (value.startswith('"') and value.endswith('"')) or (
            value.startswith("'") and value.endswith("'")
        ):
            value = value[1:-1]
        if key:
            values[key] = value
    return values


def load_env_files(paths: Optional[Iterable[Path]] = None) -> Optional[Path]:
    """Populate os.environ from the first existing env file. Existing vars win."""
    loaded = None
    for path in paths or env_file_candidates():
        if not path.is_file():
            continue
        for key, value in parse_env_file(path).items():
            os.environ.setdefault(key, value)
        if loaded is None:
            loaded = path
    return loaded


def _first_env(keys: Iterable[str], default: str = "") -> str:
    for key in keys:
        value = os.environ.get(key)
        if value:
            return value
    return default


def default_key_path() -> Optional[str]:
    explicit = _first_env(KEY_KEYS)
    if explicit:
        return str(Path(explicit).expanduser())
    for candidate in DEFAULT_KEY_CANDIDATES:
        if candidate.is_file():
            return str(candidate)
    return None


def load_credentials(
    *, prompt: bool = True, env_paths: Optional[Iterable[Path]] = None
) -> DeployCredentials:
    loaded_from = load_env_files(env_paths)
    source = str(loaded_from) if loaded_from else "environment/defaults"
    creds = DeployCredentials(
        host=_first_env(HOST_KEYS, DEFAULT_HOST),
        port=int(_first_env(PORT_KEYS, str(DEFAULT_PORT))),
        username=_first_env(USER_KEYS, DEFAULT_USER),
        password=_first_env(PASS_KEYS),
        key_path=default_key_path(),
        source=source,
    )
    if creds.password or creds.key_path:
        return creds
    if prompt and sys.stdin.isatty():
        import getpass

        creds.password = getpass.getpass(
            f"Password for {creds.username}@{creds.host}: "
        )
        creds.source = "prompt"
        return creds
    raise SystemExit(
        "No deploy credentials found. Copy .env.deploy.example to .env.deploy "
        "and set DEPLOY_USER / DEPLOY_PASS (or add an SSH key via DEPLOY_KEY)."
    )


def open_sftp(creds: DeployCredentials):
    """Return (ssh_client, sftp_client) using key and/or password."""
    try:
        import paramiko
    except ImportError as exc:
        raise SystemExit("paramiko is required. Install it with: pip install paramiko") from exc

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    kwargs = {
        "hostname": creds.host,
        "port": creds.port,
        "username": creds.username,
        "allow_agent": True,
        "look_for_keys": bool(creds.key_path),
        "timeout": 20,
        "auth_timeout": 20,
    }
    if creds.key_path:
        kwargs["key_filename"] = creds.key_path
    if creds.password:
        kwargs["password"] = creds.password
    try:
        client.connect(**kwargs)
    except Exception:
        client.close()
        raise
    return client, client.open_sftp()
