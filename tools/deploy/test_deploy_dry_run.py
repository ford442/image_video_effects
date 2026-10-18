#!/usr/bin/env python3
"""Unit tests for ``--dry-run`` in deploy.py / deploy_app_only.py (pytest, no network)."""

import hashlib
import json
import os
import socket
import subprocess
import sys
from pathlib import Path

import pytest

_DEPLOY_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(_DEPLOY_DIR))

import deploy  # noqa: E402
import deploy_app_only  # noqa: E402

INDEX_HTML = '<html><script src="/static/js/main.abc123.js"></script></html>'
MAIN_JS = "console.log('app');\n"
CHANGED_JS = "chunk v2\n"
CSS = "body{}\n"


def md5(text: str) -> str:
    return hashlib.md5(text.encode()).hexdigest()


def write(root: Path, rel: str, text: str) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


@pytest.fixture
def workdir(tmp_path, monkeypatch):
    """tmp cwd containing a tiny build/ and a manifest for both scripts."""
    build = tmp_path / "build"
    write(build, "index.html", INDEX_HTML)
    write(build, "asset-manifest.json", "{}")
    write(build, ".htaccess", "# rewrite\n")
    write(build, "static/js/main.abc123.js", MAIN_JS)  # tracked, unchanged
    write(build, "static/js/chunk.js", CHANGED_JS)  # tracked, hash differs
    write(build, "static/css/main.abc123.css", CSS)  # untracked -> new
    write(build, "shaders/a.wgsl", "// shader\n")  # deploy.py uploads, app-only skips

    manifest = {
        "index.html": {"hash": md5(INDEX_HTML), "size": len(INDEX_HTML)},  # ALWAYS beats a match
        "static/js/main.abc123.js": {"hash": md5(MAIN_JS), "size": len(MAIN_JS)},
        "static/js/chunk.js": {"hash": "0" * 32, "size": 1},
        "static/js/main.old999.js": {"hash": "1" * 32, "size": 5},  # gone from build/
    }
    manifest_text = json.dumps(manifest, indent=2)
    (tmp_path / ".deploy_manifest.json").write_text(manifest_text)
    (tmp_path / ".deploy_app_manifest.json").write_text(manifest_text)
    monkeypatch.chdir(tmp_path)
    return tmp_path


def snapshot(root: Path) -> dict:
    return {
        str(p.relative_to(root)): (p.stat().st_size, p.stat().st_mtime_ns, p.read_bytes())
        for p in sorted(root.rglob("*"))
        if p.is_file()
    }


def by_path(plan):
    return {e.path: e for e in plan.uploads}


def test_deploy_plan_reasons_sizes_and_deletions(workdir):
    plan = deploy.compute_plan("build", deploy.load_manifest())
    up = by_path(plan)

    assert {p: e.reason for p, e in up.items()} == {
        "index.html": "always",
        ".htaccess": "always",
        "asset-manifest.json": "always",
        "static/js/chunk.js": "hash-changed",
        "static/css/main.abc123.css": "new",
        "shaders/a.wgsl": "new",
    }
    assert up["static/js/chunk.js"].size == len(CHANGED_JS)
    assert plan.unchanged == ["static/js/main.abc123.js"]
    assert plan.deletions == ["static/js/main.old999.js"]
    assert plan.upload_bytes == sum(e.size for e in plan.uploads)
    assert plan.remote_root == deploy.REMOTE_DIRECTORY


def test_deploy_fresh_clears_manifest_so_nothing_is_deleted(workdir):
    plan = deploy.compute_plan("build", deploy.load_manifest(), fresh=True)
    assert {e.reason for e in plan.uploads} == {"always", "new"}
    assert len(plan.uploads) == 7 and plan.unchanged == []
    assert plan.deletions == []  # mirrors real --fresh: manifest is gone before clean_remote()
    assert any("--fresh" in n for n in plan.notes)


def test_deploy_app_only_skips_shaders_and_never_deletes(workdir):
    plan = deploy_app_only.compute_plan("build", deploy_app_only.load_manifest())
    up = by_path(plan)
    assert "shaders/a.wgsl" not in up
    assert plan.skipped_dirs == ["shaders"]
    assert up["static/js/chunk.js"].reason == "hash-changed"
    assert up["static/css/main.abc123.css"].reason == "new"
    assert up["index.html"].reason == "always"
    assert plan.unchanged == ["static/js/main.abc123.js"]
    assert plan.deletes_supported is False and plan.deletions == []
    assert any("no longer in build/" in n for n in plan.notes)

    forced = deploy_app_only.compute_plan("build", deploy_app_only.load_manifest(), force=True)
    assert forced.unchanged == [] and len(forced.uploads) == 6


@pytest.mark.parametrize("module", [deploy, deploy_app_only])
def test_dry_run_touches_nothing_and_opens_no_connection(workdir, module, monkeypatch, capsys):
    def boom(*_a, **_k):
        raise AssertionError("dry run must not open a network connection or resolve credentials")

    monkeypatch.setattr(socket.socket, "connect", boom)
    monkeypatch.setattr(socket, "create_connection", boom)
    monkeypatch.setattr(socket, "getaddrinfo", boom)
    monkeypatch.setattr(module, "load_credentials", boom)
    monkeypatch.setattr(module, "open_sftp", boom)
    monkeypatch.setattr("builtins.input", boom)
    before = snapshot(workdir)

    args = module.parse_args(["--dry-run", "--fresh"])
    assert args.dry_run and args.fresh and not args.force
    assert module.run_dry_run(fresh=args.fresh, force=args.force) == 0

    out = capsys.readouterr().out
    assert "DRY RUN" in out and module.REMOTE_DIRECTORY in out
    assert "Files to upload" in out and "Totals:" in out
    assert snapshot(workdir) == before  # manifest rewritten? files created? mtime bumped?


def test_parse_args_keeps_force_and_fresh():
    for module in (deploy, deploy_app_only):
        assert vars(module.parse_args([])) == {"force": False, "fresh": False, "dry_run": False}
        assert module.parse_args(["--force"]).force
        assert module.parse_args(["--fresh"]).fresh
        with pytest.raises(SystemExit):
            module.parse_args(["--dry"])  # no silent abbreviations


@pytest.mark.parametrize("script", ["deploy.py", "deploy_app_only.py"])
def test_cli_exit_codes(workdir, script, tmp_path_factory):
    env = {
        "PATH": os.environ.get("PATH", ""),
        "HOME": str(tmp_path_factory.mktemp("home")),  # no ~/.config or ~/.ssh credentials
    }
    cmd = [sys.executable, str(_DEPLOY_DIR / script), "--dry-run"]

    ok = subprocess.run(cmd, cwd=workdir, env=env, capture_output=True, text=True,
                        stdin=subprocess.DEVNULL, timeout=60)
    assert ok.returncode == 0, ok.stdout + ok.stderr
    assert "Files to upload" in ok.stdout and "credentials" not in ok.stdout.lower()

    empty = tmp_path_factory.mktemp("nobuild")
    bad = subprocess.run(cmd, cwd=empty, env=env, capture_output=True, text=True,
                         stdin=subprocess.DEVNULL, timeout=60)
    assert bad.returncode != 0
    assert "'build' not found" in bad.stdout and "npm run build" in bad.stdout
