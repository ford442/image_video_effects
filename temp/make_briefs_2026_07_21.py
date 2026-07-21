#!/usr/bin/env python3
"""Generate 8 self-contained swarm briefs in swarm-tasks/kimi-briefs-2026-07-21/."""
import json
import os
import subprocess

ROOT = "/root/image_video_effects"
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-briefs-2026-07-21")
os.makedirs(OUT_DIR, exist_ok=True)

SHADERS = [
    {
        "id": "bitonic-sort",
        "category": "simulation",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. Focus on performance, structure, and polish without disturbing the core algorithm:",
        "techniques": [
            "Audio-reactive sort threshold/length modulation via plasmaBuffer[0].x (bass): let bass smoothly lower the sort threshold and modulate the sorted-span length.",
            "Subtle pre-sort domain warp: add a small-amplitude fbm offset on the sample coordinates before sorting, param-controlled so it can be dialed to zero.",
            "Edge-glow highlight on sorted-span boundaries: detect transitions between sorted and unsorted regions and add a restrained glow there.",
        ],
        "caution": "CAUTION: Preserve the bitonic sorting network exactly — the bank-conflict-free shared memory structure must stay intact. Do not restructure, reorder, or 'simplify' the network stages.",
        "params": [
            {"index": 0, "name": "Sort Threshold", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 1, "name": "Warp Amplitude", "default": 0.3, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 2, "name": "Edge Glow", "default": 0.4, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 3, "name": "Sort Length", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01},
        ],
    },
    {
        "id": "temporal-rgb-smear",
        "category": "visual-effects",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. Focus on input reactivity and feedback:",
        "techniques": [
            "Mouse-velocity-driven smear direction: track mouse delta with a spring-damper in extraBuffer so the smear direction follows fast mouse motion and settles smoothly.",
            "Feedback stability: clamp the accumulated dataTextureA value pre-write (lesson from the luma-echo-warp blowup — clamp pre-tint at ~1.2) so the feedback loop can never run away.",
            "Treble-reactive sparkle grain via plasmaBuffer[0].z: add fine animated grain whose intensity follows treble.",
        ],
        "caution": None,
        "params": [
            {"index": 0, "name": "Smear Length", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 1, "name": "Mouse Spring", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 2, "name": "Sparkle Grain", "default": 0.3, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 3, "name": "Feedback Clamp", "default": 1.2, "min": 1.0, "max": 2.0, "step": 0.05},
        ],
    },
    {
        "id": "elastic-chromatic",
        "category": "visual-effects",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. Focus on input reactivity and feedback:",
        "techniques": [
            "Spring-damper elastic lag on mouse position via extraBuffer: the chromatic source should overshoot on fast mouse moves and settle like a damped spring.",
            "Click shockwave: on mouse-down, spawn an expanding ring that temporarily boosts the chromatic split as it passes.",
            "IQ cosine palette tint option blended at low mix (~0.3) over the existing blackbody/split-tone grade — the original grade must remain dominant.",
        ],
        "caution": None,
        "params": [
            {"index": 0, "name": "Elasticity", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 1, "name": "Damping", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 2, "name": "Shockwave Boost", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 3, "name": "Palette Mix", "default": 0.3, "min": 0.0, "max": 1.0, "step": 0.01},
        ],
    },
    {
        "id": "data-slicer-interactive",
        "category": "interactive-mouse",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. Focus on the math and procedural structure of the effect:",
        "techniques": [
            "fbm-driven slice offset jitter, branchless: perturb each slice's displacement with smooth fbm noise using select/mix, no divergent branches.",
            "Audio band mapping: bass (plasmaBuffer[0].x) drives slice density, mids (plasmaBuffer[0].y) drive slice displacement magnitude.",
            "Mouse-down spawns a slice shockwave ripple using the u.ripples array: an expanding ring that locally amplifies slice offsets as it travels.",
        ],
        "caution": None,
        "params": [
            {"index": 0, "name": "Slice Density", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 1, "name": "Displacement", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 2, "name": "Jitter Amount", "default": 0.4, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 3, "name": "Shockwave Strength", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01},
        ],
    },
    {
        "id": "pixel-stretch-cross",
        "category": "interactive-mouse",
        "role": "Visualist",
        "role_intro": "You are the Visualist. Focus on look, color, and cinematic polish:",
        "techniques": [
            "Bass-pulse stretch amplitude via plasmaBuffer[0].x: stretch magnitude breathes with the bass envelope.",
            "Mouse velocity steers the stretch axis blend (horizontal<->vertical): fast horizontal motion favors H-stretch, vertical favors V-stretch.",
            "Subtle HDR bloom on stretch crossings with the ACES tone map preserved — bloom must be added before tonemapping, never after.",
        ],
        "caution": None,
        "params": [
            {"index": 0, "name": "Stretch Amplitude", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 1, "name": "Axis Blend", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 2, "name": "Bloom Intensity", "default": 0.3, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 3, "name": "Bass Response", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01},
        ],
    },
    {
        "id": "interactive-magnetic-ripple",
        "category": "interactive-mouse",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. Focus on the math and procedural structure of the effect:",
        "techniques": [
            "Worley-based magnetic field-line distortion layer: add a worley-noise field that bends the ripple sampling coordinates, mixed at ~0.3 and param-controlled.",
            "Spring-damped ripple envelope: ripples should overshoot and settle like a damped oscillator instead of a plain linear decay.",
            "Treble sparkle on ripple crests via plasmaBuffer[0].z: sharp highlights only on the crest maxima.",
        ],
        "caution": None,
        "params": [
            {"index": 0, "name": "Ripple Frequency", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 1, "name": "Field-Line Mix", "default": 0.3, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 2, "name": "Spring Damping", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 3, "name": "Treble Sparkle", "default": 0.3, "min": 0.0, "max": 1.0, "step": 0.01},
        ],
    },
    {
        "id": "luma-pixel-sort",
        "category": "post-processing",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. Focus on performance, structure, and polish without disturbing the core algorithm:",
        "techniques": [
            "Param-wired sort direction (angle): rotate the sample line via a param (0-1 mapped to 0-180 degrees) instead of a fixed axis.",
            "Audio-reactive luma threshold refinement: bass (plasmaBuffer[0].x) smoothly lowers the luma threshold so beats extend the sorted spans.",
            "Cosine-palette tint on sorted spans with a param-controlled mix so it can be blended subtly or disabled.",
        ],
        "caution": "CAUTION: Keep the 25-comparator sorting network and both early-exits intact — do not touch the compare-exchange sequence or the exit conditions.",
        "params": [
            {"index": 0, "name": "Luma Threshold", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 1, "name": "Sort Length", "default": 0.3, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 2, "name": "Sort Angle", "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 3, "name": "Palette Mix", "default": 0.3, "min": 0.0, "max": 1.0, "step": 0.01},
        ],
    },
    {
        "id": "pixel-depth-sort",
        "category": "post-processing",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. Focus on performance, structure, and polish without disturbing the core algorithm:",
        "techniques": [
            "Depth-weighted sort radius is already present — wire it to a param and add audio mids (plasmaBuffer[0].y) modulation on top.",
            "Temporal smear polish: clamp feedback writes (same luma-echo-warp lesson — clamp pre-tint at ~1.2) so the accumulation buffer stays stable.",
            "Chromatic edge accent on sort boundaries: subtle RGB fringing where sorted spans begin/end.",
        ],
        "caution": "CAUTION: Keep the sorting network and the LOD-distance logic intact — comparator sequence and the distance-based detail falloff must not change.",
        "params": [
            {"index": 0, "name": "Sort Radius", "default": 0.3, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 1, "name": "Mids Modulation", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 2, "name": "Chromatic Accent", "default": 0.2, "min": 0.0, "max": 1.0, "step": 0.01},
            {"index": 3, "name": "Feedback Clamp", "default": 1.2, "min": 1.0, "max": 2.0, "step": 0.05},
        ],
    },
]

REQUIRED_OUTPUT = """## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional — only declare it if the shader already uses it.
"""

MANDATORY_BULLETS = [
    "Wire exactly 4 slider params via u.zoom_params.x/y/z/w, replacing the 4 most important hardcoded constants. Add them to the JSON updatedParams with index 0-3, sensible name/default/min/max/step.",
    "Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.",
]

for spec in SHADERS:
    sid = spec["id"]
    json_path = os.path.join(ROOT, "shader_definitions", spec["category"], f"{sid}.json")
    wgsl_path = os.path.join(ROOT, "public", "shaders", f"{sid}.wgsl")

    with open(json_path) as f:
        meta = json.load(f)
    with open(wgsl_path) as f:
        wgsl = f.read().rstrip("\n")

    wc = int(subprocess.check_output(["wc", "-l", wgsl_path]).split()[0])
    lo, hi = wc + 50, wc + 90

    # Build updated JSON: keep all fields as-is, add updatedParams + updated
    out_meta = dict(meta)
    out_meta["updatedParams"] = spec["params"]
    out_meta["updated"] = True
    json_str = json.dumps(out_meta, indent=2)

    bullets = list(spec["techniques"]) + MANDATORY_BULLETS
    if spec["caution"]:
        bullets.append(spec["caution"])

    parts = []
    parts.append(f"# Swarm Brief: {sid}\n")
    parts.append(f"**Role:** {spec['role']}")
    parts.append(f"**Name:** {meta['name']}")
    parts.append(f"**Category:** {spec['category']}")
    parts.append(f"**Description:** {meta['description']}")
    parts.append(f"**Current lines:** {wc}")
    parts.append(f"**Target lines:** {lo}\u2013{hi} (expand by +50 to +90)")
    parts.append("\n## Role Instructions\n")
    parts.append(spec["role_intro"])
    for b in bullets:
        parts.append(f"- {b}")
    parts.append("\n" + REQUIRED_OUTPUT)
    parts.append("## JSON Parameters / Controls\n")
    parts.append("```json\n" + json_str + "\n```")
    parts.append("\n## Current WGSL Code\n")
    parts.append("```wgsl\n" + wgsl + "\n```\n")

    brief = "\n".join(parts)
    out_path = os.path.join(OUT_DIR, f"{sid}.md")
    with open(out_path, "w") as f:
        f.write(brief)
    print(f"wrote {out_path} ({brief.count(chr(10))} lines, wgsl {wc} lines)")
