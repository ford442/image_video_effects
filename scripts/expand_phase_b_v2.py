#!/usr/bin/env python3
"""Expand Phase B targets v4 — add ALL remaining basic-mouse shaders + large advanced shaders."""

import json
from pathlib import Path

SCAN_PATH = Path("/root/image_video_effects/swarm-outputs/shader_scan_results.json")
PB_JSON_PATH = Path("/root/image_video_effects/swarm-outputs/phase-b-upgrade-targets.json")
PB_MD_PATH = Path("/root/image_video_effects/swarm-outputs/phase-b-upgrade-targets.md")
REGISTRY_PATH = Path("/root/image_video_effects/swarm-outputs/upgrade-target-registry.md")

PHASE_A = {
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

EXCLUDE = {'_hash_library', '_template_shared_memory', '_template_workgroup_atomics', 'texture', 'imageVideo', 'plasma'}


def main():
    with open(SCAN_PATH) as f:
        scan = {r["id"]: r for r in json.load(f)}

    with open(PB_JSON_PATH) as f:
        pb = json.load(f)

    existing_ids = {t["id"] for t in pb["targets"]}

    remaining = [r for r in scan.values()
                 if r["id"] not in PHASE_A
                 and r["id"] not in existing_ids
                 and r["id"] not in EXCLUDE
                 and r["category"] not in ("unknown",)]

    new_targets = []

    # 1. Add ALL remaining basic-mouse shaders
    basic = [r for r in remaining if r.get("mouse_depth") == "basic"]
    for r in basic:
        kb = r["size_bytes"] / 1024
        if kb > 15:
            bucket, priority = "huge", 1
        elif kb >= 5:
            bucket, priority = "complex", 3
        else:
            bucket, priority = "mouse_interactive", 5
        new_targets.append(make_target(r, bucket, priority, "Enhance mouse: add click states, physics, spring following."))

    # 2. Add large advanced-mouse shaders (>10KB) for optimization/multi-pass
    advanced_large = [r for r in remaining
                      if r.get("mouse_depth") == "advanced"
                      and r["size_bytes"] > 10 * 1024
                      and "-pass" not in r["id"]]
    for r in advanced_large:
        new_targets.append(make_target(r, "complex", 3, "Optimize/refactor. Already has advanced mouse — focus on performance/alpha."))

    # Merge
    all_targets = pb["targets"] + new_targets

    def sort_key(t):
        bucket_order = {"huge": 0, "complex": 1, "hybrids": 2, "mouse_interactive": 3}
        return (bucket_order.get(t["bucket"], 99), t.get("priority", 99), -t.get("size_bytes", 0))
    all_targets.sort(key=sort_key)

    json_data = {
        "version": "4.0",
        "last_updated": "2026-04-18",
        "total_targets": len(all_targets),
        "added_in_v4": len(new_targets),
        "previous_total": pb["total_targets"],
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

    print("=== PHASE B TARGETS v4 ===")
    print(f"Previous total (v3): {pb['total_targets']}")
    print(f"Added: {len(new_targets)}")
    print(f"New total: {len(all_targets)}")
    for bucket, count in json_data["buckets"].items():
        print(f"  {bucket}: {count}")
    print("\nMouse depth breakdown:")
    for depth, count in json_data["mouse_breakdown"].items():
        print(f"  {depth}: {count}")

    rebuild_registry(json_data, all_targets)


def make_target(r, bucket, priority, note):
    return {
        "id": r["id"],
        "name": r["name"],
        "category": r["category"],
        "size_bytes": r["size_bytes"],
        "line_count": r["line_count"],
        "bucket": bucket,
        "priority": priority,
        "status": "pending",
        "mouse_gap": r.get("mouse_depth") == "none",
        "mouse_depth": r.get("mouse_depth", "unknown"),
        "notes": note,
    }


def build_md(data, targets):
    lines = [
        "# Phase B Upgrade Targets",
        "",
        f"**Generated:** {data['last_updated']}",
        "**Version:** 4.0 (comprehensive — all basic-mouse + large advanced shaders)",
        "**Evaluator:** Evaluator Swarm",
        f"**Total Targets:** {data['total_targets']}",
        "**Focus:** Mouse-driven interactivity (not audio reactivity)",
        "",
        "## Changelog",
        "",
        "- **v1.0:** Initial list (114 targets, 39 false positives)",
        "- **v2.0:** Corrected false positives, mouse-depth classification (113 targets)",
        "- **v3.0:** Expanded with basic-mouse enhancements (+119 targets = 232)",
        "- **v4.0:** Comprehensive — ALL remaining basic-mouse shaders + large advanced shaders (+250 targets = 482)",
        "",
        "## Bucket Summary",
        "",
        "| Bucket | Count | Priority | Focus |",
        "|--------|-------|----------|-------|",
        f"| Huge Refactors | {data['buckets']['huge']} | P1 | Multi-pass split for >15KB shaders |",
        f"| Complex Upgrades | {data['buckets']['complex']} | P2–P3 | 5–15KB shaders, enhance/optimize |",
        f"| Advanced Hybrids | {data['buckets']['hybrids']} | P2 | New multi-technique mouse-driven shaders |",
        f"| Mouse-Interactive | {data['buckets']['mouse_interactive']} | P4–P5 | <5KB shaders, add/enhance mouse |",
        "",
        "### Mouse Depth Breakdown",
        "",
        "| Depth | Count | Meaning |",
        "|-------|-------|---------|",
        f"| **none** | {data['mouse_breakdown']['none']} | No mouse at all — add from scratch |",
        f"| **basic** | {data['mouse_breakdown']['basic']} | Reads position only — enhance with clicks/physics |",
        f"| **advanced** | {data['mouse_breakdown']['advanced']} | Has clicks/physics — optimize/refine |",
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
        md = "❌" if t["mouse_depth"] == "none" else ("△" if t["mouse_depth"] == "basic" else "✅")
        size = f"{t['size_bytes']/1024:.1f} KB" if t["size_bytes"] > 0 else "—"
        lines.append(f"| {t['priority']} | `{t['id']}` | {size} | {t['category']} | {md} | {t['notes']} |")

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
        md = "❌" if t["mouse_depth"] == "none" else ("△" if t["mouse_depth"] == "basic" else "✅")
        size = f"{t['size_bytes']/1024:.1f} KB" if t["size_bytes"] > 0 else "—"
        lines.append(f"| {t['priority']} | `{t['id']}` | {size} | {t['category']} | {md} | {t['notes']} |")

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
        md = "❌" if t["mouse_depth"] == "none" else ("△" if t["mouse_depth"] == "basic" else "✅")
        size = f"{t['size_bytes']/1024:.1f} KB" if t["size_bytes"] > 0 else "—"
        lines.append(f"| {t['priority']} | `{t['id']}` | {size} | {t['category']} | {md} | {t['notes']} |")

    lines.extend([
        "",
        "---",
        "",
        "## Legend",
        "",
        "- **❌** = No mouse usage — add from scratch",
        "- **△** = Basic mouse (position only) — enhance with clicks, physics, spring",
        "- **✅** = Advanced mouse — optimize/refine performance and alpha",
        "",
    ])

    return "\n".join(lines)


def rebuild_registry(pb_data, all_targets):
    with open("swarm-outputs/phase-a-eval-scores.json") as f:
        pa_scores = {r["id"]: r for r in json.load(f)}

    with open("swarm-outputs/shader_scan_results.json") as f:
        scan = {r["id"]: r for r in json.load(f)}

    total = len(scan)
    with_mouse = sum(1 for r in scan.values() if r.get("uses_mouse_expanded", r.get("uses_mouse", False)))

    lines = [
        "# Living Master Upgrade Target Registry",
        "",
        "**Generated:** 2026-04-18",
        "**Evaluator:** Evaluator Swarm",
        "**Purpose:** Central registry tracking all shader upgrade targets across Phase A, Phase B, and Phase C.",
        "",
        "---",
        "",
        "## Stats Dashboard",
        "",
        "| Metric | Value |",
        "|--------|-------|",
        f"| **Total Library Shaders** | {total} |",
        f"| **Phase A Completed** | {len(pa_scores)}/81 (53.1%) |",
        f"| **Phase B Pending** | {pb_data['total_targets']}/{pb_data['total_targets']} (100.0%) |",
        f"| **Shaders With Mouse** | {with_mouse} ({with_mouse/total*100:.1f}%) |",
        f"| **Shaders Without Mouse** | {total - with_mouse} ({(total-with_mouse)/total*100:.1f}%) |",
        "",
        "### Phase A Grade Distribution",
        "",
        "| Grade | Count |",
        "|-------|-------|",
    ]
    grades = {"A": 0, "B": 0, "C": 0, "D": 0, "F": 0}
    for r in pa_scores.values():
        grades[r["grade"]] = grades.get(r["grade"], 0) + 1
    for g in ["A", "B", "C", "D", "F"]:
        lines.append(f"| {g} | {grades.get(g, 0)} |")

    lines.extend([
        "",
        "### Phase B Bucket Summary",
        "",
        "| Bucket | Count | Priority Range |",
        "|--------|-------|----------------|",
        f"| Huge Refactors | {pb_data['buckets']['huge']} | P1 |",
        f"| Complex Upgrades | {pb_data['buckets']['complex']} | P2–P3 |",
        f"| Advanced Hybrids | {pb_data['buckets']['hybrids']} | P2 |",
        f"| Mouse-Interactive | {pb_data['buckets']['mouse_interactive']} | P4–P5 |",
        "",
        "### Phase B Mouse Depth Breakdown",
        "",
        "| Depth | Count | Meaning |",
        "|-------|-------|---------|",
        f"| **none** | {pb_data['mouse_breakdown']['none']} | No mouse at all — add from scratch |",
        f"| **basic** | {pb_data['mouse_breakdown']['basic']} | Reads position only — enhance with clicks/physics |",
        f"| **advanced** | {pb_data['mouse_breakdown']['advanced']} | Has clicks/physics — optimize/refine |",
        "",
        "---",
        "",
        "## Master Summary Table",
        "",
        "| Shader ID | Category | Size | Phase | Bucket | Status | Score | Mouse | Notes |",
        "|-----------|----------|------|-------|--------|--------|-------|-------|-------|",
    ])

    for sid, r in sorted(pa_scores.items(), key=lambda x: -x[1]["score"]):
        size = f"{r['size_bytes']/1024:.1f} KB"
        lines.append(f"| `{sid}` | {r['category']} | {size} | A | — | completed | {r['score']} | — | Grade {r['grade']} |")

    for t in all_targets:
        size = f"{t['size_bytes']/1024:.1f} KB" if t["size_bytes"] > 0 else "—"
        mouse = t.get("mouse_depth", "—")
        lines.append(f"| `{t['id']}` | {t['category']} | {size} | B | {t['bucket']} | pending | — | {mouse} | {t.get('notes', '')} |")

    lines.extend([
        "",
        "---",
        "",
        "## Maintenance Instructions",
        "",
        "### Status Values",
        "- `pending` — Not started",
        "- `in-progress` — Currently being worked on",
        "- `completed` — Done and verified",
        "- `skipped` — Intentionally deferred",
        "- `deferred` — Postponed to later phase",
        "",
        "### How to Update",
        "1. After completing a shader, change its Status from `pending` to `completed`",
        "2. After creating a new shader, append it to the appropriate Phase section",
        "3. Re-run `scripts/scan_shaders.py` after any WGSL changes to refresh mouse detection",
        "4. Update this file in-place — do not create duplicates",
        "",
    ])

    with open(REGISTRY_PATH, "w") as f:
        f.write("\n".join(lines))

    print(f"Registry rebuilt: {REGISTRY_PATH}")


if __name__ == "__main__":
    main()
