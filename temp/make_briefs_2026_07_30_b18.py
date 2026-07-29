#!/usr/bin/env python3
"""Generate 8 self-contained swarm briefs in swarm-tasks/kimi-briefs-2026-07-30-b18/.

Batch 18 (smallest-first all-category, wave 2): same theme as Batch 17 - formalize
updatedParams from EXISTING params (saved-preset contract), make each slider drive
meaningful shader-specific constants, +2-3 tailored techniques each, +50-90 lines,
gate green. Pool scan reused from the b17 generator (all categories, multipass-safe).

Recon notes baked in (2026-07-30, Batch 18):
- neural-nexus: wiring real; raw clamped mouse (no glide); ripples unused; all
  neurons follow the same global bass/treble.
- prismatic-feedback-loop: ALL 4 JSON labels mismatch the WGSL roles ('Feedback'
  drives accumulationRate, 'Blur Radius' drives prism strength, 'Glow Intensity'
  drives rotation, 'Chromatic Spread' default 0.02 drives the feedback mix).
  Header says 'Category: image', JSON lives in interactive-mouse (stale).
- neon-topology: MISLABELED + DEAD - 'Height Scale' (y) drives an alpha-helper edge
  threshold, 'Mouse Force' (w) drives hue shift, and the MOUSE IS NEVER READ despite
  the 'mouse-driven' tag. Dead `alpha` variable (computed, unused - finalAlpha
  computed separately).
- temporal-slit-scan: SPECIAL - uses binding 13 (historyTexture ring) + reads
  extraBuffer[4] historyHead (engine-owned [0..4] - read-only is fine).
  param1-4 generic ids but honestly mapped. Mouse tagged but unused.
- spectral-distortion: wiring real; stale uniform comments ('Generic2'); branchless
  style is good.
- fireworks-portrait-burst: REAL BUG - mouse burst converts zoom_config.yz
  (normalized 0..1) as PIXEL coords: (mouse - res*0.5)/min(res) lands off-screen -
  the click burst never appears where clicked. Also writeDepthTexture stores flat
  0.0 (depth clobber, cosmic-jellyfish bug class).
- holographic-sticker: plasmaBuffer[palIdx % 256u] palette read can exceed the FFT
  bin count (OOB risk); raw mouse; depth parallax advertised but not used spatially.
- neural-resonance: MASK-AS-COLOR FEEDBACK BUG (spore-galaxy class, Batch 14) -
  dataTextureA stores (mouseMask, feedbackMix, |curl|*10, alpha) MASKS but the
  shader reads dataTextureC (prev A) as COLOR feedback - the feedback loop mixes
  masks into the display. |curl|*10 in the blue channel is arbitrary HDR.
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
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-briefs-2026-07-30-b18")
os.makedirs(OUT_DIR, exist_ok=True)

SHADERS = [
    {
        "id": "neural-nexus",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This neural field is honest but every neuron dances to the same global bands and clicks do nothing - give each neuron its own voice and make clicks fire synapses:",
        "techniques": [
            "Click synapse bursts (priority 1): the ripples[] uniform is unused. Loop it (guard `min(u32(u.config.y), 50u)`) - each live ripple acts as a temporary extra 'neuron' at its click point injecting a decaying pulse wave into `activity` (age = time - ripple.z, ~2s fade), so clicks visibly fire the network.",
            "Spring-damper the signal origin: ease the mouse target with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so signal waves propagate from a gliding cursor rather than a snapping one; the raw clamped mouse stays the spring target.",
            "Per-neuron FFT voices: derive a bin index from the neuron seed (`u32(hash(...)*8.0) % 8u + 1u`) and let that bin's `plasmaBuffer[bin].x` modulate that neuron's pulse amplitude, so different neurons listen to different frequencies instead of all following global bass.",
        ],
        "caution": "CAUTION: preserve the neuron hash placement, the dendrite cos() structure, and the sampleUV displacement VERBATIM - the network identity is hand-tuned. dataTextureA stores (totalActivity, sparks, mousePulse, alpha) mask data - keep that packing, it is not display color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "prismatic-feedback-loop",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. Every one of this shader's four slider labels is a lie - 'Feedback' drives the accumulation rate, 'Blur Radius' drives prism strength, 'Glow Intensity' drives rotation, and 'Chromatic Spread' (default 0.02!) drives the feedback mix. Make the labels honest:",
        "techniques": [
            "REWIRE THE MISLABELED SLIDERS (priority 1): x ('Feedback', default 0.5) must drive the temporal feedback mix `mix(prev.rgb, prismColor, x)`; y ('Blur Radius', default 1) must drive the prism tap spread magnitude (reads as a blur/soften - map so default 1 reproduces the current ~0.1 offset scale); z ('Glow Intensity', default 0.8) must drive a real glow term (brightness lift of the accumulated trails, 0 at 0); w ('Chromatic Spread', default 0.02) must scale the chromatic r/b separation angle/amount (small default = subtle, matching its tiny default). Keep ids/names/defaults EXACTLY (saved-preset contract). The old rotation role can become a slow constant drift (time * 0.1).",
            "Fix the stale header comment claiming 'Category: image' (JSON lives in interactive-mouse) - comment-only.",
            "Click prism bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying radial chromatic kick centered on its click point (extra r/b separation fading over ~1.5s), so clicks shatter the prism locally.",
        ],
        "caution": "CAUTION: preserve the accumulativeAlpha() function and its select-based zero-guard VERBATIM - feedback stability depends on it. dataTextureA is ACCUMULATION STATE - never tonemap/clamp it beyond the existing caps; keep the A write and C read symmetric. Guard the feedback mix so values stay in [0,1] (runaway feedback blowout is the classic failure mode here).",
    },
    {
        "id": "neon-topology",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This contour shader is tagged 'mouse-driven' but NEVER READS THE MOUSE - and two of its four sliders are lies. Fix the contract:",
        "techniques": [
            "WIRE THE MOUSE + REWIRE THE LIES (priority 1): w ('Mouse Force', default 0.5) currently drives hue shift and the mouse is unread - make w drive a real mouse lens: bump the sampled depth near the cursor (`depth += mouseMask * w * 0.25`, aspect-corrected smoothstep falloff ~0.35 radius) so contours warp around the pointer. y ('Height Scale', default 0.5) currently drives the alpha helper's edge threshold - make it scale the contour field height (`contourPhase = depth * mix(0.5, 2.0, y) * contourLevels`, default 0.5 = factor 1.25; verify the default look stays close). Move the hue shift to a slow constant drift (time * 0.15) so the color identity survives.",
            "Remove the dead `alpha` variable (computed, never used - finalAlpha is computed separately). Fold anything useful from it into finalAlpha explicitly.",
            "Click contour quakes: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying depth ripple ring at its click point (expanding sinusoidal bump, ~1.5s), so clicks drop pebbles into the topology.",
        ],
        "caution": "CAUTION: preserve the branchless contour construction (fract phase + smoothstep lines + major step), the edgePreserveAlpha 5-tap depth helper, and the phantom-contour audio term VERBATIM in structure - they are the shader's identity. dataTextureA stays DISPLAY color. extraBuffer (if used) in [133..255] ONLY.",
    },
    {
        "id": "temporal-slit-scan",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. This slit-scan is clean and honest - but it's tagged mouse-driven and never uses the mouse, and clicks do nothing. Give it touch without breaking the history ring:",
        "techniques": [
            "Mouse scan pivot (priority 1): let the mouse position along the scan axis set WHERE the current-frame edge lives (instead of fixed at scanPos=1) - pixels on one side read progressively older history, the other side reads progressively younger... or simpler and truer to slit-scan: mouse sets the pivot column/row that shows the live frame, with age ramping away from it in both directions (tent map). Keep the axis/reverse params working on top.",
            "Click temporal tears: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple locally deepens the history offset near its click point (a radial 'tear' that reaches further back in the ring, decaying ~1.5s), so clicks smear time locally.",
            "Per-column spectral jitter: add a subtle per-scan-column offset jitter driven by FFT bins (`plasmaBuffer[(col % 8) + 1].x * mids-weighted`) so the smear shimmers with the spectrum; keep it sub-frame (max 1 extra history step) so the smear stays smooth.",
        ],
        "caution": "CAUTION: the history-ring indexing ((historyHead + HISTORY_DEPTH - t_offset) % HISTORY_DEPTH) and extraBuffer[4] historyHead read are ENGINE CONTRACTS - preserve VERBATIM. Keep binding 13 (historyTexture) declared exactly as-is. extraBuffer is READ-ONLY for this shader (engine owns [0..4]); do not write it. Respect the branchless select() style for scanPos.",
    },
    {
        "id": "spectral-distortion",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This warp field is honest and branchless - give the mouse weight, clicks a punch, and each channel its own frequency:",
        "techniques": [
            "Spring-damper the influence center (priority 1): ease the mouse target with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the warp blob trails the cursor with weight; keep the branchless mouseActive gate (step(0.0, mousePos.x)) applied to the RAW mouse before springing.",
            "Click warp bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying radial warp impulse centered on its click point (an expanding ring that locally boosts warpStr, ~1.2s fade), branchless (smoothstep bands, no if).",
            "Per-channel bin separation: drive the R offset from `plasmaBuffer[3].x` and the B offset from `plasmaBuffer[7].x` (different spectrum regions) instead of one global separation term, so the chromatic tear shimmers across the spectrum; the slider stays the base separation amount.",
        ],
        "caution": "CAUTION: preserve the value_noise helper, the three nR/nG/nB field taps with their (t, t+10, -t) offsets, and the branchless select()/step() style VERBATIM (docs/BRANCHLESS_PATTERNS.md). Fix the stale uniform comments (config.y = ripple COUNT, zoom_config.w = mouseDown, not 'Generic2') - comment-only. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "fireworks-portrait-burst",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This firework shader's click burst is aimed at the wrong sky - the mouse coordinate math treats normalized [0,1] coords as pixels, so bursts detonate off-screen. Fix the aim, then the depth:",
        "techniques": [
            "FIX THE MOUSE COORD BUG (priority 1): `let mUV = (u.zoom_config.yz - res*0.5)/min(res.x,res.y);` - zoom_config.yz is NORMALIZED [0,1], subtracting res*0.5 (hundreds of pixels) puts mUV far off-screen, so the held-click burst never appears at the cursor. Correct: `let mUV = (u.zoom_config.yz * res - res * 0.5) / min(res.x, res.y);`. Verify the burst then centers on the cursor.",
            "Honest depth: writeDepthTexture currently stores flat 0.0, clobbering chain depth (cosmic-jellyfish bug class) - write a real depth: luminance-derived (`clamp(dot(col, lumWeights) * 0.8 + sparkGlow * 0.2, 0.0, 1.0)`) so bright bursts sit forward.",
            "Click ripple bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple ALSO spawns a one-shot spark burst at its click point (same spark pipeline as the mouse burst, age = time - ripple.z), so individual clicks fire without holding the button. Keep the existing held-mouse auto-repeat.",
        ],
        "caution": "CAUTION: preserve the spark physics (sparkPos gravity, softGlow falloff, hash1 seeds, 7-probe loop, ACES tonemap) VERBATIM - the pyrotechnics are hand-tuned. dataTextureA/B roles (display state / dimmed echo) must stay raw - never re-tonemap them. The `continue` guards in the probe loop are intentional perf structure - keep them.",
    },
    {
        "id": "holographic-sticker",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This foil sticker has an out-of-bounds palette risk and a static feel - guard the read, then make it glide and flash:",
        "techniques": [
            "GUARD THE PALETTE READ (priority 1): `plasmaBuffer[palIdx % 256u]` can index past the actual FFT bin count (the engine publishes far fewer vec4 bins) - OOB storage reads return zeros (dead black palette). Wrap to the real bin range instead (`(palIdx % 8u) + 1u`, bins 1-8) so the palette modulation is always live audio data.",
            "Spring-damper the sticker: ease the mouse center with a critically-damped spring (extraBuffer[133..134], [0..4] reserved, [5..132] = engine FFT) so the foil glides after the cursor; raw mouse stays the spring target.",
            "Click foil flashes: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds an expanding iridescent flash ring (hue-cycling band matching the foil palette, decaying ~1.5s) centered on its click point, so clicks scatter rainbows.",
        ],
        "caution": "CAUTION: preserve the HSV foil construction (k-vec palette math), the viewAngle hue mapping, and the depthLayeredAlpha helper VERBATIM. The temporal shimmer (C read / A write) must stay subtle and raw - never tonemap the A write. The odd `vec4(depth, 0, 0, 1)` depth write is harmless - you may normalize it to (depth,0,0,0) but keep depth itself passthrough. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "neural-resonance",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This shader's feedback loop is drinking its own mask buffer - dataTextureA stores MASKS (mouseMask, feedbackMix, |curl|*10) but dataTextureC (prev A) is read back as COLOR, so the temporal feedback mixes masks into the display (spore-galaxy bug class). Fix the plumbing:",
        "techniques": [
            "FIX THE MASK-AS-COLOR FEEDBACK (priority 1): write the DISPLAY color to dataTextureA (so C = previous frame's color, which is what the feedback path expects) and move the mask quad (mouseMask, feedbackMix, |curl|*10, alpha) to dataTextureB. Same fix as Batch 14's spore-galaxy. After the fix, verify feedbackMix blending reads as intended (default 0.55 -> mix factor mix(0.25,0.96,0.55) ~ 0.64) and the |curl|*10 blue-channel garbage is out of the display path.",
            "Spring-damper the mouse mask: ease the mouse center with a critically-damped spring (extraBuffer[133..134]) so the warp emphasis glides; raw mouse stays the spring target.",
            "Click resonance rings: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple injects a decaying expanding ring into the feedback (a bright synapseTint band at radius age*0.5, ~1.5s fade) centered on its click point, so clicks ring through the resonance.",
        ],
        "caution": "CAUTION: preserve the curlField/noise helpers, the aspect-corrected warp, and the synapseTint sin() palette VERBATIM. dataTextureA becomes DISPLAY color (raw, never tonemapped); dataTextureB becomes the mask quad (keep the same 4 values in the same order). extraBuffer in [133..255] ONLY.",
    },
]


def main():
    pool = scan_pool()
    picks = [e["id"] for e in pool[:8]]
    expected = [s["id"] for s in SHADERS]
    print("Batch 18 pool picks:", picks)
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
