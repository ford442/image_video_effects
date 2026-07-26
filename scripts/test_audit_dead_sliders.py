#!/usr/bin/env python3
"""Unit tests for audit_dead_sliders (no pytest required; pytest-compatible)."""

import json
import sys
import tempfile
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPTS))

from audit_dead_sliders import (  # noqa: E402
    extract_params,
    fields_read,
    scan_definition,
)


def test_extract_params_explicit_mapping():
    meta = {"params": [
        {"id": "a", "name": "A", "default": 0.5, "mapping": "zoom_params.x"},
        {"id": "b", "name": "B", "default": 0.5, "mapping": "zoom_params.w"},
    ]}
    ps = extract_params(meta)
    assert [(p["id"], p["field"]) for p in ps] == [("a", "x"), ("b", "w")]


def test_extract_params_index_order_default():
    meta = {"params": [{"id": f"p{i}", "name": f"P{i}", "default": 0.5} for i in range(4)]}
    ps = extract_params(meta)
    assert [p["field"] for p in ps] == ["x", "y", "z", "w"]


def test_extract_params_controls_schemas():
    meta = {"controls": [
        {"name": "C1", "type": "slider", "default": 1.0, "uniform": "zoom_params.x"},
        {"id": "c2", "name": "C2", "type": "range", "default": 0.2,
         "uniformMapping": {"struct": "zoom_params", "field": "y"}},
        {"name": "skip", "type": "toggle", "uniform": "zoom_params.z"},
    ]}
    ps = extract_params(meta)
    assert [(p["name"], p["field"]) for p in ps] == [("C1", "x"), ("C2", "y")]


def test_fields_read_direct_alias_and_index():
    wgsl = """
fn f() {
    let a = u.zoom_params.x;
    let b = u.zoom_params[2];
    let p = u.zoom_params;
    let c = p.w;
}
"""
    assert fields_read(wgsl) == {"x", "z", "w"}


def test_fields_read_ignores_comments():
    assert fields_read("// let a = u.zoom_params.x;\n") == set()


def test_scan_definition_reports_dead(tmp_path):
    # scan_definition works on real repo paths; emulate via monkeypatched dirs
    import audit_dead_sliders as ads

    d = tmp_path / "defs" / "generative"
    d.mkdir(parents=True)
    s = tmp_path / "shaders"
    s.mkdir()
    (d / "demo.json").write_text(json.dumps({
        "id": "demo", "url": "shaders/demo.wgsl",
        "params": [
            {"id": "live", "name": "Live", "default": 0.5, "mapping": "zoom_params.x"},
            {"id": "dead", "name": "Dead", "default": 0.5, "mapping": "zoom_params.y"},
        ],
    }))
    (s / "demo.wgsl").write_text("fn f() { let a = u.zoom_params.x; }\n")

    old_defs, old_shaders = ads.DEFINITIONS_DIR, ads.SHADERS_DIR
    try:
        ads.DEFINITIONS_DIR, ads.SHADERS_DIR = d.parent, s
        r = ads.scan_definition(d / "demo.json")
    finally:
        ads.DEFINITIONS_DIR, ads.SHADERS_DIR = old_defs, old_shaders

    assert r is not None and not r.get("error")
    assert [p["id"] for p in r["dead"]] == ["dead"]


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for fn in fns:
        try:
            if "tmp_path" in fn.__code__.co_varnames:
                with tempfile.TemporaryDirectory() as d:
                    fn(Path(d))
            else:
                fn()
            print(f"PASS {fn.__name__}")
        except AssertionError as e:
            failed += 1
            print(f"FAIL {fn.__name__}: {e}")
    sys.exit(1 if failed else 0)
