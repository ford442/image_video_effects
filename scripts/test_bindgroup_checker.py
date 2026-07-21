#!/usr/bin/env python3
"""Unit tests for bindgroup_checker optional binding 13 and >13 rejection."""

import sys
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPTS))

from bindgroup_checker import (  # noqa: E402
    check_reserved_extrabuffer_writes,
    parse_shader,
)

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


def test_ungated_reserved_extrabuffer_write_flagged():
    result = parse_shader(str(FIXTURES / "bindgroup_extrabuf_ungated.wgsl"))
    assert result["status"] == "incompatible"
    assert any("reserved extraBuffer[0]" in e for e in result["errors"])
    assert len(result["reserved_extrabuffer_writes"]) == 1
    assert result["reserved_extrabuffer_writes"][0]["index"] == 0


def test_gated_reserved_extrabuffer_write_ok():
    result = parse_shader(str(FIXTURES / "bindgroup_extrabuf_gated.wgsl"))
    assert result["status"] == "compatible"
    assert result["reserved_extrabuffer_writes"] == []


def test_gate_variable_reserved_extrabuffer_write_ok():
    result = parse_shader(str(FIXTURES / "bindgroup_extrabuf_gatevar.wgsl"))
    assert result["status"] == "compatible"
    assert result["reserved_extrabuffer_writes"] == []


def test_reserved_extrabuffer_check_comment_stripped():
    src = "// extraBuffer[0] = 1.0;\n/* extraBuffer[4] = 2.0; */\n"
    assert check_reserved_extrabuffer_writes(src) == []


def test_reserved_extrabuffer_check_ignores_high_indices():
    src = "extraBuffer[5] = 1.0;\nextraBuffer[132] = 2.0;\n"
    assert check_reserved_extrabuffer_writes(src) == []


def test_reserved_extrabuffer_check_ignores_equality():
    src = "let a = extraBuffer[0] == 1.0;\n"
    assert check_reserved_extrabuffer_writes(src) == []


def test_reserved_extrabuffer_check_braceless_gate():
    src = (
        "fn main(@builtin(global_invocation_id) gid: vec3<u32>) {\n"
        "  if (gid.x == 0u && gid.y == 0u) extraBuffer[2] = 1.0;\n"
        "}\n"
    )
    assert check_reserved_extrabuffer_writes(src) == []


if __name__ == "__main__":
    test_core_bindings_only_compatible()
    test_valid_binding_13_compatible()
    test_wrong_binding_13_type_incompatible()
    test_binding_14_incompatible()
    test_ungated_reserved_extrabuffer_write_flagged()
    test_gated_reserved_extrabuffer_write_ok()
    test_gate_variable_reserved_extrabuffer_write_ok()
    test_reserved_extrabuffer_check_comment_stripped()
    test_reserved_extrabuffer_check_ignores_high_indices()
    test_reserved_extrabuffer_check_ignores_equality()
    test_reserved_extrabuffer_check_braceless_gate()
    print("test_bindgroup_checker: all passed")
