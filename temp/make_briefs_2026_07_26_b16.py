#!/usr/bin/env python3
"""Generate 8 self-contained generative swarm briefs in swarm-tasks/kimi-generative-briefs-2026-07-26-b16/.

Batch 16 (generative edition 7): same theme as Batches 10-15 - formalize updatedParams
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
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-generative-briefs-2026-07-26-b16")
os.makedirs(OUT_DIR, exist_ok=True)

SHADERS = [
    {
        "id": "gen-ethereal-cyber-chrono-nebula-phoenix",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This SDF phoenix claims to be audio-reactive (it is tagged 'audio-reactive') but its audio is dead - resurrect it, then tame the HDR:",
        "techniques": [
            "FIX THE DEAD AUDIO (priority 1): the shader reads `audio` from `u.config.y`, which is the engine's RIPPLE COUNT (near-constant, not sound) - the 'audio-reactive' tag is a lie. Rewire: bass (`plasmaBuffer[0].x`) drives the attractor `a` constant wobble and wing plasma pulse; treble (`plasmaBuffer[0].z`) drives the chronoGlow shimmer.",
            "Tame the HDR: bgColor scaled by (1+audio*2) plus additive chronoGlow/mouseGlow has NO tonemap - once real audio lands this blows out. Add a hue-preserving clamp at ~2.0 followed by ACES (Narkowicz) before the writeTexture store.",
            "Spring-damper phoenix halo: ease the mouse glow center with a critically-damped spring (extraBuffer[133..134], [0..4] reserved, [5..132] = engine FFT) so the phoenix's attention glides; add a click ripple ring (guard `min(u32(u.config.y), 50u)`) that momentarily flares the wing plasma as it expands.",
        ],
        "caution": "CAUTION: preserve the `sdPhoenix` SDF constants and the `attractorTrap` Clifford constants (-1.4, 1.6, 1.0, 0.7, 24 iters) VERBATIM - the silhouette is hand-tuned. The JSON uses a non-standard `controls[]` schema with ONLY 2 params (wingspan x, plasma_intensity y) - do NOT invent new params or restructure the JSON; updatedParams mirrors just those 2 (handled outside the WGSL). zoom_params.z/w stay unused.",
        "param_count": 2,
    },
    {
        "id": "liquid_magnetic_ferro",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This ferrofluid sim has a dead slider, mislabeled audio, and a NaN waiting at screen center - fix the physics honesty:",
        "techniques": [
            "WIRE THE DEAD VISCOSITY SLIDER (priority 1): zoom_params.z is read into `fluidViscosity` but never used. Make it real with temporal field smoothing: store the magnetic field magnitude to dataTextureA each frame and read back the previous field (dataTextureC), mixing `field = mix(prevField, field, mix(0.05, 0.95, 1.0 - viscosity))` so high viscosity = slow, molasses-like spike response. Keep the stored field raw (sim state - never tonemap the A write).",
            "Honest audio: `audioPulse = u.zoom_config.w` is mouse-DOWN, not audio. Rewire to bass (`plasmaBuffer[0].x`) modulating field strength and treble (`plasmaBuffer[0].z`) modulating spike frequency.",
            "Kill the NaNs: `normalize(uv - 0.5)` is normalize(0,0) at the exact screen-center pixel - add an epsilon guard (e.g. `normalize(uv - 0.5 + vec2<f32>(1e-4, 0.0))` or select-based safe normalize); same for `normalize(field)` where field ~ 0. Clamp the depth write to >= 0.0 (spike height can go negative via sign(pattern)).",
        ],
        "caution": "CAUTION: preserve the Rosensweig spike formula (`pow(abs(pattern), 0.3) * sign(pattern)`) and the dipole 1/r^3 falloff VERBATIM - they are the physics identity. dataTextureA becomes SIM STATE (raw field) with this upgrade - never clamp/tonemap it.",
    },
    {
        "id": "bio_lenia_continuous",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This continuous Lenia sim has good feedback discipline but confused uniform semantics - clean the gates, then give it seasons and a second species:",
        "techniques": [
            "FIX THE SPAWN GATE (priority 1): `mouseClickCount = u.config.y` is the engine's ripple count - it stays > 0 forever after the first click, so the mouse spawns life continuously without being held. Gate mouse seeding on `u.zoom_config.w > 0.5` (mouse-DOWN) instead. Also fix `audioPulse = u.zoom_config.w` (mouse-down mislabeled as audio): route real audio from `plasmaBuffer[0].y` (mids) to a slow growthCenter wobble (audio 'seasons' - classic Lenia modulation).",
            "Second species: store a competing species in the free dataTextureA.g channel with its own bell() kernel parameters and a cross-feeding term (species A inhibits B where dense), so red/green colonies visibly compete. Keep species B's dynamics in the existing dataTextureC read-back path (A packs both channels).",
            "Click seed bombs: loop the ripples[] uniform (guard `min(u32(u.config.y), 50u)`) - each live ripple drops a circular species-B seed blob at the click point, decaying with ripple age.",
        ],
        "caution": "CAUTION: preserve the `bell()` growth/kernel functions, the clamp(newState, 0.0, 1.0), and the dataTextureA.r primary-species state layout VERBATIM - the feedback contract depends on them. dataTextureA is SIM STATE - never clamp/tonemap it. The O(r^2) kernel loop is expensive by design; do not restructure it.",
    },
    {
        "id": "bioluminescent-bloom",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This Gray-Scott bloom is well-behaved but tone-mapped twice - fix the wash, then give each tendril its own voice:",
        "techniques": [
            "FIX THE DOUBLE ACES (priority 1): ACES is applied twice in the output path (the second pass at col*1.1), washing out the highlights. Remove the second application - single ACES only - and add a hue-preserving clamp at ~1.2 on the HDR bloom term BEFORE the tonemap. Also fix the stale struct comment claiming config.y = MouseClickCount semantics it does not document correctly (comment-only fix).",
            "Per-tendril spectrum: tendril index i reads `plasmaBuffer[(i % 8) + 1].x` to phase-offset its pulse, so each tendril dances to its own FFT bin instead of all following the global bands.",
            "Spring-damper nutrient source: ease the mouse chemotaxis target with a critically-damped spring (extraBuffer[133..134]) so the nutrient point glides and the chemotaxis trails read as pursuit rather than snapping.",
        ],
        "caution": "CAUTION: preserve the Gray-Scott constants (Du=0.18, Dv=0.09, feed/kill base 0.025/0.055) and the dataTextureA=(un, vn, glow, density) channel packing VERBATIM - the RD equilibrium and feedback contract depend on them. dataTextureA is SIM STATE - never clamp/tonemap it. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "chrono-voronoi-mycelium",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. All four of this shader's sliders are trapped in generic applyGenerativePrimaryControls boilerplate (brightness/speed-pulse/contrast/mouse-gain) - every label is a lie. Evict the boilerplate and wire the real mycelium constants:",
        "techniques": [
            "EVICT THE BOILERPLATE (priority 1): rewire the sliders to shader-specific constants, defaults reproducing the current look - Growth Bias (x) -> layer ageMix blend exponent, Temporal Scale (y) -> the actual time multiplier of the layer clocks, Decay Influence (z) -> the layer decay rate (e.g. mix(0.970, 0.995, z)), Pattern Complexity (w) -> the primary voronoi scale (e.g. mix(4.0, 16.0, w)). Remove the shared helper call entirely. Keep JSON ids/names/defaults EXACTLY (saved-preset contract).",
            "Clean the feedback path: delete the duplicate dataTextureC sample (`prevLayer2` re-reads the same texel as `prevLayer1` - dead code) and the redundant dataTextureB store (B is never read; A packs all three layers). Keep the A packing and caps untouched.",
            "Spectral seed jitter: offset each voronoi seed by a per-bin FFT term `plasmaBuffer[(cellId % 8) + 1].x` so colonies shimmer with the spectrum; spring-damper the inoculation point (extraBuffer[133..134]) so it glides.",
        ],
        "caution": "CAUTION: preserve the layer cap values (1.8/1.6/1.9), the decay formula structure, and the dataTextureA channel packing (layer1->r, layer2->g, layer3->b) VERBATIM - temporal feedback stability depends on them. dataTextureA is SIM STATE - never clamp/tonemap it. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "cosmic-jellyfish",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This raymarched jelly computes a temporal trail buffer and then THROWS IT AWAY - unlock the trails, then give it sound and honest depth:",
        "techniques": [
            "DISPLAY THE DEAD FEEDBACK (priority 1): the shader computes `temporal = mix(prev*0.96, col, 0.25)` into dataTextureA but displays raw `col` - the feedback loop is dead code. Display it: `col = mix(col, temporal, 0.6)` before output so the jelly leaves bioluminescent motion trails. Keep the 0.96 decay (< 1.0, stable) and clamp the accumulated trail pre-tint at ~1.2.",
            "Honest depth + tonemap: writeDepthTexture currently stores flat 0.0, clobbering scene depth for chained shaders - write the real raymarch hit distance (normalized). There is no tonemap and Glow Intensity goes to 5.0 - add hue-preserving clamp + ACES before output.",
            "Audio + palette: bass (`plasmaBuffer[0].x`) drives the bell pulse amplitude, treble (`plasmaBuffer[0].z`) drives tentacle wave frequency; replace the Rodrigues RGB hue rotation with an IQ cosine palette for the glow (cheaper, smoother).",
        ],
        "caution": "CAUTION: preserve the `map()` SDF structure (bell hollow + 8-tentacle capsule loop, smin k=0.2) VERBATIM - the creature silhouette is hand-tuned. Keep the u.zoom_params reads INSIDE map() (moving them changes the SDF's implicit contract). JSON param ranges exceed 0-1 (Pulse Speed 0-2, Glow 0-5) - keep defaults/ranges EXACTLY.",
    },
    {
        "id": "spec-quaternion-julia",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. This quaternion Julia set has a mislabeled slider and a spec-violating alpha - make both honest without touching the sacred math:",
        "techniques": [
            "MAKE 'DETAIL LEVEL' REAL (priority 1): zoom_params.w currently only divides the hue - wire it to the DE iteration count (`let iters = 8 + i32(u.zoom_params.w * 8.0)`) so the slider truly controls fractal detail. Keep the hue divisor role as a secondary effect if you like, but detail must be primary.",
            "Clamp the background alpha: background pixels store `alpha = orbitTrap / 10.0` with orbitTrap initialized at 1000 - alpha up to ~100 in an rgba32float target is a contract violation. Clamp alpha to 1.0. Also guard the DE `log(r)` against r ~ 0 on the first iteration (minor -inf risk).",
            "Audio + trap palette: bass (`plasmaBuffer[0].x`) multiplies the morph speed, mids (`plasmaBuffer[0].y`) offsets the 4D constant c.w for audio drift; add an IQ cosine palette keyed on the minimum orbit-trap distance over the whole march (classic Julia glow bands).",
        ],
        "caution": "CAUTION: preserve `quaternionMul` component order, the DE escape radius (256.0), and the `0.5 * r * log(r) / dr` distance estimator VERBATIM - fractal correctness depends on exact quaternion algebra. The mouse-gated orbit (zoom_config.w) semantics are correct - do not change them.",
    },
    {
        "id": "tornado-vortex",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This is the cleanest shader of the batch - but its advertised radial inflow/updraft physics is dead code. Bring it to life, then add touch:",
        "techniques": [
            "ACTIVATE THE DEAD PHYSICS (priority 1): `vRadial` and `vVertical` are computed but never used - the JSON description advertises radial inflow/vertical updraft that never happens. Advect debris angle/radius by vRadial and lift debris/brightness by vVertical so particles visibly spiral inward and rise.",
            "Click secondary vortices: loop the ripples[] uniform (guard `min(u32(u.config.y), 50u)`) spawning a temporary satellite vortex at each click point with its own decaying circulation that perturbs the funnel field as it lives (~2s).",
            "Per-bin lightning: drive lightning branch count/intensity from treble FFT bins (`plasmaBuffer[1..8]` high bins) so strikes follow hi-hats instead of only the global treble band.",
        ],
        "caution": "CAUTION: preserve the Rankine vortex `select()` core/outer branch, the blackbodyRGB coefficients, and the OkLab matrices VERBATIM - physical/perceptual correctness. The hue-preserve clamp 8.0 -> ACES(x1.5) -> IGN dither stack is exemplary - keep it byte-identical. dataTextureA stores display color here (not sim state).",
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
