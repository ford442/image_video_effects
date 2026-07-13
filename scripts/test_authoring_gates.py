#!/usr/bin/env python3
"""Unit tests for forward-only orphan definition auditor (no pytest required)."""

import sys
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPTS))

from audit_orphan_shader_defs import (  # noqa: E402
    ALLOWLIST_IDS,
    enforceable_failures,
    is_allowlisted,
)
from bindgroup_checker import (  # noqa: E402
    check_workgroup_size_convention,
    fix_literal_two_arg_workgroup_size,
)
from wgsl_precommit_gate import run_gate  # noqa: E402

FIXTURES = _SCRIPTS / "fixtures"


def test_workgroup_two_arg_flagged():
    content = (FIXTURES / "workgroup_two_arg.wgsl").read_text(encoding="utf-8")
    issues = check_workgroup_size_convention(content)
    assert len(issues) == 1
    assert issues[0]["arg_count"] == 2


def test_workgroup_three_arg_passes():
    content = (FIXTURES / "workgroup_three_arg_ok.wgsl").read_text(encoding="utf-8")
    assert check_workgroup_size_convention(content) == []


def test_gate_fails_on_two_arg_changed_file():
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "bad.wgsl"
        path.write_text((FIXTURES / "workgroup_two_arg.wgsl").read_text(encoding="utf-8"))
        report = run_gate([path], skip_naga=True)
        assert report["failed"] == 1
        assert report["workgroup_failures"] == 1


def test_gate_passes_three_arg_file():
    repo = _SCRIPTS.parent
    path = repo / "public" / "shaders" / "_template_canonical_compute.wgsl"
    report = run_gate([path], skip_naga=True)
    assert report["workgroup_failures"] == 0
    assert report["failed"] == 0


def test_autofix_literal_two_arg():
    raw = (FIXTURES / "workgroup_two_arg.wgsl").read_text(encoding="utf-8")
    fixed, n = fix_literal_two_arg_workgroup_size(raw)
    assert n == 1
    assert "@workgroup_size(8, 8, 1)" in fixed
    assert check_workgroup_size_convention(fixed) == []


def test_enforceable_likely_broken_changed_only():
    project = _SCRIPTS.parent
    row = {
        "id": "missing-shader",
        "def_path": "shader_definitions/cat/missing-shader.json",
        "expected_wgsl": "missing-shader.wgsl",
        "classification": "likely-broken",
    }
    changed = {(project / row["def_path"]).resolve()}
    failures = enforceable_failures([row], changed)
    assert len(failures) == 1


def test_enforceable_unchanged_likely_broken_not_enforced():
    row = {
        "id": "orphan-old",
        "def_path": "shader_definitions/cat/orphan-old.json",
        "expected_wgsl": "orphan-old.wgsl",
        "classification": "likely-broken",
    }
    failures = enforceable_failures([row], set())
    assert failures == []


def test_storage_only_and_allowlisted_pass():
    project = _SCRIPTS.parent
    row = {
        "id": "remote-only",
        "def_path": "shader_definitions/cat/remote-only.json",
        "expected_wgsl": "remote-only.wgsl",
        "classification": "storage-only",
    }
    changed = {(project / row["def_path"]).resolve()}
    assert enforceable_failures([row], changed) == []

    allow_id = next(iter(ALLOWLIST_IDS))
    row2 = {
        "id": allow_id,
        "def_path": f"shader_definitions/cat/{allow_id}.json",
        "expected_wgsl": f"{allow_id}.wgsl",
        "classification": "allowlisted",
    }
    assert is_allowlisted(allow_id)
    changed2 = {(project / row2["def_path"]).resolve()}
    assert enforceable_failures([row2], changed2) == []


def test_local_definition_passes():
    row = {
        "id": "good",
        "def_path": "shader_definitions/cat/good.json",
        "expected_wgsl": "good.wgsl",
        "classification": "local",
    }
    project = _SCRIPTS.parent
    changed = {(project / row["def_path"]).resolve()}
    assert enforceable_failures([row], changed) == []


def test_parse_error_classification():
    project = _SCRIPTS.parent
    row = {
        "id": "bad-json",
        "def_path": "shader_definitions/cat/bad.json",
        "expected_wgsl": "",
        "classification": "parse-error",
        "error": "Expecting value",
    }
    changed = {(project / row["def_path"]).resolve()}
    failures = enforceable_failures([row], changed)
    assert len(failures) == 1


def main() -> int:
    tests = [
        test_workgroup_two_arg_flagged,
        test_workgroup_three_arg_passes,
        test_gate_fails_on_two_arg_changed_file,
        test_gate_passes_three_arg_file,
        test_autofix_literal_two_arg,
        test_enforceable_likely_broken_changed_only,
        test_enforceable_unchanged_likely_broken_not_enforced,
        test_storage_only_and_allowlisted_pass,
        test_local_definition_passes,
        test_parse_error_classification,
    ]
    failed = 0
    for t in tests:
        try:
            t()
            print(f"OK  {t.__name__}")
        except AssertionError as e:
            failed += 1
            print(f"FAIL {t.__name__}: {e}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
