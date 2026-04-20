#!/usr/bin/env python3
"""Rebuild the living registry from updated data sources."""

import json
from pathlib import Path

SCAN_PATH = Path("/root/image_video_effects/swarm-outputs/shader_scan_results.json")
PA_SCORES_PATH = Path("/root/image_video_effects/swarm-outputs/phase-a-eval-scores.json")
PB_TARGETS_PATH = Path("/root/image_video_effects/swarm-outputs/phase-b-upgrade-targets.json")
REGISTRY_PATH = Path("/root/image_video_effects/swarm-outputs/upgrade-target-registry.md")


def main():
    with open(SCAN_PATH) as f:
        scan = {r["id"]: r for r in json.load(f)}

    with open(PA_SCORES_PATH) as f:
        pa_scores = {r["id"]: r for r in json.load(f)}

    with open(PB_TARGETS_PATH) as f:
        pb = json.load(f)

    total = len(scan)
    with_mouse = sum(1 for r in scan.values() if r.get("uses_mouse_expanded", r.get("uses_mouse", False)))
    no_mouse = total - with_mouse

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
        f"| **Phase B Pending** | {pb['total_targets']}/{pb['total_targets']} (100.0%) |",
        f"| **Shaders With Mouse** | {with_mouse} ({with_mouse/total*100:.1f}%) |",
        f"| **Shaders Without Mouse** | {no_mouse} ({no_mouse/total*100:.1f}%) |",
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
        f"| Huge Refactors | {pb['buckets']['huge']} | P1 |",
        f"| Complex Upgrades | {pb['buckets']['complex']} | P2–P3 |",
        f"| Advanced Hybrids | {pb['buckets']['hybrids']} | P2 |",
        f"| Mouse-Interactive | {pb['buckets']['mouse_interactive']} | P4–P5 |",
        "",
        "### Phase B Mouse Depth Breakdown",
        "",
        "| Depth | Count | Meaning |",
        "|-------|-------|---------|",
        f"| **none** | {pb['mouse_breakdown']['none']} | No mouse at all — primary target |",
        f"| **basic** | {pb['mouse_breakdown']['basic']} | Reads position only — enhance |",
        f"| **advanced** | {pb['mouse_breakdown']['advanced']} | Has clicks/physics — skip or refine |",
        "",
        "---",
        "",
        "## Master Summary Table",
        "",
        "| Shader ID | Category | Size | Phase | Bucket | Status | Score | Mouse | Notes |",
        "|-----------|----------|------|-------|--------|--------|-------|-------|-------|",
    ])

    # Phase A completed
    for sid, r in sorted(pa_scores.items(), key=lambda x: -x[1]["score"]):
        size_kb = r["size_bytes"] / 1024
        notes = f"Grade {r['grade']}"
        lines.append(f"| `{sid}` | {r['category']} | {size_kb:.1f} KB | A | — | completed | {r['score']} | — | {notes} |")

    # Phase B targets
    for t in pb["targets"]:
        size_kb = t["size_bytes"] / 1024 if t["size_bytes"] > 0 else "—"
        mouse = t.get("mouse_depth", "—")
        lines.append(f"| `{t['id']}` | {t['category']} | {size_kb} | B | {t['bucket']} | pending | — | {mouse} | {t.get('notes', '')} |")

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
        "### Source Files to Monitor",
        "- `public/shaders/*.wgsl` — WGSL source files",
        "- `shader_definitions/*/*.json` — Shader metadata",
        "- `swarm-outputs/phase-a-eval-scores.json` — Phase A scores",
        "- `swarm-outputs/phase-b-upgrade-targets.json` — Phase B targets",
        "",
    ])

    with open(REGISTRY_PATH, "w") as f:
        f.write("\n".join(lines))

    print(f"Registry rebuilt: {REGISTRY_PATH}")
    print(f"Total entries: {len(pa_scores) + len(pb['targets'])}")


if __name__ == "__main__":
    main()
