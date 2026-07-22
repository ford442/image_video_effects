#!/usr/bin/env python3
"""Generate 8 self-contained generative swarm briefs in swarm-tasks/kimi-generative-briefs-2026-07-22-b12/.

Batch 12 (generative edition): targets already read u.zoom_params.x-w in WGSL and
declare 4 JSON params, but updatedParams is empty -> no UI sliders wired.
Theme: formalize updatedParams (same ids/defaults -> preset compat), make each slider
drive meaningful shader-specific constants (replace generic boilerplate mappings),
+ 2-3 shader-specific techniques, expansion +50-90 lines, gate green.
"""
import json
import os
import subprocess

ROOT = "/root/image_video_effects"
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-generative-briefs-2026-07-22-b12")
os.makedirs(OUT_DIR, exist_ok=True)

SHADERS = [
    {
        "id": "emergent-calligraphic-weave",
        "role": "Visualist",
        "role_intro": "You are the Visualist. Focus on the sumi-e brush feel: ink, stroke texture, and edge chromatics:",
        "techniques": [
            "Replace the generic applyGenerativePrimaryControls boilerplate mapping with real brush constants: stroke width, ink viscosity, dry-brush threshold, and chaos amplitude must each be visibly driven by one slider (ids/defaults unchanged).",
            "Curl-noise stroke direction field: advect the stroke direction with a low-frequency divergence-free curl field so strokes flow like brushed calligraphy instead of lying on a static field.",
            "Dry-brush edge sparkle: treble-driven (plasmaBuffer[0].z) ink-grain texture on stroke edges, masked by the dry-brush threshold so fast strokes sizzle.",
        ],
        "caution": None,
    },
    {
        "id": "bubble-chamber",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. Focus on the particle-physics flavor: tracks, ionization, and field response:",
        "techniques": [
            "Ionization falloff: bubble-track brightness decays along trail length with a Bragg-curve-like bump near the end — tracks read as physical particles, not uniform worms.",
            "Mouse Lorentz deflection: nearby tracks curve around the cursor like a magnetic pole (falloff ~1/r, strength by mouse-down), so moving the mouse visibly bends the chamber.",
            "Clean up the param double-duty: zoom_params.z currently drives BOTH turbulence and spawn_rate — separate concerns so Scale controls spatial scale and spawn density follows Intensity/Detail sensibly; keep ids/defaults.",
            "Feedback clamp on the trail accumulation pre-tint at ~1.2 (luma-echo-warp lesson).",
        ],
        "caution": "CAUTION: bubble-chamber has temporal feedback (decay) — keep the divergence-free advection intact and clamp the accumulation so trails cannot blow out.",
    },
    {
        "id": "generative-turing-veins",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This reaction-diffusion shader's sliders are DEAD — the JSON declares 4 params but the WGSL never reads u.zoom_params. Wire them for real:",
        "techniques": [
            "WIRE THE SLIDERS (priority 1): Primary Scale -> RD kernel radius, Secondary Scale -> second RD layer scale, Feed Rate -> Gray-Scott feed parameter (stay inside the striped-vein regime ~0.03-0.07), Vein Glow -> bioluminescent gain on vein ridges. Keep ids/defaults.",
            "Bass nutrient pulse: plasmaBuffer[0].x modulates the feed rate in a slow radial wave from center so veins visibly grow on beats.",
            "Click seeding: mouse-down drops a gaussian activator seed (rising-edge tracked via extraBuffer[5]) so users can plant new vein colonies.",
        ],
        "caution": "CAUTION: extraBuffer[0..4] is reserved: use extraBuffer[5]+ only, in-bounds. Keep the multi-scale RD update stable (clamp activator/inhibitor to sane ranges after update).",
    },
    {
        "id": "molten-gold",
        "role": "Visualist",
        "role_intro": "You are the Visualist. Make it feel like actual liquid metal at ~1337K (the file already cites real gold physics):",
        "techniques": [
            "True blackbody temperature ramp: map the flow-field 'temperature' through a blackbody color function (deep red -> gold -> white-hot) instead of the current ad-hoc ramp; keep the cited 1337K physics comment honest.",
            "Fresnel specular on flow ridges: compute a pseudo-normal from the height field gradient and add view-dependent fresnel highlights scaled by the Specular slider.",
            "Bass heat waves: plasmaBuffer[0].x drives slow rippling heat bands through the melt; clamp any glow accumulation pre-tint at ~1.2 (luma-echo-warp lesson).",
        ],
        "caution": None,
    },
    {
        "id": "phase-memory-weave",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. Polish the Ginzburg-Landau phase-field rendering and protect the memory loop:",
        "techniques": [
            "Opalescent interface iridescence: thin-film cosine-palette color keyed on the local phase gradient magnitude (mix ~0.3), so domain boundaries shimmer like opal; base palette stays dominant.",
            "Memory-loop stability: clamp the multi-scale memory accumulation pre-tint at ~1.2 (luma-echo-warp lesson) and add a tiny epsilon decay so the memory buffer cannot latch.",
            "Mouse thermal pulse: on mouse-down, emit an expanding gaussian heat ring that locally forces phase change where it passes (rising-edge via extraBuffer[5]).",
        ],
        "caution": "CAUTION: extraBuffer[0..4] reserved (use [5]+ in-bounds). Preserve the fast-atan2/branchless optimizations already in the file — it was just optimized.",
    },
    {
        "id": "atmos_volumetric_fog",
        "role": "Visualist",
        "role_intro": "You are the Visualist. Focus on light transport: shafts, scattering color, and aerial perspective:",
        "techniques": [
            "Mouse-anchored god rays: sharpen the existing god-ray feature into visible light shafts radiating from the mouse light position, masked by fog density and the God Rays slider.",
            "fbm density modulation: break the uniform fog with 2-3 octave fbm density so shafts and layers read volumetric instead of flat.",
            "Treble sparkle motes: sparse animated dust motes (hash sparkle) visible inside bright shafts, treble-scaled; clamp temporal feedback pre-tint at ~1.2 (luma-echo-warp lesson).",
        ],
        "caution": None,
    },
    {
        "id": "mycelium-network",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. Make the network respond like a living organism:",
        "techniques": [
            "Nutrient pulse packets: on mouse-down, launch a visible pulse that travels outward along the branch network from the click point (rising-edge via extraBuffer[5]), brightening hyphae as it passes.",
            "Growth tropism: bias the branch growth direction field toward the mouse so the colony leans toward the cursor, Pulse Speed slider controlling the lean rate.",
            "Bass heartbeat: plasmaBuffer[0].x syncs a network-wide gentle pulse; worley hyphal density variation so strands vary in thickness.",
        ],
        "caution": "CAUTION: extraBuffer[0..4] reserved (use [5]+ in-bounds). Keep the existing anti-moire dither intact.",
    },
    {
        "id": "gen_julia_set",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. Polish the fractal rendering: interior detail, AA, and audio morphing:",
        "techniques": [
            "Audio c-morph: drive the Julia constant c along a slow Lissajous path whose amplitude follows bass (plasmaBuffer[0].x) — the set breathes with the music; mouse still overrides on drag.",
            "Interior filaments: color the interior (non-escaping) region with fine filament detail (derivative-of-iteration texture) instead of flat black.",
            "Hash-jitter AA: 2-sample rotated-grid jitter per pixel to smooth the orbit-trap bands; clamp any temporal accumulation pre-tint at ~1.2 (luma-echo-warp lesson).",
        ],
        "caution": "CAUTION: keep the smooth-iteration formula (mu = i - log2(log2|z|)) and the 3 orbit traps mathematically intact.",
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
    "Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.",
    "Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.",
    "Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.",
]

for spec in SHADERS:
    sid = spec["id"]
    json_path = os.path.join(ROOT, "shader_definitions", "generative", f"{sid}.json")
    wgsl_path = os.path.join(ROOT, "public", "shaders", f"{sid}.wgsl")

    with open(json_path) as f:
        meta = json.load(f)
    with open(wgsl_path) as f:
        wgsl = f.read().rstrip("\n")

    wc = int(subprocess.check_output(["wc", "-l", wgsl_path]).split()[0])
    lo, hi = wc + 50, wc + 90

    # updatedParams mirror the existing params (id/name/default/min/max/step preserved)
    upd = []
    for i, p in enumerate(meta["params"][:4]):
        upd.append({
            "index": i,
            "name": p["name"],
            "default": p["default"],
            "min": float(p.get("min", 0.0)),
            "max": float(p.get("max", 1.0)),
            "step": p.get("step", 0.01),
        })

    out_meta = dict(meta)
    out_meta["updatedParams"] = upd
    out_meta["updated"] = True
    json_str = json.dumps(out_meta, indent=2)

    bullets = list(spec["techniques"]) + MANDATORY_BULLETS
    if spec["caution"]:
        bullets.append(spec["caution"])

    parts = []
    parts.append(f"# Swarm Brief: {sid}\n")
    parts.append(f"**Role:** {spec['role']}")
    parts.append(f"**Name:** {meta['name']}")
    parts.append("**Category:** generative")
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
