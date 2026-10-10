#!/usr/bin/env python3
"""Unit tests for audit_catalog_consistency (no pytest required)."""

import json
import sys
import tempfile
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPTS))

from audit_catalog_consistency import (  # noqa: E402
    audit_catalog,
    evaluate_gate,
    stale_baseline_keys,
    violation_key,
)


def test_violation_key_stable():
    k = violation_key("definition-without-wgsl", "foo", "missing path")
    assert k == "definition-without-wgsl|foo|missing path"


def test_id_filename_mismatch_detected():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        defs = root / "shader_definitions" / "generative"
        shaders = root / "public" / "shaders"
        lists = root / "public" / "shader-lists"
        defs.mkdir(parents=True)
        shaders.mkdir(parents=True)
        lists.mkdir(parents=True)
        (defs / "demo.json").write_text(
            json.dumps({"id": "demo-id", "url": "shaders/other-name.wgsl"}),
            encoding="utf-8",
        )
        (shaders / "other-name.wgsl").write_text("@compute @workgroup_size(8,8,1) fn main() {}\n")
        (lists / "generative.json").write_text(
            json.dumps([{"id": "demo-id", "url": "shaders/other-name.wgsl"}]),
            encoding="utf-8",
        )

        import audit_catalog_consistency as mod

        old = mod.DEFINITIONS_DIR, mod.SHADERS_DIR, mod.SHADER_LISTS_DIR, mod.MULTIPASS_REGISTRY_TS
        mod.DEFINITIONS_DIR = root / "shader_definitions"
        mod.SHADERS_DIR = shaders
        mod.SHADER_LISTS_DIR = lists
        mod.MULTIPASS_REGISTRY_TS = root / "nonexistent.ts"
        try:
            paths = mod.discover_definition_paths()
            defs_loaded = mod.load_definitions_parallel(paths)
            report = mod.audit_catalog(defs_loaded, lists_regenerated=False)
        finally:
            mod.DEFINITIONS_DIR, mod.SHADERS_DIR, mod.SHADER_LISTS_DIR, mod.MULTIPASS_REGISTRY_TS = old

        types = {v["type"] for v in report["violations"]}
        assert "id-filename-mismatch" in types


def test_graph_parent_skips_id_filename_mismatch():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        defs = root / "shader_definitions" / "simulation"
        shaders = root / "public" / "shaders"
        lists = root / "public" / "shader-lists"
        defs.mkdir(parents=True)
        shaders.mkdir(parents=True)
        lists.mkdir(parents=True)
        (defs / "ripple-tank.json").write_text(
            json.dumps({
                "id": "ripple-tank",
                "url": "shaders/ripple-tank-step.wgsl",
                "multipass": {
                    "graph": {
                        "nodes": [{"id": "step", "entry": "ripple-tank-step"}],
                    },
                },
            }),
            encoding="utf-8",
        )
        (shaders / "ripple-tank-step.wgsl").write_text("@compute @workgroup_size(8,8,1) fn main() {}\n")
        (lists / "simulation.json").write_text(
            json.dumps([{"id": "ripple-tank", "url": "shaders/ripple-tank-step.wgsl"}]),
            encoding="utf-8",
        )

        import audit_catalog_consistency as mod

        old = mod.DEFINITIONS_DIR, mod.SHADERS_DIR, mod.SHADER_LISTS_DIR, mod.MULTIPASS_REGISTRY_TS
        mod.DEFINITIONS_DIR = root / "shader_definitions"
        mod.SHADERS_DIR = shaders
        mod.SHADER_LISTS_DIR = lists
        mod.MULTIPASS_REGISTRY_TS = root / "nonexistent.ts"
        try:
            paths = mod.discover_definition_paths()
            defs_loaded = mod.load_definitions_parallel(paths)
            report = mod.audit_catalog(defs_loaded, lists_regenerated=False)
        finally:
            mod.DEFINITIONS_DIR, mod.SHADERS_DIR, mod.SHADER_LISTS_DIR, mod.MULTIPASS_REGISTRY_TS = old

        mismatches = [v for v in report["violations"] if v["type"] == "id-filename-mismatch"]
        assert mismatches == []


def test_gate_baseline_accepts_known():
    report = {
        "violation_count": 1,
        "violations": [{
            "type": "wgsl-without-definition",
            "id": "orphan",
            "detail": "public/shaders/orphan.wgsl",
            "key": violation_key("wgsl-without-definition", "orphan", "orphan.wgsl"),
        }],
    }
    baseline = {report["violations"][0]["key"]}
    ok, new = evaluate_gate(report, baseline)
    assert ok and new == []


def test_gate_fails_new_violation():
    report = {
        "violation_count": 1,
        "violations": [{
            "type": "definition-without-wgsl",
            "id": "new-one",
            "detail": "missing",
            "key": violation_key("definition-without-wgsl", "new-one", "missing"),
        }],
    }
    ok, new = evaluate_gate(report, set())
    assert not ok and len(new) == 1


def _run_audit(root: Path):
    import audit_catalog_consistency as mod

    old = mod.DEFINITIONS_DIR, mod.SHADERS_DIR, mod.SHADER_LISTS_DIR, mod.MULTIPASS_REGISTRY_TS
    mod.DEFINITIONS_DIR = root / "shader_definitions"
    mod.SHADERS_DIR = root / "public" / "shaders"
    mod.SHADER_LISTS_DIR = root / "public" / "shader-lists"
    mod.MULTIPASS_REGISTRY_TS = root / "nonexistent.ts"
    try:
        loaded = mod.load_definitions_parallel(mod.discover_definition_paths())
        return mod.audit_catalog(loaded, lists_regenerated=False)
    finally:
        mod.DEFINITIONS_DIR, mod.SHADERS_DIR, mod.SHADER_LISTS_DIR, mod.MULTIPASS_REGISTRY_TS = old


def test_graph_node_pass_shader_is_secondary_not_orphan():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        defs = root / "shader_definitions" / "simulation"
        shaders = root / "public" / "shaders"
        (root / "public" / "shader-lists").mkdir(parents=True)
        defs.mkdir(parents=True)
        shaders.mkdir(parents=True)
        graph = {"maxPassesPerFrame": 2, "nodes": [
            {"id": "a", "entry": "tank-step", "reads": [], "writes": []},
            {"id": "b", "entry": "tank-missing", "reads": [], "writes": []},
        ]}
        (defs / "tank.json").write_text(json.dumps(
            {"id": "tank", "url": "shaders/tank.wgsl", "multipass": {"graph": graph}}))
        (shaders / "tank.wgsl").write_text("fn main() {}\n")
        (shaders / "tank-step.wgsl").write_text("fn main() {}\n")
        report = _run_audit(root)
        orphans = {v["id"] for v in report["violations"] if v["type"] == "orphan-graph-entry"}
        assert "tank-step" not in orphans, "graph pass with a WGSL file is a secondary pass"
        assert "tank-missing" in orphans, "graph entry with no WGSL file is still an orphan"
        assert not [v for v in report["violations"] if v["type"] == "wgsl-without-definition"]


def test_id_url_allowlist_is_pinned_to_the_exact_pair():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        defs = root / "shader_definitions" / "generative"
        shaders = root / "public" / "shaders"
        (root / "public" / "shader-lists").mkdir(parents=True)
        defs.mkdir(parents=True)
        shaders.mkdir(parents=True)
        # gen-grid -> gen_grid is pinned in catalog_id_url_allowlist.json; gen-grid -> other is not.
        (defs / "gen-grid.json").write_text(json.dumps({"id": "gen-grid", "url": "shaders/gen_grid.wgsl"}))
        (shaders / "gen_grid.wgsl").write_text("fn main() {}\n")
        assert not [v for v in _run_audit(root)["violations"] if v["type"] == "id-filename-mismatch"]
        (defs / "gen-grid.json").write_text(json.dumps({"id": "gen-grid", "url": "shaders/other.wgsl"}))
        (shaders / "other.wgsl").write_text("fn main() {}\n")
        assert [v for v in _run_audit(root)["violations"] if v["type"] == "id-filename-mismatch"]


def test_stale_baseline_keys_detected():
    report = {"violations": [{"type": "t", "id": "x", "detail": "d", "key": "t|x|d"}]}
    assert stale_baseline_keys(report, {"t|x|d"}) == []
    assert stale_baseline_keys(report, {"t|x|d", "t|gone|d"}) == ["t|gone|d"]


def main() -> int:
    tests = [
        test_violation_key_stable,
        test_id_filename_mismatch_detected,
        test_graph_parent_skips_id_filename_mismatch,
        test_gate_baseline_accepts_known,
        test_gate_fails_new_violation,
        test_graph_node_pass_shader_is_secondary_not_orphan,
        test_id_url_allowlist_is_pinned_to_the_exact_pair,
        test_stale_baseline_keys_detected,
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
