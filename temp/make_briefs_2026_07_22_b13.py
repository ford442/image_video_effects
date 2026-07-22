#!/usr/bin/env python3
"""Generate 8 self-contained generative swarm briefs in swarm-tasks/kimi-generative-briefs-2026-07-22-b13/.

Batch 13 (generative edition): same theme as Batches 10-12 - formalize updatedParams
from EXISTING param ids/names/defaults (saved-preset contract, no renames), make each
slider drive meaningful shader-specific constants (kill boilerplate mappings), + 2-3
tailored techniques each, expansion +50-90 lines, gate green.

Recon notes baked in (2026-07-22):
- gen_kimi_nebula & gen_hyper_warp share the applyGenerativePrimaryControls boilerplate
  with placeholder param1-4 JSON -> rewire to real constants, keep ids/defaults/names.
- coral-growth & crystalline-fracture store SIM STATE (envelope/stress) in feedback
  channels, not color - briefs warn agents not to "fix" it.
- retro_phosphor_dream has a latent bug: audioPulse = u.zoom_config.w (MouseDown) and
  plasmaBuffer is never read.
- gen_hyper_warp feedback (x1.1 sharpen @ 0.95 mix) is borderline blowout -> clamp.
- extraBuffer convention (Batch 12 FFT lesson): persistent state goes in [133..255]
  ONLY ([0..4] reserved, [5..132] = engine FFT bins). None of these 8 need extraBuffer.
"""
import json
import os
import subprocess

ROOT = "/root/image_video_effects"
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-generative-briefs-2026-07-22-b13")
os.makedirs(OUT_DIR, exist_ok=True)

SHADERS = [
    {
        "id": "gen-neural-dust",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. Make the dust field feel alive and aware of the viewer:",
        "techniques": [
            "Comet trails: wire the declared-but-unread dataTextureC feedback so motes leave ~0.9-decay streaks (mix color with previous frame); clamp the accumulated trail pre-tint at ~1.2 (luma-echo-warp lesson).",
            "Per-bin spectrum response: use plasmaBuffer[1+n] bins so different dust grid cells jitter/glow to different frequency bands instead of the whole field following bass+treble globally.",
            "Depth-aware parallax: offset the dust field sample position by a readDepthTexture sample so motes drift around foreground silhouettes of the input frame.",
        ],
        "caution": "CAUTION: mouse coords are u.zoom_config.yz (not .xy) and u.zoom_config.w is MouseDown - follow that convention. The 4 sliders are already shader-specific (density/speed/glow/hue) - keep those mappings and EXTEND them, do not rewire.",
    },
    {
        "id": "gen_kimi_nebula",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This nebula's 4 sliders are placeholder param1-4 wired to the generic applyGenerativePrimaryControls boilerplate - none of them touch the actual nebula algorithm. Make them real:",
        "techniques": [
            "KILL THE BOILERPLATE (priority 1): replace applyGenerativePrimaryControls with real nebula constants - Intensity -> gas density gain, Speed -> animation time multiplier (currently hard-coded time*0.1), Scale -> noise spatial scale, Detail -> star density threshold (currently hard-coded 0.995). Keep JSON ids/names/defaults EXACTLY as they are (saved-preset contract) - only the WGSL mapping changes.",
            "Audio layer separation: mids and treble drive drift speeds of different fbm density layers so the cloud strata visibly disaggregate with the music (bass already drives chromatic offset - keep that).",
            "Extra domain warp: warp noisePos by one additional fbm3 lookup for more turbulent billowing; keep the ACES tonemap and the 0.85 input blend intact.",
        ],
        "caution": None,
    },
    {
        "id": "gen_hyper_warp",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. Same placeholder param1-4 / applyGenerativePrimaryControls boilerplate as kimi_nebula, PLUS a borderline feedback loop. Stabilize first, then wire real controls:",
        "techniques": [
            "STABILIZE THE FEEDBACK (priority 1): the dataTextureC loop mixes sharpened history (history*1.1 - 0.05) at 0.95 weight - a slow amplifier held in check only by ACES+clamp. Add an explicit ~1.2 pre-tint clamp on the sharpened history (luma-echo-warp lesson) so it can never blow out.",
            "KILL THE BOILERPLATE: rewire the 4 sliders to real constants - Intensity -> warp amplitude (q weight), Speed -> time multiplier (currently fixed 0.2), Scale -> palette frequency/hue offset, Detail -> feedback mix (range ~0.85-0.98). Keep JSON ids/names/defaults EXACTLY (saved-preset contract).",
            "Flow-advected history: offset the dataTextureC sample position slightly by the r warp vector so feedback smears along the liquid flow instead of sharpening a static frame.",
        ],
        "caution": "CAUTION: preserve the triple domain-warp reaction-diffusion character and the radial burst; do not reduce octave counts. This shader's charm is the specific warp weights.",
    },
    {
        "id": "supernova-remnant",
        "role": "Visualist",
        "role_intro": "You are the Visualist. Push the stellar-explosion realism: thermal aging, shock physics, interactive detonations:",
        "techniques": [
            "Blackbody age ramp: accumulate a slow inertial 'age' in dataTextureA alpha (read back smoothed) and map shell color through a white-hot -> orange -> deep-red blackbody-style ramp as age grows, instead of fixed RGB shell weights.",
            "Click detonation: mouse-down spawns a secondary expanding shock front using the ripples[] uniform array in Uniforms (currently unused) - ring radius expands from the click point and perturbs the shock shell where it passes.",
            "Inertial bass kicks: bass nudges the age/expansion accumulator rather than rescaling expansion directly, so kicks feel like momentum, not zoom.",
        ],
        "caution": "CAUTION: preserve the normalize(uv01 - 0.5 + 0.001) epsilon guard and the existing chromatic-dispersed feedback (decay 0.92, mix ~0.15) - it is stable, do not retune it. The 4 sliders are already shader-specific; keep their mappings.",
    },
    {
        "id": "coral-growth",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. Deepen the growth model: branching hierarchy, spectral tips, and luminous residue:",
        "techniques": [
            "Second-order sub-branching: branches currently split once (gated by proj > currentLen*0.5); add a second branching level whose probability is driven by mids (plasmaBuffer[0].y) so the colony bushes out with the music.",
            "Spectral tip lighting: use per-bin plasmaBuffer[1+n] reads so different branch indices light their tips to different frequency bands instead of global treble only.",
            "Luminous growth residue: keep the bass envelope in feedback .r exactly as-is, but mix a real color trail into the output with ~0.9 decay, clamped pre-tint at ~1.2, so growth leaves glowing history.",
        ],
        "caution": "CAUTION: dataTextureA channels are SIM STATE, not color - .r carries the smoothed bass envelope (attack/release), .a the trail age. Do NOT 'fix' this into pure color storage; other reads depend on the envelope. Preserve the envelope logic verbatim.",
    },
    {
        "id": "crystalline-fracture",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. Extend the fracture mechanics: stress waves, grain boundaries, and persistent crack memory:",
        "techniques": [
            "Click stress rings: use u.config.y (MouseClickCount, currently unused) or the ripples[] uniform to spawn ring-shaped stress waves on click that propagate outward and trigger cracks where K exceeds toughness.",
            "Weak grain boundaries: make fracture toughness spatially varying via one fbm lookup so cracks preferentially propagate along weak paths - reads as real material grain.",
            "Crack memory healing: decay the stored stress memory (feedback .r) slower (e.g. store prev.r*0.98) so fracture patterns persist and evolve across frames instead of resetting; keep the effective feedback ratio strictly < 1.0.",
        ],
        "caution": "CAUTION: dataTextureA channels are SIM STATE (.r = accumulated stress, .g = crack connectivity), not color - preserve that layout. The stress feedback ratio (prev.r*0.5) is a geometric series: never raise the coefficient to >= 1.0 or stress diverges. Keep the thin-film iridescence and SSS math intact.",
    },
    {
        "id": "retro_phosphor_dream",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This CRT emulator has a LATENT BUG and zero real interactivity - fix the bug, then make it respond:",
        "techniques": [
            "FIX THE BUG (priority 1): audioPulse is bound to u.zoom_config.w (MouseDown) and plasmaBuffer is declared but never read - rewire audioPulse to plasmaBuffer[0].x (bass) so persistence decay + glow actually pump with music, not clicks.",
            "Analog hum & jitter: treble (plasmaBuffer[0].z) drives subtle scanline phase jitter plus a slow vertical hum-bar roll for authentic analog noise.",
            "Mouse degauss: mouse X modulates curvature strength; on mouse-down trigger a temporary degauss wobble (time-decaying sinusoidal UV offset) using u.zoom_config.yz/w.",
        ],
        "caution": "CAUTION: the phosphor persistence uses max(current, prev*decay) - it cannot blow out additively, but keep decay <= 0.95. Preserve the barrel distortion, RGB triad mask, and vignette math; upgrade, don't rewrite. Keep JSON steps/defaults as-is (saved-preset contract).",
    },
    {
        "id": "spec-analytic-noise-flow",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. This shader's analytic-derivative Perlin noise is its raison d'etre - exploit the free gradient, don't touch the math:",
        "techniques": [
            "Iso-contour ridges: use the already-computed analytic gradient magnitude (free byproduct) to draw flow iso-contour lines (fract(noise1.x*N) ridge mask) that sharpen with treble - contour density tied to the Detail-adjacent slider mapping.",
            "Bass surge: multiply advection strength by a bass envelope (plasmaBuffer[0].x) so kicks visibly surge the flow field.",
            "Temporally coherent streamlines: dataTextureA already stores velocity in .rg - read prev.rg as velocity and apply an exponential smoothing filter frame-to-frame so streamlines stop shimmering; keep the existing light color feedback (mix ~0.03) intact.",
        ],
        "caution": "CAUTION: preserve noiseWithDerivative EXACTLY (k0/k1/k2/k4 quintic coefficient form) - do not 'simplify' it. Note dataTextureA stores velocity vectors, not color; the existing prev.rgb color read at 3% mix is harmless - keep it, and add the velocity read as a separate path.",
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
