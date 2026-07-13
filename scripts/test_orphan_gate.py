#!/usr/bin/env python3
"""Unit tests for orphan definition CI gate (no pytest required)."""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
PROJECT_ROOT = _SCRIPTS.parent
sys.path.insert(0, str(_SCRIPTS))

from audit_orphan_shader_defs import (  # noqa: E402
    BASELINE_JSON,
    evaluate_ci_gate,
    classify_definition,
    DEFINITIONS_DIR,
)


def test_baseline_empty_passes_when_no_likely_broken():
    report = {
        "entries": [
            {
                "id": "ok-shader",
                "def_path": "shader_definitions/test/ok.json",
                "classification": "local",
            }
        ]
    }
    ok, errors = evaluate_ci_gate(report, "origin/main")
    assert ok, errors


def test_new_likely_broken_fails_against_baseline():
    report = {
        "entries": [
            {
                "id": "ghost-shader",
                "def_path": "shader_definitions/test/ghost.json",
                "classification": "likely-broken",
                "expected_wgsl": "ghost.wgsl",
            }
        ]
    }
    ok, errors = evaluate_ci_gate(report, "origin/main")
    assert not ok
    assert any("ghost-shader" in e for e in errors)


def test_baseline_accepts_preexisting_orphan():
    with tempfile.TemporaryDirectory() as tmp:
        baseline_path = Path(tmp) / "orphan_baseline.json"
        baseline_path.write_text(
            json.dumps({"ids": ["legacy-orphan"]}),
            encoding="utf-8",
        )
        original = BASELINE_JSON
        try:
            import audit_orphan_shader_defs as mod
            mod.BASELINE_JSON = baseline_path
            report = {
                "entries": [
                    {
                        "id": "legacy-orphan",
                        "def_path": "shader_definitions/old/legacy.json",
                        "classification": "likely-broken",
                        "expected_wgsl": "legacy.wgsl",
                    }
                ]
            }
            ok, errors = evaluate_ci_gate(report, "origin/main")
            assert ok, errors
        finally:
            mod.BASELINE_JSON = original


def main() -> int:
    tests = [
        test_baseline_empty_passes_when_no_likely_broken,
        test_new_likely_broken_fails_against_baseline,
        test_baseline_accepts_preexisting_orphan,
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
