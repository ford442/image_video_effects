#!/usr/bin/env python3
"""Unit tests for deploy credential loading (no network, no pytest required)."""

import os
import sys
import tempfile
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPTS))

from deploy_credentials import (  # noqa: E402
    parse_env_file,
    load_env_files,
    load_credentials,
    _first_env,
)


def test_parse_env_file_handles_export_and_quotes(tmp_path: Path):
    path = tmp_path / "deploy.env"
    path.write_text(
        "# comment\n"
        "DEPLOY_USER=ford442\n"
        "export DEPLOY_PASS='secret value'\n"
        'FTP_HOST="1ink.us"\n'
        "EMPTY=\n",
        encoding="utf-8",
    )
    values = parse_env_file(path)
    assert values["DEPLOY_USER"] == "ford442"
    assert values["DEPLOY_PASS"] == "secret value"
    assert values["FTP_HOST"] == "1ink.us"
    assert values["EMPTY"] == ""


def test_load_env_files_does_not_override_existing(tmp_path: Path):
    path = tmp_path / ".env.deploy"
    path.write_text("DEPLOY_USER=from-file\nDEPLOY_PASS=from-file\n", encoding="utf-8")
    os.environ["DEPLOY_USER"] = "already-set"
    os.environ.pop("DEPLOY_PASS", None)
    loaded = load_env_files([path])
    assert loaded == path
    assert os.environ["DEPLOY_USER"] == "already-set"
    assert os.environ["DEPLOY_PASS"] == "from-file"


def test_first_env_prefers_deploy_over_ftp_alias():
    os.environ["DEPLOY_PASS"] = "deploy-secret"
    os.environ["FTP_PASS"] = "ftp-secret"
    assert _first_env(("DEPLOY_PASS", "FTP_PASS")) == "deploy-secret"


def test_load_credentials_from_ftp_aliases(tmp_path: Path):
    for key in (
        "DEPLOY_HOST",
        "DEPLOY_PORT",
        "DEPLOY_USER",
        "DEPLOY_PASS",
        "FTP_HOST",
        "FTP_PORT",
        "FTP_USER",
        "FTP_PASS",
        "SHADER_SYNC_PASSWORD",
        "DEPLOY_KEY",
        "FTP_KEY",
    ):
        os.environ.pop(key, None)
    path = tmp_path / "ftp.env"
    path.write_text(
        "FTP_HOST=example.test\nFTP_PORT=2222\nFTP_USER=ftpbridge\nFTP_PASS=ftp-secret\n",
        encoding="utf-8",
    )
    creds = load_credentials(prompt=False, env_paths=[path])
    assert creds.host == "example.test"
    assert creds.port == 2222
    assert creds.username == "ftpbridge"
    assert creds.password == "ftp-secret"


def main():
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        test_parse_env_file_handles_export_and_quotes(tmp_path)
    saved = {k: os.environ.get(k) for k in list(os.environ) if k.startswith(("DEPLOY_", "FTP_", "SHADER_SYNC_"))}
    try:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            test_load_env_files_does_not_override_existing(tmp_path)
        test_first_env_prefers_deploy_over_ftp_alias()
        with tempfile.TemporaryDirectory() as tmp:
            test_load_credentials_from_ftp_aliases(Path(tmp))
    finally:
        for key in list(os.environ):
            if key.startswith(("DEPLOY_", "FTP_", "SHADER_SYNC_")):
                os.environ.pop(key, None)
        for key, value in saved.items():
            if value is not None:
                os.environ[key] = value
    print("test_deploy_credentials: PASS")


if __name__ == "__main__":
    main()
