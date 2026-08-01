#!/usr/bin/env python3
"""Generate 8 self-contained swarm briefs in swarm-tasks/kimi-briefs-2026-07-31-b19/.

Batch 19 (smallest-first all-category, wave 3): same theme as Batches 17-18 -
formalize updatedParams from EXISTING params (saved-preset contract), make each
slider drive meaningful shader-specific constants, +2-3 tailored techniques each,
+50-90 lines, gate green. Pool scan reused from the b17 generator (all categories,
multipass-safe).

Recon notes baked in (2026-07-31, Batch 19):
- reactive-glass-grid: wiring honest (all 4 sliders real); raw clamped mouse (no
  glide); ripples[] unused; every tile follows the same global bass/treble.
- ascii-glyph: features say 'mouse-driven' but the MOUSE IS NEVER READ (zoom_config
  unused); stale uniform comments (config.y='ClickCount', zoom_config.w='Generic2');
  header says 'Category: stylize' but JSON lives in geometric. All 4 sliders honest.
- temporal-phosphor-burn-motion-adaptive: history-ring shader (binding 13) +
  extraBuffer[4] historyHead read (engine-owned - read-only OK). Features say
  'mouse-driven' but mouse NEVER READ. Params honestly wired (motion-adaptive
  decay is the real deal).
- codebreaker-reveal: wiring honest; mouse read raw (no glide); ripples[] unused;
  stale comment config.y='MouseClickCount' (it's rippleCount). No JSON description.
- digital-reveal: wiring honest; A=mask/C=prev-mask feedback consistent (NOT
  mask-as-color); mouse raw; ripples[] unused; stale comments (config.y=
  'MouseClickCount', zoom_config.w='Generic2' - it's mouseDown).
- magnetic-ring: wiring honest (JSON even has explicit mapping fields); mouse raw;
  ripples[] unused; all 3 rings + field lines follow the same global bands.
- signal-modulation: FAKE SPECTRAL BANDS - 'bandAmp' for the 8-band visualizer is
  driven by fract(sin()) hash noise, NOT plasmaBuffer FFT bins (fake-FFT-proxy bug
  class). Mouse read (wave phase proximity) but raw; ripples[] unused.
- holographic-shatter: TRIPLE BUG - (1) OOB palette read plasmaBuffer[palIdx % 256u]
  (same as b18 holographic-sticker); (2) DEAD 'Depth Weight' slider - z is read into
  depthWeight but depthLayeredAlpha() is NEVER CALLED; (3) inverted impact falloff -
  smoothstep(0.0, 0.6, dM) GROWS with mouse distance, so mouse-down shatters
  everything EXCEPT near the cursor.
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
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-briefs-2026-07-31-b19")
os.makedirs(OUT_DIR, exist_ok=True)

SHADERS = [
    {
        "id": "reactive-glass-grid",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This glass tile field is honest - every slider is real - but the cursor snaps, clicks do nothing, and every tile dances to the same global bass/treble. Give it weight, touch, and per-tile voices:",
        "techniques": [
            "Spring-damper the influence center (priority 1): ease the mouse target with a critically-damped spring (extraBuffer[133..136], [0..4] engine-reserved, [5..132] = engine FFT bins) so the glass bulge trails the cursor with weight; the raw clamped mouse stays the spring target.",
            "Click glass shockwaves: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying radial influence ring at its click point (expanding smoothstep band boosting `influence` + caustic sparkle, ~1.5s fade), so clicks send ripples through the tiles.",
            "Per-tile FFT voices: derive a bin index from the tile id (`u32(hash21(floor(gridUV)) * 8.0) % 8u + 1u`) and let that bin's `plasmaBuffer[bin].x` modulate that tile's caustic sparkle amplitude, so different tiles listen to different frequencies instead of all following global treble.",
        ],
        "caution": "CAUTION: preserve the bass_env/hash21 helpers, the refraction + chromatic dispersion tap structure (rUV/gUV/bUV), the fresnel rim, and the ior depth mapping VERBATIM - the glass look is hand-tuned. dataTextureA stays DISPLAY color (raw, never tonemapped). extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "ascii-glyph",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This glyph field advertises 'mouse-driven' in its features but NEVER READS THE MOUSE - zoom_config is completely unused. Wire the touch it's already promising:",
        "techniques": [
            "WIRE THE MOUSE (priority 1): add an aspect-corrected mouse lens - near the cursor, locally shrink glyphSize (denser, finer glyphs, e.g. `glyphSize /= 1.0 + mouseMask * 1.5` with smoothstep falloff ~0.3 radius) and lift charDensity so the image resolves into finer type under the pointer. Spring-damper the lens center (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so it glides.",
            "Click glyph scrambles: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple injects a decaying hash-scramble ring at its click point (add `rippleAge * rippleBand` into the glyphPattern hash seed so cells inside the band flip characters chaotically, ~1.2s fade), so clicks scatter the type.",
            "Fix the stale comments (comment-only): config.y is ripple COUNT (not 'ClickCount'), zoom_config.w is mouseDown (not 'Generic2'), and the header 'Category: stylize' is stale (JSON lives in geometric).",
        ],
        "caution": "CAUTION: preserve the hash12/bass_env helpers, the depth-luminance tiering (`depthLuma`), the bass beat-swap (`beatSwap`), and the cross/dot SDF glyph shape select VERBATIM - the typographic identity is hand-tuned. All 4 sliders are honestly wired - keep their roles EXACTLY (saved-preset contract). dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "temporal-phosphor-burn-motion-adaptive",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. This motion-adaptive phosphor burn is the real deal - honest decay params, proper history ring - but it's tagged 'mouse-driven' and never touches the mouse, and clicks do nothing. Give it touch without breaking the ring:",
        "techniques": [
            "Mouse phosphor lens (priority 1): near the cursor, locally bias the decay toward decayMax (longer trails, e.g. `decay = mix(decay, decayMax, mouseMask * 0.5)`, aspect-corrected smoothstep falloff ~0.3 radius) so moving the pointer over a region makes it burn brighter - the mouse 'charges' the phosphor. Also add the mouse distance into the motion term so cursor movement itself leaves a faint trail.",
            "Click burn stamps: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying bright ghost at its click point into the accumulation (`burned = max(burned, stampColor * exp(-age * 2.0))`, warm-tinted, ~2s fade), so clicks brand the screen like a CRT flash.",
            "Per-band decay drift: let the 8 FFT bins (`plasmaBuffer[bin + 1].x`, bin = vertical screen band `u32(uv.y * 8.0)`) subtly modulate decay per band (+-0.005 around the computed decay, clamped to [decayMin, 0.999]) so the trails breathe with the spectrum; keep it subtle enough that static areas still clear.",
        ],
        "caution": "CAUTION: the history-ring indexing ((historyHead + HISTORY_DEPTH - age) % HISTORY_DEPTH), binding 13 declaration, and the extraBuffer[4] historyHead read are ENGINE CONTRACTS - preserve VERBATIM. extraBuffer is READ-ONLY for this shader (engine owns [0..4]); do not write it. Keep the max()-based burn accumulation and the warmTint math verbatim; dataTextureA stays DISPLAY color (raw).",
    },
    {
        "id": "codebreaker-reveal",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This Matrix-rain reveal is honest - all four sliders are real - but the reveal circle snaps to the cursor and clicks are deaf. Make the reveal feel alive:",
        "techniques": [
            "Spring-damper the reveal center (priority 1): ease the mouse target with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the reveal circle sweeps after the cursor with momentum; the raw mouse stays the spring target. Keep the bass radius boost applied AFTER the spring so the punch stays instant.",
            "Click reveal bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple opens a temporary second reveal disc at its click point (same mask math as the cursor disc, radius growing then collapsing over ~1.5s, combined with the cursor mask via max()), so clicks punch holes in the code wall.",
            "Per-column treble shimmer: modulate each rain column's blink rate by a per-column FFT bin (`plasmaBuffer[(colIndex % 8u) + 1u].x` - note colIndex is f32, cast via u32(colIndex)) so the code wall glitters across the spectrum instead of blinking uniformly.",
        ],
        "caution": "CAUTION: preserve the hash12 helper, the matrix rain column/row math (fallSpeed, yFlow, charRandom, pixelCode), the luminance-driven matrixColor mix, and the edge ring glow VERBATIM - the code-wall identity is hand-tuned. Fix the stale comment config.y ('MouseClickCount' -> ripple count) comment-only. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "digital-reveal",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This rain-reveal has a real feedback trail (A=mask, C=prev mask - consistent, keep it) and honest sliders, but the brush snaps to the cursor, clicks do nothing, and the uniform comments lie. Tighten it up:",
        "techniques": [
            "Spring-damper the reveal brush (priority 1): ease the mouse target with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the brush paints with inertia; raw mouse stays the spring target. The feedback trail then naturally records swooping strokes.",
            "Click splash reveals: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple stamps a decaying reveal blob at its click point into the mask (`newVal = max(newVal, rippleBlob)` before the A write, radius ~0.15, ~2s fade), so single clicks splash-reveal content that then fades with trailFade.",
            "Honest depth-gated rain: `depthReveal` currently scales the mask only - also let depth subtly scale the rain glyph brightness in unrevealed regions (`rainColor *= mix(1.0, mix(0.6, 1.2, depth), 0.4)`) so near content glows through the rain, earning the 'depth-aware' feature tag. Fix the stale comments (comment-only): config.y = ripple COUNT (not 'MouseClickCount'), zoom_config.w = mouseDown (not 'Generic2').",
        ],
        "caution": "CAUTION: preserve the hash22/bass_env helpers, the mask feedback contract (dataTextureA stores (newVal,0,0,1); dataTextureC.r read as prev mask - it is NOT display color, never tonemap it), the rain column/charID/dropVal math, and the chromatic white-drop branch VERBATIM. All 4 sliders are honestly wired - keep their roles EXACTLY. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "magnetic-ring",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. These field rings are honestly wired (the JSON even carries explicit mapping fields) - but the ring center snaps to the cursor, clicks do nothing, and all three rings follow the same global audio bands. Make it magnetic for real:",
        "techniques": [
            "Spring-damper the ring center (priority 1): ease the mouse target with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the ring system drags after the cursor like a real magnet; raw mouse stays the spring target. Keep the aspect correction applied to the SPRUNG position.",
            "Click flux shockwaves: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a temporary fourth ring expanding from its click point (ringMask += decaying smoothstep band at radius age*0.4, ~1.5s fade) plus a local pulse boost, so clicks fire flux surges across the field.",
            "Per-ring FFT voices: drive ring i's pulse/glow from its own spectrum bin (`plasmaBuffer[i + 1u].x` for i in 0..2 - bass/mids/treble neighbors) instead of the single global `pulse`, so the concentric rings throb at different frequencies; the z slider stays the global pulse speed.",
        ],
        "caution": "CAUTION: preserve the hash21/bass_env helpers, the 3-ring loop structure (radii baseRadius*(1+i*0.6), fieldAngle 8/(i+1) spokes), the safeDir normalize guard, and the chromatic rUV/gUV/bUV tap structure VERBATIM. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "signal-modulation",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This signal shader's 8-band 'spectral' visualizer is a LIE - bandAmp is driven by fract(sin()) hash noise, not the FFT. The bins are sitting right there in plasmaBuffer. Make the bands honest, then give it touch:",
        "techniques": [
            "REAL FFT BANDS (priority 1): replace `bandNoise = fract(sin(band * 12.9898 + time) * 43758.5453)` with the actual bin amplitude (`plasmaBuffer[u32(band) + 1u].x`, bands 0-7 map to bins 1-8; band is f32 from floor() - cast it). Keep bandAmp's (1.0 + bass * 0.5) boost on top. The fake hash term can survive ONLY as a tiny +-10% jitter so the bars don't look digitized - the FFT must be the signal.",
            "Spring-damper the wave origin: ease the mouse target with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the proximity-warped carrier trails the cursor; raw mouse stays the spring target.",
            "Click carrier bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple injects a decaying signal spike at its click point (local boost to `signal` + extra chromatic offset in a radial band, ~1.2s fade), so clicks spike the waveform.",
        ],
        "caution": "CAUTION: preserve the bass_env and huePreserveClamp helpers (keep the 1.8 cap call), the carrier wave construction (wave/distanceToWave/signal smoothstep), the displacement + r/g/b chromatic tap structure, and the noise floor VERBATIM. All 4 sliders are honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "holographic-shatter",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This shatter has THREE bugs: an out-of-bounds palette read, a 'Depth Weight' slider that is completely dead (depthLayeredAlpha is never called), and an impact falloff that is inverted - pressing the mouse shatters everything EXCEPT where you click. Fix the plumbing:",
        "techniques": [
            "GUARD THE PALETTE READ + WIRE THE DEAD SLIDER (priority 1): (a) `plasmaBuffer[palIdx % 256u]` can index past the real FFT bin count (OOB storage reads return zeros - dead black palette); wrap to the live range instead (`(palIdx % 8u) + 1u`, bins 1-8). (b) depthWeight (zoom_params.z) is read but depthLayeredAlpha() is NEVER CALLED - the slider does nothing. Wire it: `finalAlpha = mix(baseColor.a, depthLayeredAlpha(finalColor, uv, depthWeight), clamp(effectIntensity, 0.0, 1.0))` so z blends between source alpha and the depth/luma-tiered alpha (default 0.5 keeps the alpha lively without flattening).",
            "FIX THE INVERTED IMPACT: `impact = (0.4 + mouseDown * 0.6) * smoothstep(0.0, 0.6, dM)` GROWS with distance from the mouse - mouse-down flings far shards while the cursor zone sits still. Invert the falloff to near-focused (`smoothstep(0.6, 0.0, dM)`) but keep a small global baseline (`impact = max(nearImpact, 0.25 * (0.4 + mouseDown * 0.6))`) so the idle/far-field drift survives.",
            "Click shatter detonations: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple acts as a decaying impact center (same flightDir math with the ripple position as origin, weight exp(-age * 2.5), ~1.5s), so individual clicks crack the glass even with the button up. Normalize the odd depth write `vec4(depth, 0, 0, 1)` to `vec4(depth, 0.0, 0.0, 0.0)` (depth value itself passthrough).",
        ],
        "caution": "CAUTION: preserve the rand() helper, the shard grid + edgeGlow construction, the holographic phase/palette sin() math (only the plasmaBuffer INDEX changes), the temporal settling (C read * 0.92, mix 0.06 + bass*0.02), and the depthLayeredAlpha helper body VERBATIM. dataTextureA stays DISPLAY color (raw - the C feedback expects color, not masks). extraBuffer (if used) in [133..255] ONLY.",
    },
]


def main():
    pool = scan_pool()
    picks = [e["id"] for e in pool[:8]]
    expected = [s["id"] for s in SHADERS]
    print("Batch 19 pool picks:", picks)
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
