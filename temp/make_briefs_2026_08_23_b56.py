#!/usr/bin/env python3
"""Batch 56 (fixed cohort): fast motion + psychedelic color — tracker #475–482."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_briefs_common import MANDATORY_BULLETS, REQUIRED_OUTPUT, extract_params  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-briefs-2026-08-23-b56")
os.makedirs(OUT_DIR, exist_ok=True)

COHORT = [
    ("cyber-slit-scan", 475, "interactive-mouse"),
    ("hyb-spectral-fbm-displace", 476, "hybrid"),
    ("infinite-zoom-lens", 477, "distortion"),
    ("phosphor-magnifier", 478, "interactive-mouse"),
    ("quantum-prism", 479, "interactive-mouse"),
    ("warp_drive", 480, "visual-effects"),
    ("chromatic-focus-interactive", 481, "visual-effects"),
    ("liquid-warp-interactive", 482, "distortion"),
]

THEME = (
    "Fast motion + psychedelic color: two shader-specific continuous-motion structures, "
    "held-pointer response, capped click ripples, analytic phases (no frame-hash strobing), "
    "oil-slick / liquid-rainbow / phosphor-aurora palettes."
)

for sid, tracker, category in COHORT:
    jpath = os.path.join(ROOT, "shader_definitions", category, f"{sid}.json")
    meta = json.load(open(jpath))
    params = extract_params(meta)
    param_lines = "\n".join(
        f"- **{p['name']}** default={p['default']} → `u.zoom_params.{['x','y','z','w'][i]}`"
        for i, p in enumerate(params)
    )
    body = f"""# Batch 56 — #{tracker} `{sid}`

**Theme:** {THEME}

## Params (saved-preset contract — do not rename/re-default)
{param_lines}

## Mandatory
{chr(10).join('- ' + b for b in MANDATORY_BULLETS)}

{REQUIRED_OUTPUT}
"""
    with open(os.path.join(OUT_DIR, f"{sid}.md"), "w") as f:
        f.write(body)

print(f"Wrote {len(COHORT)} briefs to {OUT_DIR}")
