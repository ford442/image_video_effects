#!/usr/bin/env python3
"""
Curate Phase B upgrade targets from scan data.
Produces swarm-outputs/phase-b-upgrade-targets.json and .md
"""

import json
from pathlib import Path

SCAN_PATH = Path("/root/image_video_effects/swarm-outputs/shader_scan_results.json")
OUTPUT_JSON = Path("/root/image_video_effects/swarm-outputs/phase-b-upgrade-targets.json")
OUTPUT_MD = Path("/root/image_video_effects/swarm-outputs/phase-b-upgrade-targets.md")

# Categories that benefit most from mouse interaction
MOUSE_FRIENDLY_CATEGORIES = [
    "distortion", "artistic", "interactive-mouse", "visual-effects",
    "liquid-effects", "lighting-effects", "geometric", "image",
    "retro-glitch", "post-processing"
]

# Known template / library files to exclude
EXCLUDE_IDS = {
    "_hash_library", "_template_shared_memory", "_template_workgroup_atomics",
    "texture", "imageVideo",  # core infrastructure
}


def curate_targets(scan_data):
    by_id = {r["id"]: r for r in scan_data}

    # Exclude templates and already-complete Phase A shaders
    phase_a_completed = {
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

    candidates = [r for r in scan_data
                  if r["id"] not in EXCLUDE_IDS
                  and r["id"] not in phase_a_completed
                  and r["category"] not in ("unknown",)]

    # 1. Huge Refactors (>15 KB)
    huge = [r for r in candidates if r["size_bytes"] > 15 * 1024]
    # Sort by size descending, pick top 3 that are NOT already multi-pass
    huge = [r for r in huge if "-pass" not in r["id"]]
    huge.sort(key=lambda x: x["size_bytes"], reverse=True)
    huge_targets = huge[:3]

    # 2. Complex Upgrades (5–8 KB, no mouse, high visual impact)
    complex_candidates = [r for r in candidates
                          if 5 * 1024 <= r["size_bytes"] <= 8 * 1024
                          and not r["uses_mouse"]
                          and r["category"] in MOUSE_FRIENDLY_CATEGORIES]
    # Score by: size (closer to 6.5KB = better), category diversity bonus
    def complex_score(r):
        size_score = 1.0 - abs(r["size_bytes"] - 6.5 * 1024) / (3 * 1024)
        cat_bonus = 1.5 if r["category"] in MOUSE_FRIENDLY_CATEGORIES else 1.0
        return size_score * cat_bonus

    complex_candidates.sort(key=complex_score, reverse=True)
    complex_targets = complex_candidates[:50]

    # 3. Advanced Hybrid Creations (new shaders, not existing ones)
    # These are conceptual targets — list from spec
    hybrid_concepts = [
        {"id": "hyper-tensor-fluid", "name": "Hyper Tensor Fluid", "techniques": ["tensor_flow", "navier_stokes", "depth_aware"], "category": "advanced-hybrid"},
        {"id": "neural-raymarcher", "name": "Neural Raymarcher", "techniques": ["sdf_raymarching", "neural_pattern", "volumetric"], "category": "advanced-hybrid"},
        {"id": "chromatic-reaction-diffusion", "name": "Chromatic Reaction-Diffusion", "techniques": ["reaction_diffusion", "chromatic_aberration", "feedback"], "category": "advanced-hybrid"},
        {"id": "gravitational-lensing", "name": "Gravitational Lensing", "techniques": ["physics_simulation", "spacetime_distortion", "raytracing"], "category": "advanced-hybrid"},
        {"id": "cellular-automata-3d", "name": "3D Cellular Automata", "techniques": ["cellular_automata", "3d_texture", "raymarching"], "category": "advanced-hybrid"},
        {"id": "spectral-flow-sorting", "name": "Spectral Flow Pixel Sort", "techniques": ["pixel_sorting", "optical_flow", "spectral_analysis"], "category": "advanced-hybrid"},
        {"id": "multi-fractal-compositor", "name": "Multi-Fractal Compositor", "techniques": ["mandelbrot", "julia", "lyapunov", "hybrid_fractals"], "category": "advanced-hybrid"},
        {"id": "mouse-voronoi-displacement", "name": "Mouse Voronoi Displacement", "techniques": ["voronoi", "mouse_displacement", "displacement_mapping"], "category": "advanced-hybrid"},
        {"id": "fractal-boids-field", "name": "Fractal Boids Field", "techniques": ["boids_flocking", "fractal_noise", "vector_field"], "category": "advanced-hybrid"},
        {"id": "holographic-interferometry", "name": "Holographic Interferometry", "techniques": ["interference_patterns", "holography", "depth_parallax"], "category": "advanced-hybrid"},
    ]

    # 4. Mouse-Interactive Upgrades (<5 KB, no mouse, easy wins)
    mouse_candidates = [r for r in candidates
                        if r["size_bytes"] < 5 * 1024
                        and not r["uses_mouse"]
                        and r["category"] in MOUSE_FRIENDLY_CATEGORIES
                        and r["id"] not in {t["id"] for t in hybrid_concepts}]
    # Prioritize: smaller = easier to upgrade, distinct categories
    seen_cats = set()
    mouse_targets = []
    for r in sorted(mouse_candidates, key=lambda x: x["size_bytes"]):
        if len(mouse_targets) >= 50:
            break
        mouse_targets.append(r)

    return {
        "huge": huge_targets,
        "complex": complex_targets,
        "hybrids": hybrid_concepts,
        "mouse_interactive": mouse_targets,
    }


def priority_for_target(r, bucket):
    if bucket == "huge":
        return 1
    if bucket == "complex":
        size = r["size_bytes"]
        if size > 7 * 1024:
            return 2
        elif size > 6 * 1024:
            return 3
        else:
            return 4
    if bucket == "mouse_interactive":
        return 5
    return 10


def build_json(targets):
    entries = []
    for bucket, items in targets.items():
        for item in items:
            if isinstance(item, dict) and "size_bytes" in item:
                # From scan data
                entries.append({
                    "id": item["id"],
                    "name": item["name"],
                    "category": item["category"],
                    "size_bytes": item["size_bytes"],
                    "line_count": item["line_count"],
                    "bucket": bucket,
                    "priority": priority_for_target(item, bucket),
                    "status": "pending",
                    "mouse_gap": not item["uses_mouse"],
                    "notes": "",
                })
            else:
                # Hybrid concept
                entries.append({
                    "id": item["id"],
                    "name": item["name"],
                    "category": item["category"],
                    "size_bytes": 0,
                    "line_count": 0,
                    "bucket": bucket,
                    "priority": 2,
                    "status": "pending",
                    "mouse_gap": True,
                    "techniques": item.get("techniques", []),
                    "notes": f"New creation: {', '.join(item.get('techniques', []))}",
                })
    entries.sort(key=lambda x: (x["priority"], -x["size_bytes"]))
    return {
        "version": "1.0",
        "last_updated": "2026-04-18",
        "total_targets": len(entries),
        "buckets": {
            "huge": len(targets["huge"]),
            "complex": len(targets["complex"]),
            "hybrids": len(targets["hybrids"]),
            "mouse_interactive": len(targets["mouse_interactive"]),
        },
        "targets": entries,
    }


def build_md(data, targets):
    lines = [
        "# Phase B Upgrade Targets",
        "",
        f"**Generated:** {data['last_updated']}  ",
        f"**Total Targets:** {data['total_targets']}  ",
        f"**Focus:** Mouse-driven interactivity (not audio reactivity)  ",
        "",
        "## Bucket Summary",
        "",
        "| Bucket | Count | Priority | Focus |",
        "|--------|-------|----------|-------|",
        f"| Huge Refactors | {data['buckets']['huge']} | P1 | Multi-pass split for >15KB shaders |",
        f"| Complex Upgrades | {data['buckets']['complex']} | P2–P4 | 5–8KB shaders + mouse response |",
        f"| Advanced Hybrids | {data['buckets']['hybrids']} | P2 | New multi-technique mouse-driven shaders |",
        f"| Mouse-Interactive | {data['buckets']['mouse_interactive']} | P5 | <5KB shaders, easy mouse wins |",
        "",
        "---",
        "",
        "## 1. Huge Refactors (>15 KB → Multi-Pass)",
        "",
        "| Priority | Shader | Size | Category | Current Mouse | Notes |",
        "|----------|--------|------|----------|---------------|-------|",
    ]
    for t in data["targets"]:
        if t["bucket"] != "huge":
            continue
        size_kb = t["size_bytes"] / 1024
        mouse = "✅" if not t["mouse_gap"] else "❌"
        lines.append(f"| {t['priority']} | {t['id']} | {size_kb:.1f} KB | {t['category']} | {mouse} | {t['notes']} |")

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
        lines.append(f"| {t['priority']} | {t['id']} | {size_kb:.1f} KB | {t['category']} | {'❌' if t['mouse_gap'] else '✅'} | |")

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
        lines.append(f"| {t['priority']} | {t['id']} | {t['category']} | {techs} | {t['notes']} |")

    lines.extend([
        "",
        "---",
        "",
        "## 4. Mouse-Interactive Upgrades (<5 KB, Easy Wins)",
        "",
        "| Priority | Shader | Size | Category | Notes |",
        "|----------|--------|------|----------|-------|",
    ])
    for t in data["targets"]:
        if t["bucket"] != "mouse_interactive":
            continue
        size_kb = t["size_bytes"] / 1024
        lines.append(f"| {t['priority']} | {t['id']} | {size_kb:.1f} KB | {t['category']} | |")

    lines.extend([
        "",
        "---",
        "",
        "## Selection Criteria",
        "",
        "1. **Huge Refactors:** Size >15 KB, not already multi-pass (`-pass` in ID excluded).",
        "2. **Complex Upgrades:** 5–8 KB, does NOT use `zoom_config.yz` or `zoom_config.w`, category in mouse-friendly list.",
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


def main():
    with open(SCAN_PATH) as f:
        scan_data = json.load(f)

    targets = curate_targets(scan_data)
    json_data = build_json(targets)

    with open(OUTPUT_JSON, "w") as f:
        json.dump(json_data, f, indent=2)

    md_content = build_md(json_data, targets)
    with open(OUTPUT_MD, "w") as f:
        f.write(md_content)

    print("=== Phase B Target Curation Complete ===")
    print(f"Huge refactors: {len(targets['huge'])}")
    print(f"Complex upgrades: {len(targets['complex'])}")
    print(f"Advanced hybrids: {len(targets['hybrids'])}")
    print(f"Mouse-interactive: {len(targets['mouse_interactive'])}")
    print(f"Total: {json_data['total_targets']}")
    print(f"\nWritten to:")
    print(f"  {OUTPUT_JSON}")
    print(f"  {OUTPUT_MD}")


if __name__ == "__main__":
    main()
