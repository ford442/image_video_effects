#!/usr/bin/env python3
"""
Shader Library Scanner for Evaluator Swarm
Scans all WGSL files and JSON definitions to produce a comprehensive
audit dataset for Phase A evaluation and Phase B target curation.
"""

import json
import os
import re
from pathlib import Path
from collections import defaultdict

PROJECT_ROOT = Path("/root/image_video_effects")
SHADERS_DIR = PROJECT_ROOT / "public" / "shaders"
DEFINITIONS_DIR = PROJECT_ROOT / "shader_definitions"
OUTPUT_DIR = PROJECT_ROOT / "swarm-outputs"


def get_json_definitions():
    """Load all JSON shader definitions into a dict keyed by shader id."""
    defs = {}
    for json_file in DEFINITIONS_DIR.rglob("*.json"):
        try:
            with open(json_file, "r") as f:
                data = json.load(f)
            if isinstance(data, list):
                for entry in data:
                    if "id" in entry:
                        entry["_json_path"] = str(json_file.relative_to(PROJECT_ROOT))
                        defs[entry["id"]] = entry
            elif isinstance(data, dict) and "id" in data:
                data["_json_path"] = str(json_file.relative_to(PROJECT_ROOT))
                defs[data["id"]] = data
        except Exception as e:
            print(f"Warning: could not parse {json_file}: {e}")
    return defs


def analyze_wgsl(filepath):
    """Analyze a single WGSL file and return a dict of findings."""
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
    except Exception as e:
        return {"error": str(e)}

    lines = content.splitlines()
    text = content

    # Basic stats
    size_bytes = os.path.getsize(filepath)
    line_count = len(lines)

    # Binding checks
    has_all_bindings = (
        "@group(0) @binding(0) var u_sampler" in text and
        "@group(0) @binding(1) var readTexture" in text and
        "@group(0) @binding(2) var writeTexture" in text and
        "@group(0) @binding(3) var<uniform> u: Uniforms" in text and
        "@group(0) @binding(4) var readDepthTexture" in text and
        "@group(0) @binding(5) var non_filtering_sampler" in text and
        "@group(0) @binding(6) var writeDepthTexture" in text and
        "@group(0) @binding(7) var dataTextureA" in text and
        "@group(0) @binding(8) var dataTextureB" in text and
        "@group(0) @binding(9) var dataTextureC" in text and
        "@group(0) @binding(10) var<storage, read_write> extraBuffer" in text and
        "@group(0) @binding(11) var comparison_sampler" in text and
        "@group(0) @binding(12) var<storage, read> plasmaBuffer" in text
    )

    # Workgroup size
    workgroup_ok = "@workgroup_size(8, 8, 1)" in text

    # Mouse usage
    uses_mouse = bool(re.search(r"zoom_config\.(yz|w)", text))
    uses_mouse_pos = bool(re.search(r"zoom_config\.yz", text))
    uses_mouse_down = bool(re.search(r"zoom_config\.w", text))

    # Audio reactivity
    uses_audio = "plasmaBuffer" in text

    # Depth write
    writes_depth = "writeDepthTexture" in text

    # Alpha checks (rough heuristics)
    hardcoded_alpha_1 = bool(re.search(r"vec4<f32>\([^,]+,\s*1\.0\s*\)", text))
    hardcoded_alpha_patterns = len(re.findall(r",\s*1\.0\s*\)", text))

    # Randomization safety heuristics
    unsafe_div = bool(re.search(r"/\s*(u\.zoom_params\.[xyzw]|zoom_params\.[xyzw])[^+]", text))
    unsafe_log = bool(re.search(r"log\s*\(\s*(u\.zoom_params|zoom_params)", text))
    unsafe_sqrt = bool(re.search(r"sqrt\s*\(\s*.*zoom_params", text))

    # Header check
    has_header = "// ═══════════════════════════════════════════════════════════════════" in text

    # Uniforms struct check
    has_uniforms = "struct Uniforms" in text and "config: vec4<f32>" in text and "zoom_config: vec4<f32>" in text and "zoom_params: vec4<f32>" in text and "array<vec4<f32>, 50>" in text

    # Loop bounds (rough)
    unbounded_while = bool(re.search(r"while\s*\(", text))

    return {
        "size_bytes": size_bytes,
        "line_count": line_count,
        "has_all_bindings": has_all_bindings,
        "workgroup_ok": workgroup_ok,
        "uses_mouse": uses_mouse,
        "uses_mouse_pos": uses_mouse_pos,
        "uses_mouse_down": uses_mouse_down,
        "uses_audio": uses_audio,
        "writes_depth": writes_depth,
        "hardcoded_alpha_1": hardcoded_alpha_1,
        "hardcoded_alpha_patterns": hardcoded_alpha_patterns,
        "unsafe_div": unsafe_div,
        "unsafe_log": unsafe_log,
        "unsafe_sqrt": unsafe_sqrt,
        "has_header": has_header,
        "has_uniforms": has_uniforms,
        "unbounded_while": unbounded_while,
    }


def main():
    definitions = get_json_definitions()
    results = []

    wgsl_files = sorted(SHADERS_DIR.glob("*.wgsl"))

    for wgsl_path in wgsl_files:
        shader_id = wgsl_path.stem
        analysis = analyze_wgsl(wgsl_path)

        # Cross-reference with JSON definition
        json_def = definitions.get(shader_id, {})
        category = json_def.get("category", "unknown")
        name = json_def.get("name", shader_id)
        features = json_def.get("features", [])
        params = json_def.get("params", [])

        result = {
            "id": shader_id,
            "name": name,
            "category": category,
            "wgsl_path": str(wgsl_path.relative_to(PROJECT_ROOT)),
            "json_path": json_def.get("_json_path", "MISSING"),
            "has_json": shader_id in definitions,
            "features": features,
            "param_count": len(params),
            **analysis,
        }
        results.append(result)

    # Write JSON output
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    json_out = OUTPUT_DIR / "shader_scan_results.json"
    with open(json_out, "w") as f:
        json.dump(results, f, indent=2)

    # Summary stats
    total = len(results)
    with_mouse = sum(1 for r in results if r["uses_mouse"])
    with_audio = sum(1 for r in results if r["uses_audio"])
    missing_json = sum(1 for r in results if not r["has_json"])
    bad_workgroup = sum(1 for r in results if not r["workgroup_ok"])
    missing_depth = sum(1 for r in results if not r["writes_depth"])
    hardcoded_alpha = sum(1 for r in results if r["hardcoded_alpha_1"])

    print(f"=== Shader Scan Complete ===")
    print(f"Total WGSL files scanned: {total}")
    print(f"With mouse usage: {with_mouse} ({with_mouse/total*100:.1f}%)")
    print(f"With audio reactivity: {with_audio} ({with_audio/total*100:.1f}%)")
    print(f"Missing JSON definition: {missing_json}")
    print(f"Wrong workgroup size: {bad_workgroup}")
    print(f"Missing depth write: {missing_depth}")
    print(f"Hardcoded alpha=1.0: {hardcoded_alpha}")
    print(f"Results written to: {json_out}")


if __name__ == "__main__":
    main()
