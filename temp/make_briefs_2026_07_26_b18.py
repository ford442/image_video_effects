#!/usr/bin/env python3
"""Generate 8 self-contained generative swarm briefs in swarm-tasks/kimi-generative-briefs-2026-07-26-b18/.

Batch 18 (generative edition 9): same theme as Batches 10-15 - formalize updatedParams
from EXISTING param ids/names/defaults (saved-preset contract, no renames), make each
slider drive meaningful shader-specific constants, + 2-3 tailored techniques each,
expansion +50-90 lines, gate green.

ENGINE UNIFORM TRUTH (verified src/renderer/UniformBuffer.ts + webgpu/frame.ts, 2026-07-26):
  config      = [time, rippleCount, resW, resH]
  zoom_config = [time, mouseX, mouseY, mouseDown]  -> mouse = .yz, down = .w
  ripples guard: min(u32(u.config.y), 50u)
NOTE: docs/BINDING_CONTRACT.md claims config.y=delta_time - STALE, trust the TS source.

Recon notes baked in (2026-07-26, Batch 16):
- phoenix: audio = u.config.y (ripple count, near-constant - audio dead); no tonemap;
  dataTextureA write-only; controls[] schema with uniformMapping, ONLY 2 params.
- liquid_magnetic_ferro: Viscosity (z) DEAD slider; audioPulse = zoom_config.w
  (mouse-down mislabeled); NaN risk normalize(uv-0.5) at screen center.
- bio_lenia_continuous: spawn gate uses config.y>0 (true after any click forever);
  audioPulse = zoom_config.w mislabeled; sim-state feedback discipline is GOOD.
- bioluminescent-bloom: ACES applied TWICE (washes highlights); stale struct comment.
- chrono-voronoi-mycelium: ALL 4 sliders trapped in applyGenerativePrimaryControls
  boilerplate (all mislabeled); duplicate dataTextureC read; redundant B write.
- cosmic-jellyfish: temporal feedback computed but NEVER DISPLAYED (dead trails);
  writeDepthTexture stores flat 0.0 (clobbers chain depth); no audio; no tonemap.
- spec-quaternion-julia: Detail Level (w) mislabeled (only a hue divisor);
  background alpha unclamped (orbitTrap/10 up to ~100); no audio.
- tornado-vortex: vRadial/vVertical computed but never used (dead physics);
  tonemap stack exemplary - cleanest of the batch.
- extraBuffer unused in all 8; if a brief adds it, [133..255] ONLY ([0..4] reserved,
  [5..132] = engine FFT bins).
"""
import json
import os
import subprocess

ROOT = "/home/ftpbridge/image_video_effects"
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-generative-briefs-2026-07-26-b18")
os.makedirs(OUT_DIR, exist_ok=True)

SHADERS = [
    {
        "id": "gen_quantum_foam",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This quantum foam claims 'audio-reactive' but reads mouse Y as its audio source - make it honest, then give the vacuum a voice:",
        "techniques": [
            "FIX THE FAKE AUDIO (priority 1): `audioPulse = u.zoom_config.z` is mouse Y (the comment even admits 'proxy') - and plasmaBuffer is never read. Rewire: bass (`plasmaBuffer[0].x`) drives the foam burst/pair-production rate; per-bin FFT (`plasmaBuffer[1..8]`) modulates the entanglement-web density spatially.",
            "Entanglement strikes: loop ripples[] (guard `min(u32(u.config.y), 50u)`) perturbing the web field with a decaying shockwave from each click point.",
            "Spring-damper the mouse warp point (extraBuffer[133..135]) so the vacuum polarity eases instead of snapping; delete the dead `n` variable in noise() and make the dead dataTextureA write carry real display color (it currently stores a biased finalColor*0.5+0.5 that nothing reads - either wire dataTextureC feedback with a bounded mix <= 0.1 or store clean display color).",
        ],
        "caution": "CAUTION: preserve `quantumFoam()` + `entanglementWeb()` and `acesToneMap()` VERBATIM - the visual identity is the fbm correlation math. extraBuffer in [133..255] ONLY ([0..4] reserved, [5..132] = engine FFT bins).",
    },
    {
        "id": "kimi_nebula_depth",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. IDENTITY CRISIS: the JSON says 'volumetric nebula with ray marching' but the WGSL is a halftone dot + Sobel ink-stipple effect (naga-transpiled GLSL). Make the metadata honest and polish the actual effect:",
        "techniques": [
            "HONEST METADATA (priority 1): the JSON description and slider display names are wrong (no nebula, no raymarching, no 3D noise). In the JSON: KEEP all param ids/defaults/mappings EXACTLY (saved-preset contract), but update the description to describe the real halftone/Sobel ink-stipple effect and update param display names to honest ones (Dot Size / Edge Threshold / Posterize Levels / Ink Density). In updatedParams use the NEW honest names.",
            "Audio pulse: add bass reactivity (`plasmaBuffer[0].x`) driving a subtle dot-size pulse for VJ feel (the JSON gains no new params - wire it in WGSL only).",
            "Spring-damper the mouse vignette center (extraBuffer[133..134]); fix the vignette edge case gated on `mousePos.x >= 0.0` (vanishes at the left edge); remove the dead `radius` variable.",
        ],
        "caution": "CAUTION: preserve the Sobel double-loop and `hash12_` VERBATIM - this is fragile naga-transpiled output; do NOT 'clean up' the `_eNN` temps. JSON: param ids/defaults/min/max/mapping must not change - only description and display names become honest.",
        "honest_names": {"param1": "Dot Size", "param2": "Edge Threshold", "param3": "Posterize Levels", "param4": "Ink Density"},
        "honest_description": "Halftone dot and Sobel edge ink-stipple effect: posterized luma rendered as resolution-independent dots with ink outlines, paper grain, and a mouse-driven vignette.",
    },
    {
        "id": "gen_grok41_plasma",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This spherical-harmonics gas giant has a DEAD Hue Shift slider and a missing bounds guard - fix both, then push the harmonics spectral:",
        "techniques": [
            "FIX THE DEAD HUE SHIFT (priority 1): `gasGiantColor()` builds `shiftMat` from the Hue Shift slider but never applies it (dead matrix). Apply the rotation to the final color so the slider works. Also add the missing OOB bounds guard (`if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }`).",
            "Band-specific harmonics: weight the three harmonic bands from per-bin FFT - l1 (Y1x) follows bass bins (`plasmaBuffer[1..3]`), l2 follows mid bins (`plasmaBuffer[4..6]`), l3 follows treble bins (`plasmaBuffer[7..8]`) - so each spherical-harmonic family dances to its own frequency range.",
            "Storm cells: add a subtle Worley noise overlay on the gas-giant band structure for cellular storm texture (keep it under 20% mix so the harmonics stay dominant).",
        ],
        "caution": "CAUTION: preserve the 10 `Y00..Y30` spherical-harmonic functions VERBATIM - the constants are exact normalization coefficients. The existing bass-turbulence and treble-lightning audio paths stay intact.",
    },
    {
        "id": "gen_rainbow_smoke",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This is the best-engineered shader of the batch - one stability risk to shore up, then add spectral emitters:",
        "techniques": [
            "CFL SAFETY (priority 1): velocity in the sim state is NOT clamped - vorticity confinement scaled by (1 + bass*3.0) can push |v| past 1 px/frame on hard bass hits, destabilizing the semi-Lagrangian advection. Add a magnitude clamp (`clampMag(velocity, 0.05)`) inside the sim update - nothing else about the solver changes.",
            "Spectral emitters: add 2 extra emission centers whose intensities track per-bin FFT (`plasmaBuffer[1..8]`), positioned on a slow Lissajous drift, so different frequency ranges ignite different smoke sources.",
            "Click smoke bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) injecting radial velocity + density impulses at each click point; spring-damper the mouse stir point (extraBuffer[133..135]).",
        ],
        "caution": "CAUTION: preserve the state channel packing `vec4(velocity, density, temperature)` and the decay constants (0.972/0.994/0.992) VERBATIM - the whole sim chain depends on them. dataTextureA is SIM STATE - never tonemap it. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "quantum-foam-lattice",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This lattice feeds ACES-tonemapped color back into itself - a slow contrast-decay bug. Fix the feedback order, then spectralize the cells:",
        "techniques": [
            "FIX THE DOUBLE-TONEMAP FEEDBACK (priority 1): dataTextureA stores ACES-tonemapped display color which is read back next frame via dataTextureC - each frame re-tonemaps, progressively flattening contrast. Restructure: read prev (dataTextureC) and blend in LINEAR space, store linear HDR (clamp pre-tint ~1.2) to dataTextureA, and apply ACES only to the final display output after the feedback mix.",
            "Per-cell spectrum: rotate each voronoi cell's hue by its own FFT bin (`plasmaBuffer[1 + (cellId % 8)].x`) so the lattice shimmers across the spectrum.",
            "Lattice displacement waves: loop ripples[] (guard `min(u32(u.config.y), 50u)`) sending a decaying radial displacement through the lattice from each click.",
        ],
        "caution": "CAUTION: preserve the voronoi F2-F1 edge logic and the 3-channel chromatic-dispersion re-evaluation VERBATIM - the shader's signature look. The feedback restructure must keep the same blend weights (0.25 + bass*0.15); only the tonemap position changes.",
    },
    {
        "id": "spec-distance-field-text",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This glyph shader samples depth with the wrong UV space and advertises feedback trails that do not exist - fix both honestly:",
        "techniques": [
            "FIX THE DEPTH UV (priority 1): the depth passthrough samples readDepthTexture with `uv` (the -1..1 remapped coord) instead of `uv01` - out-of-range samples clamp to edge texels and poison the downstream depth chain. Fix both sample sites to `uv01`.",
            "MAKE THE TRAILS REAL: JSON/tags claim temporal feedback but dataTextureC is never read. Implement it: store (glyphColor, d) to dataTextureA as now, read back via dataTextureC with decay ~0.92 mixed at <= 0.3 (clamp accumulated pre-tint ~1.2) so glyphs leave phosphor trails. Keep it stable.",
            "Spectral glyphs: select the active glyph index from per-bin FFT energy (`plasmaBuffer[1..4]`, one bin per glyph) so the dominant band picks the symbol; click ripples (guard `min(u32(u.config.y), 50u)`) as expanding SDF displacement rings.",
        ],
        "caution": "CAUTION: preserve `sdGlyph0..3` and the branchless `sdGlyph` index-weight selection VERBATIM - glyph shapes are hand-tuned segment sets. Keep the `overlayMix < 0.001` early-exit passthrough intact.",
    },
    {
        "id": "gen_grok41_mandelbrot",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. This Buddhabrot has the same tonemapped-feedback decay as quantum-foam-lattice, plus a missing bounds guard - fix the accumulation integrity:",
        "techniques": [
            "FIX THE DOUBLE-TONEMAP FEEDBACK (priority 1): dataTextureA stores ACES-tonemapped color read back next frame - progressive contrast fade. Store LINEAR pre-tonemap accumulation (density stays Reinhard-soft-clamped), apply ACES only to the display output after the history mix. Also add the missing OOB bounds guard.",
            "Gliding navigation: spring-damper the zoom/center targets (extraBuffer[133..136]) so Center X/Y/Zoom slider moves glide instead of jumping; add click ripples (guard `min(u32(u.config.y), 50u)`) that re-target the zoom center to the click point.",
            "Spectral stars: drive star density per band from per-bin FFT (`plasmaBuffer[1..8]`) so the starfield follows the spectrum.",
        ],
        "caution": "CAUTION: preserve `cmul`/`escapes` and the orbit-points accumulation loops VERBATIM - Buddhabrot correctness depends on exact iteration order. param4's dual purpose (evolution speed + historyBlend) is intentional - keep both couplings. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "interactive_neural_swarm",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This neural swarm claims 'audio-reactive' but reads the mouse button as audio, and its depth write clobbers the chain - wake it up:",
        "techniques": [
            "FIX THE FAKE AUDIO (priority 1): `audioPulse = u.zoom_config.w` is mouse-DOWN, not audio - plasmaBuffer is never read. Rewire: bass (`plasmaBuffer[0].x`) drives global activation energy, and each neuron i reads its own FFT bin (`plasmaBuffer[1 + (i % 8)].x`) for per-neuron activation. ALSO make 'Network Density' honest: it currently only scales brightness - let it also gate the active neuron count (e.g. 20-40 neurons).",
            "Honest depth: the shader writes constant 0.0 depth, clobbering the chain - write depth derived from neuron proximity/signal strength instead.",
            "Click signal waves: loop ripples[] (guard `min(u32(u.config.y), 50u)`) emitting expanding activation wavefronts from each click that propagate through the connection web; spring-damper the mouse attractor (extraBuffer[133..135]); replace the sin/cos neuron drift with a curl-noise drift field.",
        ],
        "caution": "CAUTION: preserve `getNeuronPos` hash placement and the O(N^2) `connectionStrength` loop VERBATIM - network topology emerges from those exact hash constants. extraBuffer in [133..255] ONLY.",
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
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional - only declare it if the shader already uses it.
- extraBuffer (if ever used): [0..4] reserved, [5..132] = engine FFT bins - persistent shader state goes in [133..255] ONLY.
- Engine uniform truth (verified src/renderer/UniformBuffer.ts): config = [time, rippleCount, resW, resH]; zoom_config = [time, mouseX, mouseY, mouseDown]. Guard ripple loops with `min(u32(u.config.y), 50u)`.
"""

MANDATORY_BULLETS = [
    "Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.",
    "Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.",
    "Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.",
]

MANDATORY_BULLETS_2PARAM = [
    "Wire the 2 existing slider params via u.zoom_params.x/y using the EXISTING JSON controls (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-1. These param ids/defaults are the saved-preset contract: do not rename or re-default them, and do NOT invent params for z/w.",
    "Make each slider drive meaningful shader-specific constants in the WGSL.",
    "Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.",
]


def extract_params(meta):
    """Return list of {name, default, min, max, step} from any known schema."""
    if "params" in meta:
        return [
            {
                "name": p["name"],
                "default": p["default"],
                "min": float(p.get("min", 0.0)),
                "max": float(p.get("max", 1.0)),
                "step": p.get("step", 0.01),
            }
            for p in meta["params"][:4]
        ]
    controls = [c for c in meta["controls"] if c.get("type") in ("slider", "range")]

    def field_of(c):
        if "uniform" in c:
            return c["uniform"]  # "zoom_params.x"
        return f"zoom_params.{c['uniformMapping']['field']}"

    controls.sort(key=field_of)
    return [
        {
            "name": c["name"],
            "default": c["default"],
            "min": float(c.get("min", 0.0)),
            "max": float(c.get("max", 1.0)),
            "step": c.get("step", 0.01),
        }
        for c in controls[:4]
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

    hn = spec.get("honest_names", {})
    upd = [
        {
            "index": i,
            "name": hn.get(meta["params"][i].get("id"), p["name"]) if hn and "params" in meta else p["name"],
            "default": p["default"],
            "min": p["min"],
            "max": p["max"],
            "step": p["step"],
        }
        for i, p in enumerate(extract_params(meta))
    ]

    out_meta = dict(meta)
    if spec.get("honest_description"):
        out_meta["description"] = spec["honest_description"]
    if spec.get("honest_names") and "params" in out_meta:
        for p in out_meta["params"]:
            if p.get("id") in spec["honest_names"]:
                p["name"] = spec["honest_names"][p["id"]]
        for u in upd:
            # match by index: params array order corresponds to updatedParams index
            pass
    out_meta["updatedParams"] = upd
    out_meta["updated"] = True
    json_str = json.dumps(out_meta, indent=2)

    mandatory = MANDATORY_BULLETS_2PARAM if spec.get("param_count") == 2 else MANDATORY_BULLETS
    bullets = list(spec["techniques"]) + mandatory
    if spec["caution"]:
        bullets.append(spec["caution"])

    parts = []
    parts.append(f"# Swarm Brief: {sid}\n")
    parts.append(f"**Role:** {spec['role']}")
    parts.append(f"**Name:** {meta.get('name', sid)}")
    parts.append("**Category:** generative")
    parts.append(f"**Description:** {meta.get('description', '(no description field)')}")
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
