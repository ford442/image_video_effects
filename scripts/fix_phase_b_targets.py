#!/usr/bin/env python3
"""
Fix Phase B targets by removing false positives (shaders that already have mouse)
and replacing them with genuine no-mouse candidates.
"""

import json
import re
import os
from pathlib import Path

SCAN_PATH = Path("/root/image_video_effects/swarm-outputs/shader_scan_results.json")
PB_JSON_PATH = Path("/root/image_video_effects/swarm-outputs/phase-b-upgrade-targets.json")
PB_MD_PATH = Path("/root/image_video_effects/swarm-outputs/phase-b-upgrade-targets.md")
REGISTRY_PATH = Path("/root/image_video_effects/swarm-outputs/upgrade-target-registry.md")

# Exclude templates, phase-a completed, and infrastructure
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


def main():
    with open(SCAN_PATH) as f:
        scan_data = json.load(f)

    by_id = {r["id"]: r for r in scan_data}

    # 1. Identify false positives in current Phase B targets
    with open(PB_JSON_PATH) as f:
        pb = json.load(f)

    false_positives = []
    valid_targets = []

    for t in pb["targets"]:
        tid = t["id"]
        if t["bucket"] == "hybrids":
            valid_targets.append(t)
            continue
        r = by_id.get(tid)
        if not r:
            false_positives.append((tid, "missing from scan"))
            continue
        if r.get("uses_mouse_expanded", r.get("uses_mouse", False)):
            false_positives.append((tid, f"has mouse (patterns)"))
            continue
        valid_targets.append(t)

    print(f"False positives to remove: {len(false_positives)}")
    for tid, reason in false_positives:
        print(f"  - {tid}: {reason}")

    # 2. Build candidate pool for replacements
    candidates = [r for r in scan_data
                  if r["id"] not in EXCLUDE_IDS
                  and r["id"] not in PHASE_A_COMPLETED
                  and not r.get("uses_mouse_expanded", r.get("uses_mouse", False))
                  and r["category"] not in ("unknown",)]

    # Remove already-valid targets from candidates
    valid_ids = {t["id"] for t in valid_targets}
    candidates = [r for r in candidates if r["id"] not in valid_ids]

    # 3. Determine how many replacements needed per bucket
    removed_by_bucket = {}
    for tid, reason in false_positives:
        # Find which bucket it was in
        for t in pb["targets"]:
            if t["id"] == tid:
                removed_by_bucket[t["bucket"]] = removed_by_bucket.get(t["bucket"], 0) + 1
                break

    print(f"\nRemoved by bucket: {removed_by_bucket}")

    # 4. Find replacements
    replacements = []

    # Huge refactors: >15KB, no mouse
    huge_needed = removed_by_bucket.get("huge", 0)
    huge_pool = [r for r in candidates if r["size_bytes"] > 15 * 1024 and "-pass" not in r["id"]]
    huge_pool.sort(key=lambda x: x["size_bytes"], reverse=True)
    huge_replacements = huge_pool[:huge_needed]
    for r in huge_replacements:
        replacements.append({
            "id": r["id"],
            "name": r["name"],
            "category": r["category"],
            "size_bytes": r["size_bytes"],
            "line_count": r["line_count"],
            "bucket": "huge",
            "priority": 1,
            "status": "pending",
            "mouse_gap": True,
            "notes": f"Multi-pass refactor candidate. Add mouse-driven control via zoom_config.yz.",
        })
        candidates.remove(r)

    # Complex: 5-8KB, no mouse
    complex_needed = removed_by_bucket.get("complex", 0)
    complex_pool = [r for r in candidates if 5 * 1024 <= r["size_bytes"] <= 8 * 1024]
    complex_pool.sort(key=lambda x: abs(x["size_bytes"] - 6.5 * 1024))
    complex_replacements = complex_pool[:complex_needed]
    for r in complex_replacements:
        replacements.append({
            "id": r["id"],
            "name": r["name"],
            "category": r["category"],
            "size_bytes": r["size_bytes"],
            "line_count": r["line_count"],
            "bucket": "complex",
            "priority": 3,
            "status": "pending",
            "mouse_gap": True,
            "notes": f"Add mouse response: zoom_config.yz as focal point/displacement origin.",
        })
        candidates.remove(r)

    # Mouse-interactive: <5KB, no mouse
    mouse_needed = removed_by_bucket.get("mouse_interactive", 0)
    mouse_pool = [r for r in candidates if r["size_bytes"] < 5 * 1024]
    mouse_pool.sort(key=lambda x: x["size_bytes"])
    mouse_replacements = mouse_pool[:mouse_needed]
    for r in mouse_replacements:
        replacements.append({
            "id": r["id"],
            "name": r["name"],
            "category": r["category"],
            "size_bytes": r["size_bytes"],
            "line_count": r["line_count"],
            "bucket": "mouse_interactive",
            "priority": 5,
            "status": "pending",
            "mouse_gap": True,
            "notes": f"Add mouse-driven interaction via zoom_config.yz and zoom_config.w.",
        })
        candidates.remove(r)

    # 5. Rebuild target list
    all_targets = valid_targets + replacements
    # Re-sort
    def sort_key(t):
        bucket_order = {"huge": 0, "complex": 1, "hybrids": 2, "mouse_interactive": 3}
        return (bucket_order.get(t["bucket"], 99), t.get("priority", 99), -t.get("size_bytes", 0))

    all_targets.sort(key=sort_key)

    # 6. Build JSON
    json_data = {
        "version": "1.2",
        "last_updated": "2026-04-18",
        "total_targets": len(all_targets),
        "false_positives_removed": len(false_positives),
        "replacements_added": len(replacements),
        "buckets": {
            "huge": sum(1 for t in all_targets if t["bucket"] == "huge"),
            "complex": sum(1 for t in all_targets if t["bucket"] == "complex"),
            "hybrids": sum(1 for t in all_targets if t["bucket"] == "hybrids"),
            "mouse_interactive": sum(1 for t in all_targets if t["bucket"] == "mouse_interactive"),
        },
        "targets": all_targets,
    }

    with open(PB_JSON_PATH, "w") as f:
        json.dump(json_data, f, indent=2)

    # 7. Build MD
    md = build_md(json_data, false_positives, replacements)
    with open(PB_MD_PATH, "w") as f:
        f.write(md)

    print(f"\n=== FIXED PHASE B TARGETS ===")
    print(f"Removed: {len(false_positives)} false positives")
    print(f"Added: {len(replacements)} replacements")
    print(f"Final total: {len(all_targets)}")
    for bucket, count in json_data["buckets"].items():
        print(f"  {bucket}: {count}")


def build_md(data, removed, replacements):
    lines = [
        "# Phase B Upgrade Targets",
        "",
        f"**Generated:** {data['last_updated']}",
        f"**Version:** 1.2 (corrected)",
        "**Evaluator:** Agent EV-2A + EV-Correction Pass",
        f"**Total Targets:** {data['total_targets']}",
        "**Focus:** Mouse-driven interactivity (not audio reactivity)",
        "",
        "## Correction Pass",
        "",
        f"- **False positives removed:** {data['false_positives_removed']} shaders that already had mouse support",
        f"- **Replacements added:** {data['replacements_added']} genuine no-mouse candidates",
        "- Expanded mouse detection to catch `MouseX`, `MouseY`, `mousePos`, `mouse_down`, `cursor`, `pointer` patterns",
        "",
        "### Removed (already have mouse)",
        "",
        "| Shader | Reason |",
        "|--------|--------|",
    ]
    for tid, reason in removed:
        lines.append(f"| `{tid}` | {reason} |")

    lines.extend([
        "",
        "### Added (genuine no-mouse candidates)",
        "",
        "| Shader | Bucket | Size | Category |",
        "|--------|--------|------|----------|",
    ])
    for t in replacements:
        size_kb = t["size_bytes"] / 1024
        lines.append(f"| `{t['id']}` | {t['bucket']} | {size_kb:.1f} KB | {t['category']} |")

    lines.extend([
        "",
        "## Bucket Summary",
        "",
        "| Bucket | Count | Priority | Focus |",
        "|--------|-------|----------|-------|",
        f"| Huge Refactors | {data['buckets']['huge']} | P1 | Multi-pass split for >15KB shaders + mouse add |",
        f"| Complex Upgrades | {data['buckets']['complex']} | P2–P4 | 5–8KB shaders + mouse response |",
        f"| Advanced Hybrids | {data['buckets']['hybrids']} | P2 | New multi-technique mouse-driven shaders |",
        f"| Mouse-Interactive | {data['buckets']['mouse_interactive']} | P5 | <5KB shaders, easy mouse wins |",
        "",
        "---",
        "",
        "## 1. Huge Refactors (>15 KB → Multi-Pass + Mouse)",
        "",
        "| Priority | Shader | Size | Category | Mouse Gap | Notes |",
        "|----------|--------|------|----------|-----------|-------|",
    ])
    for t in data["targets"]:
        if t["bucket"] != "huge":
            continue
        size_kb = t["size_bytes"] / 1024
        mouse = "❌" if t.get("mouse_gap", True) else "✅"
        lines.append(f"| {t['priority']} | `{t['id']}` | {size_kb:.1f} KB | {t['category']} | {mouse} | {t.get('notes', '')} |")

    lines.extend([
        "",
        "---",
        "",
        "## 2. Complex Upgrades (5–8 KB + Mouse Response)",
        "",
        "| Priority | Shader | Size | Category | Mouse Gap | Notes |",
        "|----------|--------|------|----------|-----------|-------|",
    ])
    for t in data["targets"]:
        if t["bucket"] != "complex":
            continue
        size_kb = t["size_bytes"] / 1024
        mouse = "❌" if t.get("mouse_gap", True) else "✅"
        lines.append(f"| {t['priority']} | `{t['id']}` | {size_kb:.1f} KB | {t['category']} | {mouse} | {t.get('notes', '')} |")

    lines.extend([
        "",
        "---",
        "",
        "## 3. Advanced Hybrid Creations (New Shaders)",
        "",
        "| Priority | Shader | Category | Techniques | Notes |",
        "|----------|--------|----------|------------|-------|",
    ])
    for t in data["targets"]:
        if t["bucket"] != "hybrids":
            continue
        techs = ", ".join(t.get("techniques", []))
        lines.append(f"| {t['priority']} | `{t['id']}` | {t['category']} | {techs} | {t.get('notes', '')} |")

    lines.extend([
        "",
        "---",
        "",
        "## 4. Mouse-Interactive Upgrades (<5 KB, Easy Wins)",
        "",
        "| Priority | Shader | Size | Category | Mouse Gap | Notes |",
        "|----------|--------|------|----------|-----------|-------|",
    ])
    for t in data["targets"]:
        if t["bucket"] != "mouse_interactive":
            continue
        size_kb = t["size_bytes"] / 1024
        mouse = "❌" if t.get("mouse_gap", True) else "✅"
        lines.append(f"| {t['priority']} | `{t['id']}` | {size_kb:.1f} KB | {t['category']} | {mouse} | {t.get('notes', '')} |")

    lines.extend([
        "",
        "---",
        "",
        "## Selection Criteria",
        "",
        "1. **Huge Refactors:** Size >15 KB, not already multi-pass (`-pass` in ID excluded).",
        "2. **Complex Upgrades:** 5–8 KB, does NOT use mouse coords (`zoom_config.yz`, `MouseX`, `mousePos`, etc.), category in mouse-friendly list.",
        "3. **Advanced Hybrids:** Conceptual new shaders combining 2–3 techniques, mouse-driven by design.",
        "4. **Mouse-Interactive:** <5 KB, no mouse usage, easy to add `zoom_config.yz` displacement/focal-point.",
        "",
        "## Mouse Response Patterns to Apply",
        "",
        "```wgsl",
        "// Displacement / Distortion",
        "let mousePos = u.zoom_config.yz;",
        "let mouseStrength = u.zoom_params.x;",
        "let displacement = (uv - mousePos) * mouseStrength * 0.1;",
        "",
        "// Focal Point",
        "let center = mix(vec2(0.5), u.zoom_config.yz, u.zoom_params.x);",
        "",
        "// Interactive Reveal",
        "let mouseDown = u.zoom_config.w > 0.5;",
        "let revealRadius = select(0.0, u.zoom_params.y, mouseDown);",
        "```",
        "",
    ])

    return "\n".join(lines)


if __name__ == "__main__":
    main()
