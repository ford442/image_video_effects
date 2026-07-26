#!/usr/bin/env python3
"""Generate batch 19 briefs using make_briefs_common pool scanner."""

import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
from make_briefs_common import (  # noqa: E402
    MANDATORY_BULLETS,
    REQUIRED_OUTPUT,
    extract_params,
    pick_next_batch,
    scan_empty_updated_params_pool,
    wgsl_line_count,
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-generative-briefs-2026-07-26-b19")
TRACKER = os.path.join(ROOT, "agents", "weekly_upgrade_swarm.md")
os.makedirs(OUT_DIR, exist_ok=True)

BATCH_IDS = pick_next_batch(8, tracker_path=TRACKER)
print("Batch 19 pool picks:", BATCH_IDS)

ROLES = ["Visualist", "Algorithmist", "Interactivist", "Optimizer"]


def write_brief(sid: str, role: str, idx: int) -> None:
    json_path = os.path.join(ROOT, "shader_definitions", "generative", f"{sid}.json")
    wgsl_path = os.path.join(ROOT, "public", "shaders", f"{sid}.wgsl")
    with open(json_path) as f:
        meta = json.load(f)
    with open(wgsl_path) as f:
        wgsl = f.read().rstrip("\n")
    wc = wgsl_line_count(wgsl_path)
    lo, hi = wc + 50, wc + 90
    upd = [
        {
            "index": i,
            "name": p["name"],
            "default": p["default"],
            "min": p["min"],
            "max": p["max"],
            "step": p["step"],
        }
        for i, p in enumerate(extract_params(meta))
    ]
    out_meta = dict(meta)
    out_meta["updatedParams"] = upd
    out_meta["updated"] = True
    bullets = [
        f"Formalize 4 updatedParams from EXISTING param ids (saved-preset contract — no renames).",
        "Wire each u.zoom_params.x/y/z/w to shader-specific constants; evict any applyGenerativePrimaryControls boilerplate.",
        "Add bass/mid/treble via plasmaBuffer[0] (not zoom_config.w mouse-down or config.y ripple count).",
        "If using extraBuffer for persistent state: [133..255] ONLY ([0..4] reserved, [5..132] engine FFT bins).",
        "Sim/feedback state → dataTextureA; host copies A→C each frame.",
    ] + MANDATORY_BULLETS
    parts = [
        f"# Swarm Brief: {sid}\n",
        f"**Role:** {role}",
        f"**Name:** {meta.get('name', sid)}",
        "**Category:** generative",
        f"**Current lines:** {wc}",
        f"**Target lines:** {lo}–{hi}",
        "\n## Role Instructions\n",
        f"You are the {role}. Upgrade this generative shader: preserve its visual identity, fix dead sliders/fake audio, expand +50–90 lines.",
    ]
    for b in bullets:
        parts.append(f"- {b}")
    parts.append("\n" + REQUIRED_OUTPUT)
    parts.append("## JSON Parameters / Controls\n")
    parts.append("```json\n" + json.dumps(out_meta, indent=2) + "\n```")
    parts.append("\n## Current WGSL Code\n")
    parts.append("```wgsl\n" + wgsl + "\n```\n")
    out_path = os.path.join(OUT_DIR, f"{sid}.md")
    with open(out_path, "w") as f:
        f.write("\n".join(parts))
    print(f"wrote {out_path}")


for i, sid in enumerate(BATCH_IDS):
    write_brief(sid, ROLES[i % len(ROLES)], i)

pool = scan_empty_updated_params_pool(tracker_path=TRACKER)
print(f"Pool remaining after picks: {len(pool)}")
