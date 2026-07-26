#!/usr/bin/env python3
"""Generate 8 self-contained generative swarm briefs in swarm-tasks/kimi-generative-briefs-2026-07-26-b17/.

Batch 17 (generative edition 8): same theme as Batches 10-15 - formalize updatedParams
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
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-generative-briefs-2026-07-26-b17")
os.makedirs(OUT_DIR, exist_ok=True)

SHADERS = [
    {
        "id": "chromatic-ghost-tunnel",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This tunnel is already reference-quality - do not fix what is not broken. Add spectral individuality and touch:",
        "techniques": [
            "Per-bin ring voices: drive each ghost echo ring i from `plasmaBuffer[1 + (i % 8)].x` instead of only the global bands, so individual rings flare to individual FFT bins.",
            "Click tunnel shockwaves: loop the ripples[] uniform (guard `min(u32(u.config.y), 50u)`) sending a decaying brightness/chromatic shockwave down the tunnel z-axis from each click.",
            "Inertial flight: spring-damper the mouse tunnel offset (extraBuffer[133..136], critically damped) so steering has momentum.",
        ],
        "caution": "CAUTION: preserve the OkLab mix + blackbody temperature palette and the hue_preserve_clamp(5.0) -> ACES -> IGN dither -> gamma output chain VERBATIM and in order - it is the shader's signature look. extraBuffer in [133..255] ONLY ([0..4] reserved, [5..132] = engine FFT bins).",
    },
    {
        "id": "crystalline-veins",
        "role": "Visualist",
        "role_intro": "You are the Visualist. These mineral veins can blow out their highlights (sparkle x2.5 stacked on pulse x1.4, no tonemap). Tame the HDR, then enrich the geology:",
        "techniques": [
            "TAME THE BLOWOUT (priority 1): add a hue-preserving clamp at ~1.2 followed by ACES tonemapping AFTER the accumulation/feedback section (not inside it), so treble-hit sparkles stop clipping to white. This also sanitizes the raw-color feedback loop.",
            "Worley crack complement: add a Worley F2-F1 crack layer as a cheaper secondary vein generator, modulated by per-bin FFT (`plasmaBuffer[1..8]`) so cracks shimmer across the spectrum.",
            "IQ mineral palette: replace the hardcoded gold/copper/silver lerps with an IQ cosine palette driven by the Mineral Shift slider for richer mineral variety (keep defaults visually close to the legacy gold look).",
        ],
        "caution": "CAUTION: preserve the FBM domain-warp `veinNoise` ridge formula (`1.0 - abs(n-0.5)*2.0` + `pow(combined, 2.5)`) VERBATIM - it defines the vein geometry. Any tonemap goes AFTER the accumulation block, never inside it.",
    },
    {
        "id": "cosmic-web",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This cosmic web has a feedback discontinuity hiding in its void path - fix the temporal coherence, then smooth the gravity:",
        "techniques": [
            "FIX THE VOID FEEDBACK GAP (priority 1): the early-exit void path writes constant voidColor and SKIPS the temporal feedback mix, so voids shimmer at filament edges. Route void pixels through the same feedback path (move the early-exit after the temporal mix) so the whole frame is temporally coherent.",
            "Per-octave spectrum: the filament stack already bands bass/mids/treble - refine it so filament octave o reads `plasmaBuffer[(o % 8) + 1].x`, making large structure follow bass bins and fine structure follow treble bins.",
            "Spring-damper gravity well: ease the mouse gravity center with a critically-damped spring (extraBuffer[133..136]) so the well lags the cursor organically.",
        ],
        "caution": "CAUTION: preserve the branchless voronoi3 F1/F2 and the filamentDensity constants (FILAMENT_SHARP=10, BIAS=0.05) VERBATIM - filament sharpness is numerically tuned. Keep the compositeAlpha multi-factor alpha untouched (3-slot compositor contract). dataTextureA holds pre-ACES HDR color - do not add a clamp that changes the feedback equilibrium; only reroute the void path. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "gen_grokcf_interference",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This Bessel drum-mode shader has a mislabeled slider and dead mouse code - make the labels honest, then give the membrane a real strike:",
        "techniques": [
            "MAKE 'COLOUR MODE' HONEST (priority 1): zoom_params.y is only consumed by the applyGenerativePrimaryControls boilerplate (brightness pulse) - the slider does nothing color-related. Evict the boilerplate and wire y to a real hue rotation of the base color before the Chladni mix. Keep the JSON id/name/default EXACTLY (saved-preset contract). Also remove the x-param double duty (modeScale AND boilerplate intensity fighting on one slider) - x drives modeScale only.",
            "Remove the dead mouse code: `rc` and `phic` are computed from zoom_config.yz and never used (stale 'mouse shifts drum centre' comment). Either delete them or - better - make the mouse genuinely offset the drum center via the (r, phi) polar mapping.",
            "Membrane strikes: loop ripples[] (guard `min(u32(u.config.y), 50u)`) injecting a decaying impulse into u_total at each click point (a real drum hit); weight each drum mode by its matching FFT bin `plasmaBuffer[1 + (mode % 8)]` for truer cymatics.",
        ],
        "caution": "CAUTION: preserve the Abramowitz & Stegun J0/J1 polynomial coefficients and the tabulated Bessel zeros (2.4048, 5.5201, 3.8317, 7.0156, 5.1356, 6.3802) VERBATIM - they are the physical correctness of the modal model. dataTextureA stores SIM STATE (u_total, r, phi/2pi, blendAlpha) - never clamp/tonemap it.",
    },
    {
        "id": "stellar-plasma",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This IQ-style nebula is healthy but its comments lie and its chromatic aberration is fake - clean the signal:",
        "techniques": [
            "FIX THE LYING COMMENTS (priority 1, docs-only): the struct comments claim config.y/z/w = AudioLow/Mid/High and zoom_config.x = MouseX - all wrong (config.y = rippleCount, zw = resolution, zoom_config.x = time, mouse = .yz). Correct the comments to the verified engine truth; code behavior unchanged.",
            "Real chromatic aberration: replace the additive caStr tint with 3 actual spectral samples of the fbm field at sub-pixel offsets (cheap because the warp coords are reused) - true prismatic fringing on the nebula filaments.",
            "IQ cosine palette: replace the 4 hardcoded base colors with an IQ cosine palette driven by the Hue Shift slider (defaults reproduce the legacy look), and spring-damper the mouse gravity (extraBuffer[133..136]).",
        ],
        "caution": "CAUTION: preserve the nested double domain-warp structure (q then r then f) VERBATIM including the 4.0x warp amplitude and offset constants (1.7, 9.2 / 8.3, 2.8) - this is the classic IQ nebula signature; changing the warp amplitude destroys the look. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "audio_geometric_pulse",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This shader calls itself audio-reactive but its 'audio' is the mouse button - fix the headline bug, then make the name true:",
        "techniques": [
            "FIX THE FAKE AUDIO (priority 1): `let audioPulse = u.zoom_config.w;` is mouse-DOWN, not audio - the whole 'audio-reactive' feature is click-reactive and plasmaBuffer is never read. Rewire: `audioPulse` from bass (`plasmaBuffer[0].x`), and drive the 5 band rings from real per-bin FFT `plasmaBuffer[1..5]` instead of the mouse flag. Change ONLY the source of audioPulse - keep all downstream uses.",
            "Click SDF rings: loop ripples[] (guard `min(u32(u.config.y), 50u)`) spawning expanding geometric SDF rings from each click point that fade with ripple age.",
            "Treble symmetry modulation: let treble (`plasmaBuffer[0].z`) subtly modulate the kaleidoscope segment count around the Symmetry slider value; spring-damper the mouse center offset (extraBuffer[133..136]).",
        ],
        "caution": "CAUTION: preserve the exact kaleidoscope fold math (mod_val + segment mirror) and the SDF set (sdCircle/sdBox/sdTriangle/sdHexagon) VERBATIM. When rewiring audio, replace only the SOURCE of audioPulse, never its downstream uses. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "gen_kimi_crystal",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. This ice-crystal shader is missing the mandatory bounds guard and has no tonemap - harden it, then add the physics-flavored extras:",
        "techniques": [
            "ADD THE MISSING OOB GUARD (priority 1): every sibling shader has the `if (pixel.x >= res.x || pixel.y >= res.y) { return; }` bounds guard - this one relies on WebGPU OOB-store discard. Add the standard guard. Also add a hue-preserving clamp at ~1.2 + ACES before the store (edgeGlow + sparkle + mouseGlow can exceed 1).",
            "Spectral dispersion: split the Fresnel edgeGlow into 3 spectral samples with slightly different IORs (1.31/1.32/1.33 - ice dispersion) for cheap physically-flavored chromatic fringing on crystal edges.",
            "Audio growth: bass (`plasmaBuffer[0].x`) pulses the crystal growth; per-bin FFT (`plasmaBuffer[1..8]`) shimmers individual hex rows.",
        ],
        "caution": "CAUTION: preserve the physical transmission block VERBATIM (crystalMask, Fresnel-Schlick with F0 from IOR_ICE=1.31, Beer absorption exp(-k*path*mask), transmission product) - it is the shader's stated identity. Also preserve the odd-row hex offset logic exactly.",
    },
    {
        "id": "gen_fluffy_raincloud",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This vorticity raincloud has the cleanest architecture of the batch - protect it, and add storm interactivity around the edges:",
        "techniques": [
            "Storm gusts on click: loop ripples[] (guard `min(u32(u.config.y), 50u)`) injecting radial velocity impulses into the SIM STATE (the .gb velocity channels) at each click point - gusts that the vorticity confinement then naturally swirls.",
            "Per-bin rain audio: mids bins (`plasmaBuffer[3..5]`) micro-modulate rain intensity, treble bins (`plasmaBuffer[6..8]`) raise the rain-sheet streak noise threshold so hi-hats read as rain texture.",
            "Long-session precision fix: wrap the noise-coordinate time (`mod(time, 3600.0)`) so the fbm field does not degrade after hours of runtime; spring-damper the mouse gust center (extraBuffer[133..136]).",
        ],
        "caution": "CAUTION: preserve the dataTextureA channel packing `(density, velocity.x, velocity.y, moisture)` and dataTextureB packing `(rain, omega*0.5+0.5, silverEdge, lightning)` VERBATIM - the vorticity-confinement neighbor reads depend on .gb = velocity layout; any repack breaks the fluid sim. Sim-state channels stay raw (never tonemapped). extraBuffer in [133..255] ONLY.",
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
