#!/usr/bin/env python3
"""Unit tests for wgsl_workgroup_detector (no pytest required)."""

import sys
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPTS))

from wgsl_workgroup_detector import (  # noqa: E402
    audit_file,
    check_dispatch_limits,
    strip_wgsl_comments,
)

FIXTURES = _SCRIPTS / "fixtures"


def test_comment_strip_prevents_false_positive():
    content = (FIXTURES / "workgroup_comment_false_positive.wgsl").read_text(encoding="utf-8")
    stripped = strip_wgsl_comments(content)
    assert "@workgroup_size(8, 8)" not in stripped
    row = audit_file(FIXTURES / "workgroup_comment_false_positive.wgsl")
    assert row["convention_warnings"] == []


def test_two_arg_convention_warning():
    row = audit_file(FIXTURES / "workgroup_two_arg.wgsl")
    assert not row["skipped"]
    assert any(w["kind"] == "two-arg-convention" for w in row["convention_warnings"])


def test_over_256_limit_error():
    row = audit_file(FIXTURES / "workgroup_over_256.wgsl")
    assert not row["skipped"]
    assert len(row["limit_errors"]) >= 1
    assert any("272" in e["message"] for e in row["limit_errors"])


def test_dispatch_limits_math():
    assert check_dispatch_limits(16, 16, 1) == []
    assert any("272" in x for x in check_dispatch_limits(17, 16, 1))


def main() -> int:
    tests = [
        test_comment_strip_prevents_false_positive,
        test_two_arg_convention_warning,
        test_over_256_limit_error,
        test_dispatch_limits_math,
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
