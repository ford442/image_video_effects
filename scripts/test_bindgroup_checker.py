#!/usr/bin/env python3
"""Unit tests for bindgroup_checker optional binding 13 and >13 rejection."""

import sys
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPTS))

from bindgroup_checker import parse_shader  # noqa: E402

FIXTURES = _SCRIPTS / "fixtures"


def test_core_bindings_only_compatible():
    result = parse_shader(str(FIXTURES / "bindgroup_core_only.wgsl"))
    assert result["status"] == "compatible"
    assert not result["has_binding_13_plus"]


def test_valid_binding_13_compatible():
    result = parse_shader(str(FIXTURES / "bindgroup_history_ok.wgsl"))
    assert result["status"] == "compatible"
    assert result["has_binding_13_plus"]


def test_wrong_binding_13_type_incompatible():
    result = parse_shader(str(FIXTURES / "bindgroup_history_bad.wgsl"))
    assert result["status"] == "incompatible"
    assert any("Binding 13" in e for e in result["errors"])


def test_binding_14_incompatible():
    result = parse_shader(str(FIXTURES / "bindgroup_binding_14.wgsl"))
    assert result["status"] == "incompatible"
    assert any("beyond max index 13" in e for e in result["errors"])


if __name__ == "__main__":
    test_core_bindings_only_compatible()
    test_valid_binding_13_compatible()
    test_wrong_binding_13_type_incompatible()
    test_binding_14_incompatible()
    print("test_bindgroup_checker: all passed")
