#!/usr/bin/env python3
"""Unit tests for workgroup-size convention checks (no pytest required)."""

import sys
import tempfile
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPTS))

from bindgroup_checker import (  # noqa: E402
    check_workgroup_size_convention,
    fix_literal_two_arg_workgroup_size,
    strip_wgsl_comments,
)

FIXTURES = _SCRIPTS / "fixtures"


def test_strip_comments_ignores_commented_attribute():
    src = """
// @workgroup_size(8, 8)
@compute @workgroup_size(16, 16, 1)
fn main() {}
"""
    stripped = strip_wgsl_comments(src)
    assert "@workgroup_size(8, 8)" not in stripped
    issues = check_workgroup_size_convention(src)
    assert issues == []


def test_two_arg_literal_detected():
    content = (FIXTURES / "workgroup_two_arg.wgsl").read_text(encoding="utf-8")
    issues = check_workgroup_size_convention(content)
    assert len(issues) == 1
    assert issues[0]["arg_count"] == 2


def test_override_one_arg_detected():
    content = (FIXTURES / "workgroup_override_one_arg.wgsl").read_text(encoding="utf-8")
    issues = check_workgroup_size_convention(content)
    assert len(issues) == 1
    assert issues[0]["arg_count"] == 1
    assert "block_width" in issues[0]["args"]


def test_three_arg_ok():
    content = (FIXTURES / "workgroup_three_arg_ok.wgsl").read_text(encoding="utf-8")
    assert check_workgroup_size_convention(content) == []


def test_autofix_literal_two_arg_only():
    raw = (FIXTURES / "workgroup_two_arg.wgsl").read_text(encoding="utf-8")
    fixed, n = fix_literal_two_arg_workgroup_size(raw)
    assert n == 1
    assert "@workgroup_size(8, 8, 1)" in fixed
    assert check_workgroup_size_convention(fixed) == []

    override = (FIXTURES / "workgroup_override_one_arg.wgsl").read_text(encoding="utf-8")
    unchanged, n2 = fix_literal_two_arg_workgroup_size(override)
    assert n2 == 0
    assert unchanged == override


def test_gen_showcase_nebula_core_if_present():
    repo = _SCRIPTS.parent
    target = repo / "public" / "shaders" / "gen-showcase-nebula-core.wgsl"
    if not target.exists():
        return
    issues = check_workgroup_size_convention(target.read_text(encoding="utf-8"))
    assert any(i["arg_count"] == 2 for i in issues)


def main() -> int:
    tests = [
        test_strip_comments_ignores_commented_attribute,
        test_two_arg_literal_detected,
        test_override_one_arg_detected,
        test_three_arg_ok,
        test_autofix_literal_two_arg_only,
        test_gen_showcase_nebula_core_if_present,
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
