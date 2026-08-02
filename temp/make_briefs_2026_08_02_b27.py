#!/usr/bin/env python3
"""Generate 8 self-contained swarm briefs in swarm-tasks/kimi-briefs-2026-08-02-b27/.

Batch 27 (smallest-first all-category, wave 10): same theme as Batches 17-26 -
formalize updatedParams from EXISTING params (saved-preset contract), make each
slider drive meaningful shader-specific constants, +2-3 tailored techniques each,
+50-90 lines, gate green. Pool scan reused from the b17 generator (all categories,
multipass-safe).

ENGINE UNIFORM TRUTH (verified src/renderer/UniformBuffer.ts + webgpu/frame.ts):
  config      = [time, rippleCount, resW, resH]
  zoom_config = [time, mouseX, mouseY, mouseDown]  -> mouse = .yz, down = .w
  ripples guard: min(u32(u.config.y), 50u)
NOTE: docs/BINDING_CONTRACT.md claims config.y=delta_time - STALE, trust the TS source.

Recon notes baked in (2026-08-02, Batch 27):
- melting-oil: JSON category artistic, header says 'simulation' (stale). THREE
  MISLABELED SLIDERS: y 'Turbulence' actually drives mouseForceK, z 'Ripple
  Strength' actually drives hueShiftK, w 'Color Shift' actually drives audioK
  (audio boost). LEGACY RIPPLE LOOP: `for i < 8` with step(1e-4, rip.z) active
  test and NO min(u32(u.config.y), 50u) guard - non-standard, convert to the
  guarded convention. Stale comments (config.y='ClickCount', zoom_config.w=
  'Generic2'). Sobel gradient flow + advection + hue math are the identity.
- spec-iridescence-engine: plasmaBuffer NEVER SAMPLED (dead audio on a
  spectral-render shader); mouse only acts while mouseDown; ripples unused.
  Spectral loop 380-700nm/20nm step + wavelengthToRGB + OPD + fresnel blend +
  tonemap + alpha=thickness/1000 are the identity.
- spectral-waves: raw mouse; ripples unused; stale comments (ClickCount/Generic2).
  IQ palette + ACES + IGN dither + premultiplied output are the identity.
- aero-chromatics: plasmaBuffer NEVER SAMPLED ('Or generic object data' comment);
  raw mouse; ripples unused. C->A display-color history contract. Dev commentary
  comments are file personality (keep verbatim).
- chroma-kinetic: raw mouse; ripples unused; luma_influence has non-standard
  range -2..2 (keep exact). Velocity lead/lag chromatic + smear loop identity.
- cyber-trace: plasmaBuffer NEVER SAMPLED; ripples unused; C->A raw history
  (clamp 2.0) SACRED; custom ranges (Trail Decay 0.8-0.99, Glow 0-3, Brush
  0.005-0.2) keep EXACT. Dev commentary comments stay verbatim.
- gen-chrono-erosion-feedback-melting: DEAD SLIDER - feedbackMix (w) is read and
  NEVER USED (melt uses decay only). Mouse smudge NOT aspect-corrected. Ripples
  unused. Feedback C read / A raw write (clamp 1.5) sacred - never tonemap.
- quantum-flux: raw mouse; ripples unused; global FFT only. rgb2hsv/hsv2rgb/
  jitter/wave/split taps/scanlines are the identity.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_briefs_common import (  # noqa: E402
    MANDATORY_BULLETS,
    REQUIRED_OUTPUT,
    extract_params,
    wgsl_line_count,
)
from make_briefs_2026_07_30_b17 import scan_pool  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-briefs-2026-08-02-b27")
os.makedirs(OUT_DIR, exist_ok=True)

SHADERS = [
    {
        "id": "melting-oil",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. Three of this oil flow's four sliders are LIES - 'Turbulence' drives the mouse force, 'Ripple Strength' drives the hue shift, 'Color Shift' drives the audio boost - and its ripple loop is a legacy non-standard 8-iteration form with no rippleCount guard. Make the labels honest and the clicks standard:",
        "techniques": [
            "REWIRE THE 3 MISLABELED SLIDERS (priority 1 - ids/names/defaults EXACTLY, defaults reproduce today's look bit-exact): y ('Turbulence', 0.4) must drive real chaotic flow - add a time-varying sinusoidal turbulence perturbation to flow_dir scaled by y, with y=0.4 reproducing the current feel (the old mouseForce role moves to a fixed constant 0.4 so the mouse gate is unchanged at default). z ('Ripple Strength', 0.5) must scale the click-stir amplitude (the `stir` accumulation *= mix(0.0, 2.0, z) - default 0.5 = 1.0 bit-exact). w ('Color Shift', 0.3) must drive the hue-shift mix (hueShiftK = w - default 0.3 lands on today's hue behavior; the old audioK role becomes a fixed 1.0 multiplier on the bass boost).",
            "CONVERT THE LEGACY RIPPLE LOOP to the standard guarded form: `let rippleCount = min(u32(u.config.y), 50u); for (var i = 0u; i < rippleCount; i++)` - keep the existing stir math (exp(-dR2*60) swirl pulse, 3s alive window) as the per-ripple behavior, now honoring the real click count. Fix the stale comments (comment-only): config.y = ripple COUNT, zoom_config.w = mouseDown.",
            "Spring-damper the mouse influence + per-region FFT: ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the flow bend glides; raw mouse stays the spring target. Modulate the hue-shift phase by 8 vertical-band bins (`plasmaBuffer[(band % 8u) + 1u].x * 0.3`) so the oil sheen shimmers across the spectrum. Fix the stale header ('Category: simulation' -> artistic, comment-only).",
        ],
        "caution": "CAUTION: preserve the 9-tap Sobel gradient (r0/r1/r2 textureLoad grid), the grad/flow_dir construction, the mouseGate gaussian, the advection sampling (last_pos/dimF), the hue_shift PHI math, and the alpha formula VERBATIM - the flow identity is hand-tuned. dataTextureA stays DISPLAY color. The engine manages the A->C history copy; keep reads of dataTextureC as-is. extraBuffer in [133..255] ONLY. All slider ids/names/defaults/ranges EXACTLY (saved-preset contract).",
    },
    {
        "id": "spec-iridescence-engine",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This is a SPECTRAL-RENDER shader that never samples the audio spectrum - plasmaBuffer is declared and ignored - and the mouse only matters while the button is held. Give the film a light show:",
        "techniques": [
            "WIRE THE DEAD AUDIO (priority 1): per-wavelength spectral voices - inside the thinFilmColor call site, modulate the computed iridescent color's RGB channels by FFT bins mapped across the visible range (e.g. iridescent.r *= 1.0 + plasmaBuffer[7].x * 0.25, .g by bin 4, .b by bin 2 - high wavelengths ride high bins), so music plays across the rainbow. Also a global bass breathing on intensity (intensity *= 1.0 + bass * 0.3).",
            "Spring-damper film lens (mouse matters unpressed): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT); near the sprung point, add a gentle always-on thickness lens (thickness += 80nm * aspect-corrected gaussian ~0.25 radius) so hovering tilts the film; the existing mouseDown perturbation rides the SPRUNG position.",
            "Click film waves: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple launches an expanding thickness wave from its click point (thickness += 150nm * sin(age * 20.0 - dist * 40.0) * exp(-age * 2.0) * ring mask, ~1.5s), so clicks send iridescent ripples across the oil slick.",
        ],
        "caution": "CAUTION: preserve the hash12 helper, wavelengthToRGB, the thinFilmColor spectral integration loop (380-700nm, 20nm step), the OPD/cosTheta_t math, the depth+noise thickness construction, the fresnel blend, the HDR tonemap, and the alpha=thickness/1000.0 semantic (both writes) VERBATIM - the spectral physics are the identity. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stores (iridescent, thickness/1000) - keep that packing. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "spectral-waves",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This luma ripple's palette/ACES/dither stack is exemplary - but the wave origin snaps to the cursor and clicks never launch a wave. Make the water respond:",
        "techniques": [
            "Spring-damper the wave origin (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the ripple epicenter glides; raw mouse stays the spring target. Keep the existing aspect correction (uv_c/mouse_c).",
            "Click wave trains: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple emits an expanding wave train from its click point (an extra displacement term: sin(distR * frequency * 0.8 - rippleAge * 8.0) * exp(-rippleAge * 1.5) * maxAmplitude * 0.8 in an aspect-corrected falloff, ~2s), composed with the main wave before the chromatic taps, so clicks splash rings.",
            "Per-ring FFT voices: quantize the radial distance into 8 rings; each ring's crest glow rides its own bin (`plasmaBuffer[(ring % 8u) + 1u].x * 0.35` added into the caustic term), so the spectrum ripples outward spatially. Fix the stale comments (comment-only): config.y = ripple COUNT, zoom_config.w = mouseDown.",
        ],
        "caution": "CAUTION: preserve the getLuminance/palette/aces/ign helpers, the dual-wave construction (wave + echoWave), the crest smoothsteps, the displacement luma weighting, the 3-tap chromatic aberration with safeDir, the spectral/caustic/bass-glow HDR assembly, the radial vignette, the dither, the alpha formula, and the PREMULTIPLIED finalRGBA output VERBATIM - the tonal stack is hand-tuned. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays display color (premultiplied, same as writeTexture). extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "aero-chromatics",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This smoke-advection shader declares plasmaBuffer 'Or generic object data' and never samples it - the smoke ignores the music - and clicks never gust. Give the wind a beat:",
        "techniques": [
            "WIRE THE DEAD AUDIO (priority 1): bass gusts - the windStrength rides bass (windStrength *= 1.0 + bass * 0.6) so drops push the smoke; per-band flutter - 8 horizontal bands each wobble their velocity perpendicular component by `plasmaBuffer[(band % 8u) + 1u].x * 0.003`, so the trail flickers across the spectrum.",
            "Spring-damper the wind source: ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the repulsion source drifts like a slow fan; raw mouse stays the spring target. Keep the aspect-corrected distance and the smoothstep(0.5, 0.0) influence.",
            "Click gust bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying radial gust from its click point (velocity += aspect-corrected dir * 0.02 * exp(-rippleAge * 2.0) * smoothstep(0.35, 0.0, distR), ~1.5s), so clicks blow puffs of smoke. Fix the stale comment (comment-only): config.y = ripple COUNT.",
        ],
        "caution": "CAUTION: the feedback contract is SACRED - dataTextureC is read as advected history (3 chromatic taps + alpha carry), dataTextureA is written with the display color - keep this exactly, never tonemap the A write. Preserve ALL the dev commentary comments VERBATIM (file personality), the luma-drag model, the baseWind/mouseWind construction, the chromatic offsetR/G/B advection taps, the decay/injectAmount mix, and the depth-weighted alpha VERBATIM. All 4 slider ids/names/defaults EXACTLY. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "chroma-kinetic",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. This velocity-chromatic smear is well-tuned - but the effect center snaps to the cursor and clicks never fire a kinetic burst. Precision work:",
        "techniques": [
            "Spring-damper the effect center (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the distortion field glides; raw mouse stays the spring target. The spring VELOCITY also feeds a small strength bonus (strength *= 1.0 + min(springSpeed * 3.0, 0.4)) so fast flicks smear harder - the shader is literally named kinetic.",
            "Click kinetic bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple fires a decaying directional smear pulse at its click point (local velocity boost exp(-rippleAge * 2.0) in an aspect-corrected ~0.25 radius, direction radial from the click, ~1.2s), so clicks punch motion trails.",
            "Per-sector FFT voices: divide the field into 8 angular sectors around the sprung center; each sector's smear mix (the finalR/G/B bass/mids/treble blends) rides its own bin (`plasmaBuffer[(sector % 8u) + 1u].x * 0.25`), so the chromatic trail shimmers directionally. Fix the stale comments (comment-only): config.y = ripple COUNT, zoom_config.w = mouseDown.",
        ],
        "caution": "CAUTION: preserve the bass_env helper, the rotation matrix + uvOffsetDir construction, the falloff/modFactor math, the lead/lag chromatic taps (uvR/uvG/uvB), the 3-sample smear loop with its (1.0 - t) weights, the per-channel smear mix structure, the depthMod, and the alpha formula VERBATIM - the velocity identity is hand-tuned. Sliders: luma_influence range is -2..2 (non-standard, keep EXACT), rotation default 0 - all ids/names/defaults/ranges EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "cyber-trace",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This neon tracer's raw-history feedback is solid - but it never samples the audio, the brush snaps, and clicks leave no mark beyond the held drag. Light it up:",
        "techniques": [
            "Spring-damper the brush (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the trace ribbons behind the cursor; raw mouse stays the spring target. Keep the aspect correction and the down/idle brush strength select.",
            "WIRE THE DEAD AUDIO: bass pulses the glow (glowIntensity * (1.0 + bass * 0.5) at the composite only - history stays raw), mids drive the hue cycle speed (colorTick rate * (1.0 + mids * 0.8)), and 8 vertical bands each shimmer their composite glow by `plasmaBuffer[(band % 8u) + 1u].x * 0.3`.",
            "Click stamp blooms: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple stamps a soft round bloom into the history at its click point (same drawColor pipeline, radius ~ brushSize * 1.5, decaying with ripple age ~1.5s), so clicks paint stars without dragging.",
        ],
        "caution": "CAUTION: the history contract is SACRED - dataTextureC read as prev history, dataTextureA written RAW (historyColor * decaySpeed + drawColor * brush, clamp to 2.0) - never tonemap the A write; audio modulation of glow happens ONLY at the composite. Preserve the hue2rgb/hslToRgb helpers and ALL dev commentary comments VERBATIM (file personality). Custom slider ranges are EXACT (Trail Decay 0.8-0.99, Glow Intensity 0-3, Brush Size 0.005-0.2). extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "gen-chrono-erosion-feedback-melting",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This datamosh melt has a DEAD SLIDER - 'Feedback Mix' (w) is read into `feedbackMix` and then never referenced; the melt weight is `decay` alone. The mouse smudge is also elliptical (no aspect correction). Fix the plumbing:",
        "techniques": [
            "WIRE THE DEAD SLIDER (priority 1 - bit-exact at default 0.6): make feedbackMix scale the feedback weight (`let meltW = clamp(decay * (feedbackMix / 0.6), 0.0, 0.98); let melted = mix(current, feedback, meltW);` - default 0.6 reproduces `decay` exactly, lower values favor the live frame, higher values deepen the mosh). ASPECT-CORRECT the smudge: `mouseDist = length(mouseDelta)` -> correct both uv and mouse by (aspect, 1.0) before the distance so the influence is circular.",
            "Spring-damper the smudge: ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the smear finger drags with weight; raw mouse stays the spring target.",
            "Click melt vortices + per-region FFT: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple injects a decaying rotational flow vortex at its click point (tangent vector * exp(-rippleAge * 1.8) * 0.02, aspect-corrected ~0.2 radius, ~2s), so clicks stir the melt. Modulate the turbulence per 8 vertical bands (`plasmaBuffer[(band % 8u) + 1u].x * 0.5`) so different strips boil at different energies.",
        ],
        "caution": "CAUTION: the feedback contract is SACRED - dataTextureC read at displacedUV, dataTextureA written with outCol RAW (clamp 1.5) - never tonemap the A write. Preserve the hash/noise/curlNoise helpers, the curl flow construction, the bass shock block (keep its branchy form - it predates the branchless convention and is the file's character), the flowMag color shift, the beat inversion block, and the displacedUV clamp VERBATIM. All 4 slider ids/names/defaults EXACTLY. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "quantum-flux",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This flux field's jitter/wave/split composition is honest - but the influence snaps to the cursor and clicks never collapse the field. Give it quantum behavior:",
        "techniques": [
            "Spring-damper the flux center (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the influence zone trails the cursor; raw mouse stays the spring target. Keep the existing aspect correction (uvCorrected/mouseCorrected).",
            "Click decoherence bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple spikes the jitter locally at its click point (a decaying +0.6 jitterAmount bump in an aspect-corrected ~0.25 radius smoothstep, exp(-rippleAge * 2.0), ~1.2s), so clicks make reality flicker without holding the cursor still.",
            "Per-region FFT voices: divide the influence zone into 8 angular sectors; each sector's jitter seed rides its own bin (`plasmaBuffer[(sector % 8u) + 1u].x * 0.3` modulating the jitter magnitude), so different wedges vibrate to different frequencies.",
        ],
        "caution": "CAUTION: preserve the rgb2hsv/hsv2rgb/rand helpers, the jitter/wave/split construction, the 3 chromatic tap offsets, the hue-drift driftMask gate, the interference scanlines, and the splitMag alpha formula VERBATIM - the flux identity is hand-tuned. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
]


def main():
    pool = scan_pool()
    picks = [e["id"] for e in pool[:8]]
    expected = [s["id"] for s in SHADERS]
    print("Batch 27 pool picks:", picks)
    if picks != expected:
        print("WARNING: pool drifted from baked recon - update SHADERS before running!")
        print("  expected:", expected)
        sys.exit(1)

    for spec in SHADERS:
        sid = spec["id"]
        entry = next(e for e in pool if e["id"] == sid)
        json_path = os.path.join(ROOT, "shader_definitions", entry["category"], f"{sid}.json")
        wgsl_path = os.path.join(ROOT, "public", "shaders", f"{sid}.wgsl")

        with open(json_path) as f:
            meta = json.load(f)
        with open(wgsl_path) as f:
            wgsl = f.read().rstrip("\n")

        wc = wgsl_line_count(wgsl_path)
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
        parts.append(f"**Category:** {entry['category']}")
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


if __name__ == "__main__":
    main()
