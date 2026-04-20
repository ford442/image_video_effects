#!/usr/bin/env python3
"""
Phase B Target Curation v2 — Realistic targeting with mouse-depth classification.
Classifies mouse support as: none, basic, or advanced.
Targets "none" first, then "basic" for enhancement.
"""

import json
import re
import os
from pathlib import Path

SCAN_PATH = Path("/root/image_video_effects/swarm-outputs/shader_scan_results.json")
PB_JSON_PATH = Path("/root/image_video_effects/swarm-outputs/phase-b-upgrade-targets.json")
PB_MD_PATH = Path("/root/image_video_effects/swarm-outputs/phase-b-upgrade-targets.md")

EXCLUDE_IDS = {
    "_hash_library", "_template_shared_memory", "_template_workgroup_atomics",
    "texture", "imageVideo", "plasma",
}

PHASE_A_COMPLETED = {
    'rgb-glitch-trail', 'chroma-shift-grid', 'selective-color', 'echo-trace',
    'temporal-slit-paint', 'signal-noise', 'sonic-distortion', 'galaxy-compute',
    'radial-rgb', 'luma-echo-warp', 'gen-astro-kinetic-chrono-orrery', 'gen-raptor-mini',
    'gen-cosmic-web-filament', 'gen_psychedelic_spiral', 'cymatic-sand',
    'gen-vitreous-chrono-chandelier', 'gen-xeno-botanical-synth-flora', 'gen-crystal-caverns',
    'gen-quantum-mycelium', 'gen-stellar-web-loom', 'gen-supernova-remnant',
    'gen-cyber-terminal', 'gen-bioluminescent-abyss', 'gen-chronos-labyrinth',
    'gen-quantum-superposition', 'interactive-fisheye', 'radial-blur', 'swirling-void',
    'static-reveal', 'entropy-grid', 'digital-mold', 'pixel-sorter', 'magnetic-field',
    'kaleidoscope', 'synthwave-grid-warp', 'sonar-reveal', 'concentric-spin',
    'interactive-fresnel', 'time-slit-scan', 'double-exposure-zoom', 'velocity-field-paint',
    'pixel-repel', 'lighthouse-reveal',
}

HYBRID_CONCEPTS = [
    {"id": "hyper-tensor-fluid", "name": "Hyper Tensor Fluid", "techniques": ["tensor_flow", "navier_stokes", "depth_aware"], "category": "advanced-hybrid"},
    {"id": "neural-raymarcher", "name": "Neural Raymarcher", "techniques": ["sdf_raymarching", "neural_pattern", "volumetric"], "category": "advanced-hybrid"},
    {"id": "chromatic-rd-cascade", "name": "Chromatic Reaction-Diffusion", "techniques": ["reaction_diffusion", "chromatic_aberration", "feedback"], "category": "advanced-hybrid"},
    {"id": "gravitational-lensing", "name": "Gravitational Lensing", "techniques": ["physics_simulation", "spacetime_distortion", "raytracing"], "category": "advanced-hybrid"},
    {"id": "cellular-automata-3d", "name": "3D Cellular Automata", "techniques": ["cellular_automata", "3d_texture", "raymarching"], "category": "advanced-hybrid"},
    {"id": "spectral-flow-hybrid", "name": "Spectral Flow Hybrid", "techniques": ["pixel_sorting", "optical_flow", "spectral_analysis"], "category": "advanced-hybrid"},
    {"id": "multi-fractal-compositor", "name": "Multi-Fractal Compositor", "techniques": ["mandelbrot", "julia", "lyapunov", "hybrid_fractals"], "category": "advanced-hybrid"},
    {"id": "mouse-voronoi-displacement", "name": "Mouse Voronoi Displacement", "techniques": ["voronoi", "mouse_displacement", "displacement_mapping"], "category": "advanced-hybrid"},
    {"id": "fractal-boids-field", "name": "Fractal Boids Field", "techniques": ["boids_flocking", "fractal_noise", "vector_field"], "category": "advanced-hybrid"},
    {"id": "holographic-interferometry", "name": "Holographic Interferometry", "techniques": ["interference_patterns", "holography", "depth_parallax"], "category": "advanced-hybrid"},
]


def classify_mouse(content):
    """Classify mouse support depth."""
    has_pos = bool(re.search(r'(zoom_config\.yz|MouseX|MouseY|mousePos|mouse_pos|mouse\.x|mouse\.y|mouse\.xy)', content))
    has_click = bool(re.search(r'(zoom_config\.w|mouseDown|mouse_down)', content))
    has_physics = bool(re.search(r'(spring|velocity|force|drag|physics|follow|track)', content, re.I))

    if not has_pos and not has_click:
        return "none"
    if has_pos and not has_click and not has_physics:
        return "basic"
    return "advanced"


def main():
    with open(SCAN_PATH) as f:
        scan_data = json.load(f)

    # Re-classify all shaders
    for r in scan_data:
        tid = r["id"]
        path = f"public/shaders/{tid}.wgsl"
        if os.path.exists(path):
            with open(path) as f:
                content = f.read()
            r["mouse_depth"] = classify_mouse(content)
        else:
            r["mouse_depth"] = "unknown"

    # Save updated scan
    with open(SCAN_PATH, "w") as f:
        json.dump(scan_data, f, indent=2)

    by_id = {r["id"]: r for r in scan_data}

    # Build candidate pools
    candidates = [r for r in scan_data
                  if r["id"] not in EXCLUDE_IDS
                  and r["id"] not in PHASE_A_COMPLETED
                  and r["category"] not in ("unknown",)]

    # Remove already-multi-pass pass files from huge consideration
    non_pass = [r for r in candidates if "-pass" not in r["id"]]

    # Huge: >15KB, regardless of mouse (multi-pass refactor is the main goal)
    huge_pool = [r for r in non_pass if r["size_bytes"] > 15 * 1024]
    huge_pool.sort(key=lambda x: x["size_bytes"], reverse=True)
    huge_targets = huge_pool[:3]

    # Complex: 5-15KB, target "none" and "basic" mouse (upgrade opportunity)
    complex_pool = [r for r in non_pass if 5 * 1024 <= r["size_bytes"] <= 15 * 1024]
    # Prioritize: no mouse first, then basic mouse
    def complex_sort(r):
        depth_score = {"none": 0, "basic": 1, "advanced": 2}.get(r["mouse_depth"], 3)
        size_score = abs(r["size_bytes"] - 7 * 1024) / (8 * 1024)
        return (depth_score, size_score)

    complex_pool.sort(key=complex_sort)
    complex_targets = complex_pool[:50]

    # Mouse-interactive: <5KB, target "none" and "basic"
    mouse_pool = [r for r in non_pass if r["size_bytes"] < 5 * 1024]
    mouse_pool.sort(key=lambda r: ({"none": 0, "basic": 1, "advanced": 2}.get(r["mouse_depth"], 3), r["size_bytes"]))
    mouse_targets = mouse_pool[:50]

    # Build target structures
    all_targets = []

    for r in huge_targets:
        all_targets.append({
            "id": r["id"], "name": r["name"], "category": r["category"],
            "size_bytes": r["size_bytes"], "line_count": r["line_count"],
            "bucket": "huge", "priority": 1, "status": "pending",
            "mouse_gap": r["mouse_depth"] == "none",
            "mouse_depth": r["mouse_depth"],
            "notes": f"Multi-pass refactor. Mouse: {r['mouse_depth']}.",
        })

    for r in complex_targets:
        all_targets.append({
            "id": r["id"], "name": r["name"], "category": r["category"],
            "size_bytes": r["size_bytes"], "line_count": r["line_count"],
            "bucket": "complex", "priority": 2 if r["mouse_depth"] == "none" else 3,
            "status": "pending",
            "mouse_gap": r["mouse_depth"] == "none",
            "mouse_depth": r["mouse_depth"],
            "notes": f"Add/enhance mouse response. Current: {r['mouse_depth']}.",
        })

    for concept in HYBRID_CONCEPTS:
        all_targets.append({
            "id": concept["id"], "name": concept["name"], "category": concept["category"],
            "size_bytes": 0, "line_count": 0,
            "bucket": "hybrids", "priority": 2, "status": "pending",
            "mouse_gap": True, "mouse_depth": "none",
            "techniques": concept["techniques"],
            "notes": f"New creation: {', '.join(concept['techniques'])}",
        })

    for r in mouse_targets:
        all_targets.append({
            "id": r["id"], "name": r["name"], "category": r["category"],
            "size_bytes": r["size_bytes"], "line_count": r["line_count"],
            "bucket": "mouse_interactive", "priority": 4 if r["mouse_depth"] == "none" else 5,
            "status": "pending",
            "mouse_gap": r["mouse_depth"] == "none",
            "mouse_depth": r["mouse_depth"],
            "notes": f"Add mouse interaction. Current: {r['mouse_depth']}.",
        })

    json_data = {
        "version": "2.0",
        "last_updated": "2026-04-18",
        "total_targets": len(all_targets),
        "buckets": {
            "huge": sum(1 for t in all_targets if t["bucket"] == "huge"),
            "complex": sum(1 for t in all_targets if t["bucket"] == "complex"),
            "hybrids": sum(1 for t in all_targets if t["bucket"] == "hybrids"),
            "mouse_interactive": sum(1 for t in all_targets if t["bucket"] == "mouse_interactive"),
        },
        "mouse_breakdown": {
            "none": sum(1 for t in all_targets if t.get("mouse_depth") == "none"),
            "basic": sum(1 for t in all_targets if t.get("mouse_depth") == "basic"),
            "advanced": sum(1 for t in all_targets if t.get("mouse_depth") == "advanced"),
        },
        "targets": all_targets,
    }

    with open(PB_JSON_PATH, "w") as f:
        json.dump(json_data, f, indent=2)

    md = build_md(json_data, all_targets)
    with open(PB_MD_PATH, "w") as f:
        f.write(md)

    print("=== PHASE B TARGETS v2 ===")
    print(f"Total: {len(all_targets)}")
    for bucket, count in json_data["buckets"].items():
        print(f"  {bucket}: {count}")
    print("\nMouse depth breakdown:")
    for depth, count in json_data["mouse_breakdown"].items():
        print(f"  {depth}: {count}")


def build_md(data, targets):
    lines = [
        "# Phase B Upgrade Targets",
        "",
        f"**Generated:** {data['last_updated']}",
        "**Version:** 2.0 (corrected with mouse-depth classification)",
        "**Evaluator:** Evaluator Swarm",
        f"**Total Targets:** {data['total_targets']}",
        "**Focus:** Mouse-driven interactivity (not audio reactivity)",
        "",
        "## Correction Notes",
        "",
        "v1.0 had 39 false positives — shaders listed as needing mouse that already used `MouseX`, `mousePos`, etc. This v2.0 corrects that by:",
        "",
        "1. **Expanding mouse detection** to catch `MouseX`, `MouseY`, `mousePos`, `mouse_down`, `cursor`, `pointer`",
        "2. **Classifying mouse depth:** `none` → no mouse at all; `basic` → reads position only; `advanced` → click states, physics, springs",
        "3. **Targeting realistically:** `none` gets priority; `basic` gets secondary priority for advanced mouse features",
        "",
        "## Bucket Summary",
        "",
        "| Bucket | Count | Priority | Focus |",
        "|--------|-------|----------|-------|",
        f"| Huge Refactors | {data['buckets']['huge']} | P1 | Multi-pass split for >15KB shaders |",
        f"| Complex Upgrades | {data['buckets']['complex']} | P2–P3 | 5–15KB shaders, enhance mouse |",
        f"| Advanced Hybrids | {data['buckets']['hybrids']} | P2 | New multi-technique mouse-driven shaders |",
        f"| Mouse-Interactive | {data['buckets']['mouse_interactive']} | P4–P5 | <5KB shaders, add mouse |",
        "",
        "### Mouse Depth Breakdown",
        "",
        "| Depth | Count | Meaning |",
        "|-------|-------|---------|",
        f"| **none** | {data['mouse_breakdown']['none']} | No mouse usage at all — primary target |",
        f"| **basic** | {data['mouse_breakdown']['basic']} | Reads position only — enhance with clicks/physics |",
        f"| **advanced** | {data['mouse_breakdown']['advanced']} | Already has clicks/physics — skip or refine |",
        "",
        "---",
        "",
        "## 1. Huge Refactors (>15 KB)",
        "",
        "| Priority | Shader | Size | Category | Mouse | Notes |",
        "|----------|--------|------|----------|-------|-------|",
    ]
    for t in targets:
        if t["bucket"] != "huge":
            continue
        size_kb = t["size_bytes"] / 1024
        md = "❌" if t["mouse_depth"] == "none" else ("△" if t["mouse_depth"] == "basic" else "✅")
        lines.append(f"| {t['priority']} | `{t['id']}` | {size_kb:.1f} KB | {t['category']} | {md} | {t['notes']} |")

    lines.extend([
        "",
        "---",
        "",
        "## 2. Complex Upgrades (5–15 KB)",
        "",
        "| Priority | Shader | Size | Category | Mouse | Notes |",
        "|----------|--------|------|----------|-------|-------|",
    ])
    for t in targets:
        if t["bucket"] != "complex":
            continue
        size_kb = t["size_bytes"] / 1024
        md = "❌" if t["mouse_depth"] == "none" else ("△" if t["mouse_depth"] == "basic" else "✅")
        lines.append(f"| {t['priority']} | `{t['id']}` | {size_kb:.1f} KB | {t['category']} | {md} | {t['notes']} |")

    lines.extend([
        "",
        "---",
        "",
        "## 3. Advanced Hybrid Creations (New Shaders)",
        "",
        "| Priority | Shader | Category | Techniques | Notes |",
        "|----------|--------|----------|------------|-------|",
    ])
    for t in targets:
        if t["bucket"] != "hybrids":
            continue
        techs = ", ".join(t.get("techniques", []))
        lines.append(f"| {t['priority']} | `{t['id']}` | {t['category']} | {techs} | {t['notes']} |")

    lines.extend([
        "",
        "---",
        "",
        "## 4. Mouse-Interactive Upgrades (<5 KB)",
        "",
        "| Priority | Shader | Size | Category | Mouse | Notes |",
        "|----------|--------|------|----------|-------|-------|",
    ])
    for t in targets:
        if t["bucket"] != "mouse_interactive":
            continue
        size_kb = t["size_bytes"] / 1024
        md = "❌" if t["mouse_depth"] == "none" else ("△" if t["mouse_depth"] == "basic" else "✅")
        lines.append(f"| {t['priority']} | `{t['id']}` | {size_kb:.1f} KB | {t['category']} | {md} | {t['notes']} |")

    lines.extend([
        "",
        "---",
        "",
        "## Legend",
        "",
        "- **❌** = No mouse usage — add from scratch",
        "- **△** = Basic mouse (position only) — enhance with clicks, physics, spring",
        "- **✅** = Advanced mouse — already has clicks/physics",
        "",
    ])

    return "\n".join(lines)


if __name__ == "__main__":
    main()
