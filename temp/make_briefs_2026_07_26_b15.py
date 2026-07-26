#!/usr/bin/env python3
"""Generate 8 self-contained generative swarm briefs in swarm-tasks/kimi-generative-briefs-2026-07-26-b15/.

Batch 15 (generative edition 6): same theme as Batches 10-14 - formalize updatedParams
from EXISTING param ids/names/defaults (saved-preset contract, no renames), make each
slider drive meaningful shader-specific constants, + 2-3 tailored techniques each,
expansion +50-90 lines, gate green.

Recon notes baked in (2026-07-26, Batch 15):
- gen-crystalline-nebula-weaver-void-spider: FAKE AUDIO (reads u.ripples[0].x with a
  stale "plasmaBuffer proxy" comment - that is click-ripple data), fake fbm (sum of
  sin(dot)), no tonemap (blowout risk), JSON uses non-standard `controls[]` schema.
- gen-holographic-fracture: MOUSE BUG - reads u.zoom_config.xy (x = Time!), same bug
  class fixed in B13/B14. Engine convention: zoom_config.yz = mouse pos, w = mouse-down.
  JSON claims supportsDepth:true but WGSL writes flat 0.0 depth.
- liquid_crystal_birefringence: `audioPulse = u.zoom_config.w` - mouse-down mislabeled
  as audio; plasmaBuffer declared but never read.
- kimi_quantum_field: DOUBLE TONEMAP (Reinhard + ACES stacked, over-darkens mids);
  dead psi() helper; sliders mislabeled (keep JSON names - preset contract).
- kimi_fractal_dreams: cdiv(0.1, z+0.01) near-zero denominator -> NaN risk when
  complexity > 1.5; sliders mislabeled (same contract handling).
- supernova-core: cleanest of the set; premultiplied-alpha compositor block is a
  3-slot-chain CONTRACT - preserve verbatim.
- lava-lamp-blobs: dataTextureA = SIM STATE (blobShape, blobHalo, heat, a) - never
  clamp/tonemap; mouse not aspect-corrected.
- extraBuffer unused in all 8; if a brief adds it, [133..255] ONLY ([0..4] reserved,
  [5..132] = engine FFT bins).
"""
import json
import os
import subprocess

ROOT = "/home/ftpbridge/image_video_effects"
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-generative-briefs-2026-07-26-b15")
os.makedirs(OUT_DIR, exist_ok=True)

SHADERS = [
    {
        "id": "gen-crystalline-nebula-weaver-void-spider",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This raymarched nebula-spider has broken audio and a fake noise field. Fix the foundations, then make it glow:",
        "techniques": [
            "FIX THE FAKE AUDIO (priority 1): the shader computes `audioBass` from `u.ripples[0].x` with a stale comment claiming it is a plasmaBuffer proxy - ripples[] is click-ripple data, NOT audio, so audio reactivity is dead. Rewire to the real `plasmaBuffer[0].x` (bass) for the spider abdomen pulse and add `plasmaBuffer[0].z` (treble) driving web-thread glint/sparkle.",
            "Real fbm nebula: replace the fake `sin(dot(...))` accumulation with a true hash-based value-noise fbm (3-4 octaves, rotation matrix between octaves) for the crystalline nebula density, and add an IQ cosine palette `a + b*cos(6.28318*(c*t+d))` for the crystalline hue grading.",
            "Tame the blowout: plasma_intensity up to 2.0 stacked on glow with no tonemap clips to white - add a hue-preserving clamp at ~2.0 followed by ACES tonemapping before output, preserving the luminous look.",
        ],
        "caution": "CAUTION: preserve the canonical 13-binding header and Uniforms struct verbatim; keep the ray origin `ro = (0,0,-5*void_depth)` / `max_dist = 20*void_depth` coupling or the spider leaves frame. The JSON uses a non-standard `controls[]` schema - do NOT restructure it; only updatedParams/updated are added to the JSON (handled outside the WGSL).",
    },
    {
        "id": "gen_psychedelic_spiral",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This superformula spirograph is already solid - give it individual spectral voices and a sense of touch:",
        "techniques": [
            "Per-bin superformula modulation: drive the superformula exponents (n2/n3) from individual FFT bins `plasmaBuffer[1..k]` (e.g. n2 from a low bin, n3 from a high bin) instead of only the band averages, so the petal morphology visibly follows the spectrum.",
            "Click petal bursts: loop the ripples[] uniform (guard with `min(u32(u.config.y), 50u)`) and add each live ripple as a decaying radial impulse to shapeRadius - clicks detonate a temporary petal-burst ring.",
            "IQ cosine palette: replace the hsv2rgb call with an IQ cosine palette for cheaper, smoother chroma, and add a hue-preserving clamp at ~1.2 on the color before the feedback write to future-proof the history loop (value can reach ~2.6 today).",
        ],
        "caution": "CAUTION: preserve the dataTextureC feedback historyUV transform chain (rotate -> scale by `0.985 - feedback*0.08` -> aspect un-correct -> `+0.5+mouseOffset*0.15`) VERBATIM - it is the warp signature. dataTextureC is engine-owned: sampled, never written by this shader. dataTextureA carries display color here (not sim state).",
    },
    {
        "id": "liquid_crystal_birefringence",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This LCD physics shader claims audio it does not have - make it honest, then give the spectrum a physical voice:",
        "techniques": [
            "FIX THE FAKE AUDIO (priority 1): `let audioPulse = u.zoom_config.w;` is mouse-DOWN, not audio - the twist 'audio' wobble only fires while the mouse is held, and plasmaBuffer is declared but never read. Rewire: bass (`plasmaBuffer[0].x`) -> cell compression around the Frederiks threshold, mids (`plasmaBuffer[0].y`) -> twist oscillation, treble (`plasmaBuffer[0].z`) -> Schlieren sparkle grain.",
            "Spectrum retardation bands: read per-bin `plasmaBuffer[1..8]` and add a per-bin radial Newton-ring fringe term to the phase retardation, so the interference rainbow visibly decomposes into 8 spectral bands.",
            "Click voltage pulses: loop ripples[] (guard `min(u32(u.config.y), 50u)`) as propagating voltage fronts that locally flip the director orientation as they pass, and spring-damper the mouse defect core (2 extraBuffer slots in [133..255]) for smooth tracking.",
        ],
        "caution": "CAUTION: preserve the `phaseRetardation()` physical wavelength constants (650/530/460 nm x 0.001) and the `rotatePolarization` Mueller-matrix math VERBATIM - the interference colors depend on them. extraBuffer persistent state goes in [133..255] ONLY ([0..4] reserved, [5..132] = engine FFT bins).",
    },
    {
        "id": "gen-holographic-fracture",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This shader has the mouse-coordinate bug class we fixed in Batches 13/14 - fix it first, then make the cracks answer to touch:",
        "techniques": [
            "FIX THE MOUSE BUG (priority 1): the shader reads mouse position from `u.zoom_config.xy`, but x is TIME - the crack origin drifts with time. Engine convention is `u.zoom_config.yz` = mouse position, `.w` = mouse-down (verified in src/renderer/UniformBuffer.ts). Change ONLY the `.xy` -> `.yz` swizzle - do not restructure the crack-network loop. Also fix the stale header comment documenting the wrong convention.",
            "Honest depth: the JSON claims `supportsDepth: true` but the WGSL writes flat 0.0 to writeDepthTexture - write a real depth derived from crack distance/edge field so the depth feature is earned.",
            "Click crack fronts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) spawning transient crack fronts that expand from each click point and fade with ripple age; spring-damper the mouse crack origin (extraBuffer[133..134]) so it eases rather than snaps. Add per-bin plasmaBuffer[1..k] phase shifts to the thin-film iridescence so each crack index shimmers to its own band.",
        ],
        "caution": "CAUTION: preserve the `hash22`/`valueNoise`/`fbm2`/`glow` chunk-library function bodies VERBATIM (shared-pattern chunks). extraBuffer persistent state in [133..255] ONLY. The hard clamp(col,0,1) may be upgraded to hue-preserve-clamp + ACES, but keep the final output in 0..1.",
    },
    {
        "id": "kimi_quantum_field",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This wave-packet interferometer has a double tonemap and dead code - clean the signal path, then make the spectrum a real interferometer:",
        "techniques": [
            "FIX THE DOUBLE TONEMAP (priority 1): the shader applies Reinhard `col/(1+col)` + pow(0.95), THEN `acesToneMap(col*1.1)` - stacked curves over-darken the mids. Remove the Reinhard/pow line and keep the ACES call. Also delete the dead `psi()` helper (defined, never called).",
            "Spectrum interferometer: drive individual wave-source amplitudes from per-bin `plasmaBuffer[1..k]` reads (source i reads bin i+1) so the interference pattern is a literal audio interferogram; mids -> phase hue via an IQ cosine palette, treble -> antinode bloom gain.",
            "Honest sliders (preset contract): the JSON names are mislabeled vs. code (Intensity=waveCount, Speed=coherence, Scale=uncertainty, Detail=decayRate) and CANNOT be renamed (saved-preset contract). Keep the JSON exactly as-is; in the WGSL make each slider's effect match its label as closely as possible WITHOUT changing defaults' visual output (e.g. let 'Speed' also drive packet phase velocity, 'Scale' also drive field zoom).",
        ],
        "caution": "CAUTION: preserve the |psi|^2 probability accumulation loop and the `alpha = probability + nodes*0.3 + collapsed*mouseDown` semantics VERBATIM - alpha-as-probability is the shader's identity. When fixing the tonemap, remove ONLY the Reinhard line, not the ACES call.",
    },
    {
        "id": "kimi_fractal_dreams",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This Burning-Ship Julia dreamscape has a latent NaN and mislabeled sliders - guard the math, then smooth the dream:",
        "techniques": [
            "FIX THE NaN RISK (priority 1): `cdiv(0.1, z + 0.01)` divides by a near-zero denominator when z ~= (-0.01, -0.01) (only reachable when complexity > 1.5), producing inf/NaN pixels. Add a small epsilon guard on the denominator magnitude (e.g. max(length2, 1e-4)) inside or around cdiv - do not change the formula's behavior elsewhere.",
            "Spring-damper Julia morph: smooth the mouse-driven Julia constant with a critically-damped spring (2-4 extraBuffer slots in [133..255]) so c glides instead of lerping at fixed 0.5; add click ripples (guard `min(u32(u.config.y), 50u)`) as temporary zoom-pulse impulses decaying with ripple age.",
            "Orbit-trap palette + treble filaments: key an IQ cosine palette on the orbit-trap distance, and extend treble reactivity to per-bin `plasmaBuffer[1..k]` filament glow so high-hat energy lights the fractal edges.",
            "Honest sliders (preset contract): JSON names are mislabeled vs. code (Intensity=zoom, Speed=iterations, Scale=colorCycles) and CANNOT be renamed. Keep JSON as-is; in WGSL give each slider an ADDITIONAL honest effect matching its label (e.g. 'Speed' also drives layer rotation rate) without changing the default look.",
        ],
        "caution": "CAUTION: preserve the Burning-Ship abs() + cmul iteration core and the smooth-escape `smoothIter = i - log2(log2(r)) + 4.0` formula VERBATIM; the 3-layer rotation by 1.047 rad with 0.8 scale is the visual signature. extraBuffer persistent state in [133..255] ONLY.",
    },
    {
        "id": "supernova-core",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. This is the cleanest shader of the batch - do not fix what is not broken. Add spectral and tactile depth around the pristine core:",
        "techniques": [
            "Spectrum-driven rays: modulate individual ray intensities by per-bin `plasmaBuffer[1..k]` reads (ray index i reads bin (i % 8) + 1) so the light echo decomposes into the audio spectrum; keep the per-ray hash shimmer as the floor.",
            "Click Sedov rings: loop ripples[] (guard `min(u32(u.config.y), 50u)`) spawning secondary shockwave rings from each click point with Sedov-Taylor radius growth (r ~ t^0.4) and age-decayed intensity.",
            "Spring-damper companion star: ease the mouse companion-star position with a critically-damped spring (extraBuffer[133..134]) so the asymmetry and rim light relax smoothly after fast mouse moves.",
        ],
        "caution": "CAUTION: preserve the advanced alpha compositor block VERBATIM (luminanceKey -> depthAlpha -> beerLambertAlpha -> edgeAlpha blend order and the pre-multiplied `finalColor = color * alpha` output) - downstream 3-slot chain depends on premultiplied semantics. Keep the OkLab mix, blackbody functions, hue_preserve_clamp(hdr, 8.0) -> ACES -> gamma -> IGN dither stack byte-identical. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "lava-lamp-blobs",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This metaball lamp is physically charming but touch-deaf - give it per-blob voices and honest interaction:",
        "techniques": [
            "Aspect-correct the mouse (priority 1): the mouse offset uses `u.zoom_config.yz * 2.0 - 1.0` without aspect correction, so blob attraction is elliptical on wide screens - aspect-correct the x component using u.config.zw, and spring-damper the attraction point (extraBuffer[133..135]) instead of the raw 0.1 shift.",
            "Per-blob FFT voices: assign each blob index its own FFT bin `plasmaBuffer[(i % 8) + 1]` so blobs pulse individually to the spectrum; add mids -> blob-count shimmer and treble -> rim sparkle on the halo term.",
            "Click heat injections: loop ripples[] (guard `min(u32(u.config.y), 50u)`) spawning a temporary new blob at each click point that rises and dissolves with ripple age.",
        ],
        "caution": "CAUTION: dataTextureA is SIM STATE packed as `(blobShape, blobHalo, heat, a)` - preserve the channel order VERBATIM, never route it through the ACES/dither stack, never clamp/tonemap it. Keep the premultiplied `outRGB * a` write to writeTexture and the hue_preserve_clamp -> ACES -> IGN dither -> gamma stack intact. extraBuffer in [133..255] ONLY.",
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
"""

MANDATORY_BULLETS = [
    "Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.",
    "Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.",
    "Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.",
]


def extract_params(meta):
    """Return list of {name, default, min, max, step} from either schema."""
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
    # Non-standard controls[] schema (void-spider): uniform: "zoom_params.x" etc.
    controls = [c for c in meta["controls"] if c.get("type") == "slider"]
    controls.sort(key=lambda c: c["uniform"])
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

    bullets = list(spec["techniques"]) + MANDATORY_BULLETS
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
