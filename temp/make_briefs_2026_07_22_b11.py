#!/usr/bin/env python3
"""Generate 8 self-contained generative swarm briefs in swarm-tasks/kimi-generative-briefs-2026-07-22-b11/.

Batch 11 (generative edition): targets already read u.zoom_params.x-w in WGSL and
declare 4 JSON params, but updatedParams is empty -> no UI sliders wired.
Theme: formalize updatedParams (same ids/defaults -> preset compat), make each slider
drive meaningful shader-specific constants (replace generic boilerplate mappings),
+ 2-3 shader-specific techniques, expansion +50-90 lines, gate green.
"""
import json
import os
import subprocess

ROOT = "/root/image_video_effects"
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-generative-briefs-2026-07-22-b11")
os.makedirs(OUT_DIR, exist_ok=True)

SHADERS = [
    {
        "id": "gen_cyclic_automaton",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. Focus on the excitable-media dynamics and wave readability:",
        "techniques": [
            "Wavefront leading-edge tracer: use the refractoryProgress gradient across neighbors to detect the firing wave's leading edge and render a thin bright ring there — propagating waves become legible instead of a uniform glow.",
            "Treble ignition sparks: plasmaBuffer[0].z raises the spontaneous-ignition probability in a fine hash-noise pattern so hi-hats seed new wave centers across the field.",
            "Directional mouse painting: while mouse-down, bias ignition along the mouse motion direction (compare current mouse to previous via extraBuffer[5..7]) so dragging draws cardiac-style wavefronts, not just radial blobs.",
        ],
        "caution": "CAUTION: The Greenberg-Hastings state machine (resting=0, firing=1, refractory>=2 with the select-chain) must stay logically intact — upgrade around it, don't rewrite the rule. extraBuffer[0..4] is reserved: use extraBuffer[5]+ only, in-bounds.",
    },
    {
        "id": "holographic_interference",
        "role": "Visualist",
        "role_intro": "You are the Visualist. Focus on the laser-optics feel: speckle, parallax, and chromatic richness:",
        "techniques": [
            "Animated laser speckle: high-frequency hash speckle modulating fringe intensity (treble-scaled via plasmaBuffer[0].z) — real holograms shimmer; flat fringes read fake.",
            "IQ cosine palette fringe tint at low mix (~0.3) keyed on film thickness, so thin-film hues sweep holographically; the original fringe colors stay dominant.",
            "Mouse parallax: mouse position tilts the reference-beam angle so the interference field shifts with viewpoint like a real holographic plate.",
        ],
        "caution": None,
    },
    {
        "id": "holographic-crystal",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. Focus on anti-aliasing quality, structure, and polish:",
        "techniques": [
            "Strengthen the anti-moire: add a per-pixel hash phase dither on the interference phase to kill residual banding/aliasing on high-frequency fringes.",
            "Worley facet variation: perturb per-facet normals with a low-frequency worley field so facets catch light unevenly like cut glass instead of stamping uniform planes.",
            "Treble facet glint: sharp sparkle highlights on facet edges driven by plasmaBuffer[0].z, masked by facet-edge proximity.",
        ],
        "caution": None,
    },
    {
        "id": "gen_wave_equation",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. Focus on solver correctness first, then wave quality:",
        "techniques": [
            "FIX THE FEEDBACK BUG FIRST: the sim reads (height, velocity) from dataTextureC.rg but writes finalColor into dataTextureA — so the feedback carries color, not state. Write the sim state (height, velocity, energy) into dataTextureA so the A->C engine copy makes the solver actually iterate; keep the rendered color in writeTexture (and optionally pack color into unused channels).",
            "Upgrade the 4-point Laplacian to a 9-point (add diagonals, weights 1 ortho / 0.5 diag, renormalized) for more isotropic, less grid-aligned wave propagation.",
            "Click droplets: deposit a gaussian height pulse on mouse-down rising edge (tracked via extraBuffer[5]) instead of continuous forcing while held — drops radiate clean rings.",
        ],
        "caution": "CAUTION: engine contract — when dataTextureA is written, A->C copy wins (B then A). The solver state MUST live in dataTextureA. extraBuffer[0..4] reserved; use [5]+ in-bounds. Keep the Klein-Gordon/Sine-Gordon nonlinear term working after the state fix.",
    },
    {
        "id": "plasma-orb",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. Focus on the MHD/tokamak structure and polish without disturbing the core field math:",
        "techniques": [
            "Worley F2-F1 arc ridges: add secondary lightning arcs along worley ridge lines between core and shell, arcChaos-scaled — cheap, dramatic plasma branching.",
            "Spring-damper orb drift: the orb center eases toward the mouse with damped overshoot (state in extraBuffer[5..8]) so fast mouse moves make it lunge and settle like a contained plasma ball.",
            "Corona shimmer: mids (plasmaBuffer[0].y) drive a slow rotating shimmer on the outer glow; clamp any accumulated glow pre-tint at ~1.2 (luma-echo-warp lesson).",
        ],
        "caution": "CAUTION: extraBuffer[0..4] is reserved: use extraBuffer[5]+ only, in-bounds.",
    },
    {
        "id": "plasma-jet-stream",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. Focus on the jet shear-layer physics and boundary structure:",
        "techniques": [
            "Chromatic shear fringe: at jet boundaries (high velocity-gradient regions) add subtle RGB dispersion — shear layers get a prismatic edge.",
            "Bass surge wave: plasmaBuffer[0].x launches a slow radial velocity pulse from the stream origin that temporarily widens spread as it passes, so beats visibly pump the jets.",
            "Strengthen the divergence-free perturbation: derive the turbulence offset from a curl of a noise potential (finite-difference gradient rotated 90 deg) instead of raw noise — jets bend without artificial sources/sinks.",
        ],
        "caution": None,
    },
    {
        "id": "sacred-geometry-torus",
        "role": "Visualist",
        "role_intro": "You are the Visualist. Lean into the sacred-geometry symbolism: Fibonacci, phi, and luminous line work:",
        "techniques": [
            "Fibonacci dot lattice: overlay a phyllotaxis (golden-angle) point lattice projected onto the torus surface, param-scaled by Phi Layers — dots sit at strand intersections like a seed-of-life grid.",
            "Cosine-palette strand hue cycling: each knot strand gets a slow hue offset by strand index (IQ palette, mix ~0.35), original coloring dominant.",
            "Trail clamp + polish: clamp temporal glow accumulation pre-tint at ~1.2 (luma-echo-warp lesson) and add a restrained bloom lift on strand crossings.",
        ],
        "caution": None,
    },
    {
        "id": "acoustic-string-theory",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. Make the strings feel played, not just drawn:",
        "techniques": [
            "Pluck on click: mouse-down rising edge (tracked via extraBuffer[5]) excites the nearest string with a gaussian displacement that decays by Tension — clicks pluck, they don't just glow.",
            "Audio spectrum drive: use plasmaBuffer bands (bass/mids/treble) to weight per-string harmonic amplitudes across the string index range — the instrument visibly tracks the music's spectrum.",
            "Spring-damper gravity well: the existing gravity well follows the mouse with damped overshoot (state in extraBuffer[6..9]); clamp the feedback-loop accumulation pre-tint at ~1.2 (luma-echo-warp lesson).",
        ],
        "caution": "CAUTION: extraBuffer[0..4] is reserved: use extraBuffer[5]+ only, in-bounds.",
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
