#!/usr/bin/env python3
"""Generate 8 self-contained generative swarm briefs in swarm-tasks/kimi-generative-briefs-2026-07-22/.

Batch 10 (generative edition): targets already read u.zoom_params.x-w in WGSL and
declare 4 JSON params, but updatedParams is empty -> no UI sliders wired.
Theme: formalize updatedParams (same ids/defaults -> preset compat), make each slider
drive meaningful shader-specific constants (replace generic boilerplate mappings),
+ 2-3 shader-specific techniques, expansion +50-90 lines, gate green.
"""
import json
import os
import subprocess

ROOT = "/root/image_video_effects"
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-generative-briefs-2026-07-22")
os.makedirs(OUT_DIR, exist_ok=True)

SHADERS = [
    {
        "id": "fire_smoke_volumetric",
        "role": "Visualist",
        "role_intro": "You are the Visualist. Focus on color, lighting, and visual richness:",
        "techniques": [
            "Worley-noise ember particles: add rising ember sparks (animated worley cells scrolling upward) masked by the fire shape and tinted by the existing chromatic temperature gradient. Restrained — embers must not dominate the smoke.",
            "Feedback stability: clamp the temporal smoke accumulation path (prevSmoke * decay) pre-write at ~1.2 (luma-echo-warp lesson) so the smoke buffer can never run away or lock to white.",
            "Treble-reactive edge flicker: modulate the fire silhouette turbulence amplitude with plasmaBuffer[0].z so the flame edge crackles on high-frequency content.",
        ],
        "caution": None,
    },
    {
        "id": "multi-scale-evolutionary-cellular-gardens",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. Focus on the simulation's depth and emergent behavior:",
        "techniques": [
            "Upgrade the 4-neighbor sampling to full 8-neighbor (add diagonals) with distance-correct weights (1.0 orthogonal, ~0.707 diagonal) — the species/resource diffusion gets visibly smoother.",
            "Worley colony-border accent: detect species territory boundaries (where s1 and s2 dominance flips between neighbors) and add a restrained bioluminescent glow line there.",
            "Replace the generic applyGenerativePrimaryControls boilerplate mapping with shader-specific control: sliders must drive real sim constants (mutation rate, competition, fertility, nurture radius) — the boilerplate intensity/speed/contrast remapping is not meaningful control for a CA sim.",
        ],
        "caution": "CAUTION: dataTextureA carries the sim state (s1, s2, resource) and dataTextureC is the readback — keep the channel layout and the update ordering intact, only strengthen the rules around it.",
    },
    {
        "id": "recursive-ancestral-terrains",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. Focus on the generational/lineage structure of the terrain:",
        "techniques": [
            "IQ cosine palette for generation tinting: blend a cosine-palette hue (mix ~0.3) keyed on lineage depth so ancestry reads as color strata; original grading must remain dominant.",
            "Add one ridged-fbm octave (abs-folded noise) to the terrain height field for sharper mountain crests — layered under the existing fbm, param-scaled so it can be dialed down.",
            "Bass mutation waves: make the bass-driven mutation rate spatial — a slow radial wave expanding from the mouse position (or center if no mouse) modulates mutation locally, so beats ripple lineage change across the terrain.",
        ],
        "caution": None,
    },
    {
        "id": "neural-synapse-web",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. Focus on input reactivity and feedback:",
        "techniques": [
            "Click pulse wave: on mouse-down, spawn an expanding ring (tracked in extraBuffer with frame-stamped origin) that temporarily boosts signal gain / synapse brightness as it sweeps past nodes.",
            "Spring-damper mouse attractor via extraBuffer: node attraction point follows the mouse with damped overshoot instead of raw position — fast mouse moves make the web lunge then settle.",
            "Treble-reactive synapse sparkle: fine animated grain on active connections via plasmaBuffer[0].z, masked by signal strength so only firing synapses shimmer.",
        ],
        "caution": "CAUTION: extraBuffer[0..4] is reserved by the engine — use extraBuffer[5] and above only (indexed writes must stay in-bounds).",
    },
    {
        "id": "magnetic-flux-garden",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. Focus on performance, structure, and polish without disturbing the core algorithm:",
        "techniques": [
            "Curl-noise perturbation on the field lines: add a small-amplitude curl (derivative-of-noise) offset to the flux-line sampling so lines weave organically instead of lying perfectly smooth.",
            "IQ cosine palette blend on the bloom layer at low mix (~0.3), param-scaled; the original field-line coloring stays dominant.",
            "Feedback clamp on any temporal accumulation write (clamp pre-tint at ~1.2, luma-echo-warp lesson) so the bloom trails cannot blow out over time.",
        ],
        "caution": None,
    },
    {
        "id": "generative-psy-swirls",
        "role": "Visualist",
        "role_intro": "You are the Visualist. Focus on color, motion feel, and psychedelic richness:",
        "techniques": [
            "Domain-warped swirl: add a small fbm domain offset to the UV before the twist is applied, so the swirl arms bend and breathe instead of rotating rigidly.",
            "Chromatic hue separation driven by mids (plasmaBuffer[0].y): stagger the per-layer hue rotation slightly by audio mids so layers fan out into rainbow fringes on musical peaks.",
            "Feedback clamp on the temporal layer memory write (clamp pre-tint at ~1.2, luma-echo-warp lesson) — this shader accumulates color across frames and is exactly the blowup pattern.",
        ],
        "caution": None,
    },
    {
        "id": "4d-projection-dream-weavers",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. Focus on the 4D math and navigation smoothness:",
        "techniques": [
            "Spring-damper smoothing on the 4D mouse rotation angles via extraBuffer (store smoothed angle + velocity per axis): raw mouse jumps become smooth eased rotations through the 4D slice.",
            "Worley dream-dust layer: sparse animated worley sparkle suspended in the projected 3D slice, depth-faded and treble-modulated (plasmaBuffer[0].z).",
            "Cosine-palette dimension tint: subtle per-dimension hue shift (mix ~0.25) so the chromatic dimension separation reads richer; original palette dominant.",
        ],
        "caution": "CAUTION: extraBuffer[0..4] is reserved by the engine — use extraBuffer[5] and above only (indexed writes must stay in-bounds).",
    },
    {
        "id": "symbiotic-light-propagation-networks",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. Focus on input reactivity and feedback:",
        "techniques": [
            "Mouse seeding pulse: on mouse-down, spawn an expanding growth ring (frame-stamped in extraBuffer) that locally boosts network growth where it passes — seeds feel planted, not just held.",
            "Bass glow pulse as a spatial wave: make plasmaBuffer[0].x drive a slow radial glow wave from the seed point instead of a flat global gain, so beats propagate along the network.",
            "Feedback clamp on the temporal light accumulation (clamp pre-tint at ~1.2, luma-echo-warp lesson) so glow trails stabilize instead of saturating.",
        ],
        "caution": "CAUTION: extraBuffer[0..4] is reserved by the engine — use extraBuffer[5] and above only (indexed writes must stay in-bounds).",
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
