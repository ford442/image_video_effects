#!/usr/bin/env python3
"""Generate 8 self-contained swarm briefs in swarm-tasks/kimi-briefs-2026-08-02-b26/.

Batch 26 (smallest-first all-category, wave 9): same theme as Batches 17-25 -
formalize updatedParams from EXISTING params (saved-preset contract), make each
slider drive meaningful shader-specific constants, +2-3 tailored techniques each,
+50-90 lines, gate green. Pool scan reused from the b17 generator (all categories,
multipass-safe).

ENGINE UNIFORM TRUTH (verified src/renderer/UniformBuffer.ts + webgpu/frame.ts):
  config      = [time, rippleCount, resW, resH]
  zoom_config = [time, mouseX, mouseY, mouseDown]  -> mouse = .yz, down = .w
  ripples guard: min(u32(u.config.y), 50u)
NOTE: docs/BINDING_CONTRACT.md claims config.y=delta_time - STALE, trust the TS source.

Recon notes baked in (2026-08-02, Batch 26) - ALL 8: ripples[] never read (clicks
dead), raw unsprung mouse, global plasmaBuffer[0].xyz only (no per-region FFT):
- temporal-frequency-decomposition: HISTORY-RING shader (binding 13, HISTORY_DEPTH=8,
  extraBuffer[4]=historyHead read). Tagged 'mouse-driven' but NEVER reads the mouse
  (zoom_config referenced only in the struct). Stale header extraBuffer map claims
  [0..2]=bass/mid/treble - engine actually writes FFT at [5..132]; [4]=historyHead
  (read-only). Depth is passthrough only. dataTextureA = display color.
- glass-wipes: JSON category liquid-effects, header comment says 'distortion' (stale).
  Wetness state contract: A=(wetness,0,0,wetness) write, C read as prev - engine-forced,
  keep exactly, never tonemap. plasmaBuffer declared but never sampled. zoom_params.w
  does double duty (evaporation + glassDensity) - keep both roles.
- interactive-zoom-blur: JSON category distortion, header says 'image' (stale). Raw
  mouse center; bayer-dithered 3-accumulator chromatic radial loop; temporal trail via
  C read; dataTextureA = display color.
- reality-tear: raw mouse (already aspect-corrected); branchless select() void/border;
  meaningful alpha formula; dataTextureA = display color.
- bubble-lens: raw mouse (aspect-corrected); thin-film drainage/turbulence/fresnel;
  dataTextureA stores MASK data (inside, drainedThickness*0.2, spec, finalAlpha) - NOT
  display color, keep packing verbatim.
- cross-mouse-spec-dispersion-lens: mouseDist NOT aspect-corrected (elliptical lens on
  wide canvas); treble declared? no - only bass/mids used; mouseDown binary clickBoost
  exists; Cauchy IOR + parabolic profile + rotation; dataTextureA = display color.
- laser-burn: state feedback SACRED - A=(charLevel, cooledHeat, emberLevel, burnAlpha)
  state write, C read as prev state; never tonemap the A write. Stale comments
  (config.y='ClickCount', zoom_config.w='Generic2'). Burn only while mouseDown.
- magnetic-luma-sort: dev thinking-out-loud comments are file personality (keep
  verbatim, like b21 interactive-emboss). DEAD CODE: finalColor computed (mix + max)
  then unused - `mixed` wins. plasmaBuffer declared but never sampled. C=history read,
  A=mixed history write (display=color feedback, keep contract).
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
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-briefs-2026-08-02-b26")
os.makedirs(OUT_DIR, exist_ok=True)

SHADERS = [
    {
        "id": "temporal-frequency-decomposition",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This 8-frame temporal DFT is tagged 'mouse-driven' but NEVER reads the mouse - the pointer does nothing and clicks do nothing. Wire the interaction it advertises:",
        "techniques": [
            "WIRE THE MOUSE (priority 1 - the feature tag is currently a lie): add a sprung analysis lens - ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved/historyHead, [5..132] = engine FFT) and near the lens (aspect-corrected smoothstep ~0.35 radius) sharpen the frequency response (energy *= 1.0 + lensMask * 0.8) and slightly widen the glow, so the cursor focuses the Fourier microscope. Raw mouse stays the spring target.",
            "Click tuning-fork pings: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple injects a decaying oscillation at its click point into the DFT accumulators (realAcc += cos(TAU * freq * age_frames) * pingMask * decay, imagAcc likewise with sin, where pingMask is an aspect-corrected ~0.2 radius smoothstep around the click and decay ~exp(-rippleAge * 1.5)), so clicks light up at the target frequency even in static scenes.",
            "Per-region FFT voices: split the screen into 8 vertical bands; each band's glow brightness rides its own bin (`plasmaBuffer[(band % 8u) + 1u].x * 0.4`) added to the global bass boost, so the spectrum shimmers spatially. Fix the stale header comment (comment-only): extraBuffer[0..2] are NOT bass/mid/treble - [4]=historyHead, [5..132]=engine FFT, persistent state in [133..255] only.",
        ],
        "caution": "CAUTION: this is a HISTORY-RING shader - binding 13 (historyTexture), the HISTORY_DEPTH=8 ring indexing `(historyHead + HISTORY_DEPTH - age) % HISTORY_DEPTH`, and the extraBuffer[4] historyHead read are SACRED (engine contract) - keep VERBATIM, extraBuffer[4] stays READ-ONLY. Preserve the DFT accumulation loop, the hue2rgb helper, the magnitude/energy math, and the base+glow composite VERBATIM. All 4 sliders honestly wired - keep roles EXACTLY (defaults bit-exact). dataTextureA stays DISPLAY color. Persistent state in extraBuffer[133..255] ONLY.",
    },
    {
        "id": "glass-wipes",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This rainy window has a working wiper and real Beer-Lambert physics - but the wiper snaps to the cursor, clicks never splash, and the audio uniform is declared yet never sampled. Make it feel alive:",
        "techniques": [
            "Spring-damper the wiper (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the wiper trails the hand with weight; raw mouse stays the spring target. Keep the aspect-corrected distance.",
            "Click splashes: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple stamps a wetness splash at its click point (wetness += 0.5 * aspect-corrected ~0.15 radius smoothstep, one-shot on young ripples, clamp wetness to 1.0), so clicks spatter rain onto the glass.",
            "Wire the dead audio: bass-driven rain bursts (rainIntensity *= 1.0 + bass * 0.8, so downpours follow the beat) and per-band droplet glint - 8 horizontal bands each sparkle their specular by `plasmaBuffer[(band % 8u) + 1u].x * 0.3`. Fix the stale header comment ('Category: distortion' -> liquid-effects, comment-only).",
        ],
        "caution": "CAUTION: the wetness state contract is SACRED - dataTextureA stores (wetness, 0, 0, wetness) STATE and dataTextureC is read as prev wetness; the engine only reads history via C - keep this packing EXACTLY and never tonemap the A write. Preserve the Beer-Lambert absorption, the Fresnel (R0=0.02), the thickness/transmission math, the droplet distortion noise, and the specular highlight VERBATIM. zoom_params.w intentionally double-duties (evaporation + glassDensity) - keep BOTH roles. All slider ids/names/defaults EXACTLY. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "interactive-zoom-blur",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. This dithered chromatic zoom blur is well-built but the blur epicenter snaps to the cursor and clicks never punch the tunnel. Precision work:",
        "techniques": [
            "Spring-damper the epicenter (priority 1): ease the mouse center with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the tunnel glides; raw mouse stays the spring target. The spring LAG also feeds a subtle motion bonus: strength *= 1.0 + min(springSpeed * 4.0, 0.5) so fast flicks smear harder.",
            "Click zoom shockwaves: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying radial blur pulse centered at its click point (local attenuatedStrength boost exp(-rippleAge * 2.0) in an aspect-corrected ~0.3 radius, ~1.2s fade), so clicks detonate secondary tunnels.",
            "Per-ring FFT voices: inside the sample loop, modulate each tap's weight by a bin selected from the fractional radius (`plasmaBuffer[(u32(t * 8.0) % 8u) + 1u].x * 0.15`), so blur rings shimmer across the spectrum. Fix the stale header ('Category: image' -> distortion, comment-only).",
        ],
        "caution": "CAUTION: preserve the bayer() 4x4 dither, the hash11 helper, the 3-accumulator r/g/b chromatic loop structure with its rSpread/gSpread/bSpread, the sample-count mapping, the depth attenuation, the temporal trail mix (C read, 0.88 decay), and the effectBlend smoothstep VERBATIM - the streak quality is hand-tuned. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "reality-tear",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This tear's void/burn/static composition is honest and branchless - but the rip center snaps to the cursor and clicks never open secondary rifts. Give reality more wounds:",
        "techniques": [
            "Spring-damper the tear center (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the tear drifts with menace instead of snapping; raw mouse stays the spring target. Keep the existing aspect correction.",
            "Click rifts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple opens a small secondary tear at its click point (same void/border/select pipeline evaluated against a radius that grows then collapses over ~1.5s, max radius ~0.15, branchless select() composition with the main tear), so clicks puncture extra holes in reality.",
            "Angular FFT voices: modulate the jagged noiseVal by angular sector bins (`plasmaBuffer[(u32((angle + PI) / TAU * 8.0) % 8u) + 1u].x * 0.3`) so different sectors of the tear edge writhe to different frequencies, and let treble bins 5-8 flicker the burn color per sector instead of only global treble.",
        ],
        "caution": "CAUTION: preserve the hash21/valueNoise2D helpers, the dual-octave angular noise, the currentRadius construction, the branchless select() void/border composition, the void static/inverted mix, and the meaningful-alpha formula VERBATIM - the tear identity is hand-tuned. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY. Keep new logic branchless (select/step/smoothstep).",
    },
    {
        "id": "bubble-lens",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This bubble's thin-film drainage and fresnel rim are genuinely physical - but the bubble snaps to the cursor and clicks never pop it. Give the soap some life:",
        "techniques": [
            "Spring-damper the bubble (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the bubble floats after the cursor with buoyancy; raw mouse stays the spring target. Keep the aspect-corrected delta.",
            "Click pops and satellite bubbles: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple spawns a small satellite bubble at its click point (radius ~0.06 growing then popping over ~1.2s - reuse the same lens displacement + interference evaluation at reduced strength) AND pops a brief film-shockwave on the main bubble (drainedThickness perturbation ring expanding from the click side), so clicks ripple the soap film.",
            "Per-octave FFT shimmer: modulate the two turbulence noise octaves by different bins (plasmaBuffer[2].x for the broad octave, plasmaBuffer[6].x for the fine octave, +-15%), so the film interference dances across the spectrum; keep audio.x on filmThickness and audio.y on spec as now.",
        ],
        "caution": "CAUTION: dataTextureA stores MASK data (inside, drainedThickness*0.2, spec, finalAlpha) - NOT display color - keep that packing VERBATIM. Preserve the safeNormalize helper, the lens displacement math, the drainage/turbulence/drainedThickness construction, the 3-phase interference cosines + blackSpot, the fresnel (Schlick from ior), the rim/spec terms, and the transmittance/alpha clamps VERBATIM - the soap physics are hand-tuned. All 4 sliders honestly wired - keep roles EXACTLY. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "cross-mouse-spec-dispersion-lens",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This Cauchy-dispersion lens has two problems: the lens is ELLIPTICAL on any non-square canvas (mouseDist never aspect-corrects) and treble sits unused while bass/mids do all the work. Fix the geometry, then the spectrum:",
        "techniques": [
            "ASPECT-CORRECT THE LENS (priority 1): `mouseDist = length(toMouse)` ignores aspect - on wide canvases the 'circular' lens is an ellipse; correct both uv and mousePos by (aspect, 1.0) before the distance (and use the same corrected vector for the refraction normal so dispersion stays radial). Verify the rim gaussian uses the corrected distance.",
            "Spring-damper + wire treble: ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the prism glides; raw mouse stays the spring target. Wire the unused treble: per-channel sparkle - the dispR/dispB split shimmers by `plasmaBuffer[6].x * 0.3` and `plasmaBuffer[8].x * 0.3` respectively, so high frequencies twinkle the fringes.",
            "Click spectrum flares: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple fires a decaying dispersion burst at its click point (local localDispersion spike exp(-rippleAge * 2.0) * 1.5 in an aspect-corrected ~0.25 radius, ~1.2s fade) plus a brief spectral ring at the burst edge, so clicks scatter rainbows beyond the held-button boost.",
        ],
        "caution": "CAUTION: preserve the cauchyIOR helper, the n0/B constants, the 650/530/460nm wavelengths, the parabolic lensProfile, the time-rotation matrix, the per-channel r/g/b sample split, and the rim gaussian form VERBATIM - the spectral physics are the identity. The mouseDown clickBoost (select 1.0/2.0) stays. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "laser-burn",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This burn sim's char/heat/ember state machine is solid - but the beam snaps to the cursor and clicks (mouseDown is the ONLY burn trigger) never brand a lasting mark. Give the laser some weight:",
        "techniques": [
            "Spring-damper the beam (priority 1): ease the mouse with a HEAVY critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT, omega ~6) so the beam lags the hand like real hardware; raw mouse stays the spring target. The lag streak naturally extends burn paths.",
            "Click brand stamps: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple sears a brand at its click point (heatLevel += 0.6 * aspect-corrected ~0.08 radius smoothstep * exp(-rippleAge * 1.5), one pulse), so single clicks tattoo the surface without holding the button. These feed the SAME char/ember pipeline.",
            "Per-region spark bins: divide the beam zone into 8 angular sectors around the beam center; each sector's sparkChance threshold rides its own bin (`plasmaBuffer[(sector % 8u) + 1u].x`) instead of only global treble, so spark showers dance around the beam. Fix the stale comments (comment-only): config.y = ripple COUNT, zoom_config.w = mouseDown (not 'Generic2').",
        ],
        "caution": "CAUTION: the burn state contract is SACRED - dataTextureA stores (charLevel, cooledHeat, emberLevel, burnAlpha) STATE and dataTextureC is read as prev state; the engine only reads history via C - keep this packing EXACTLY and never tonemap/clamp the A write beyond the existing clamps. Preserve the hash12/bass_env helpers, the heat->char->ember accumulation math, the healFactor/ember decay, the fireColor/emberColor/sparkColor ramps, and the burnAlpha formula VERBATIM. All 4 sliders honestly wired - keep roles EXACTLY. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "magnetic-luma-sort",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This luma-flow feedback has a corpse in the code: `finalColor` is computed two different ways and then THROWN AWAY (`mixed` is what actually gets stored) - and the audio uniform is declared but never sampled. Clean up, then wire it:",
        "techniques": [
            "REMOVE THE DEAD finalColor (priority 1): the `finalColor = mix(...)` then `finalColor = max(...)` lines compute a value nothing reads - delete them (the dev commentary explaining the approach STAYS - it is this file's personality, comments verbatim). No behavior change: `mixed` already wins.",
            "Spring-damper the attractor + click vortex pulses: ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the magnet glides; raw mouse stays the spring target. Loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying second attractor at its click point (speed contribution from a smoothstep falloff ~0.25 radius, exp(-rippleAge * 2.0)), so clicks stir the flow; compose with the main pull before the offset.",
            "Wire the dead audio: bass lowers the effective luma threshold (threshold * (1.0 - bass * 0.3), so beats loosen the sort) and per-row FFT drift - 8 horizontal bands each scale their speed by `plasmaBuffer[(band % 8u) + 1u].x * 0.4`, so the smear dances across the spectrum.",
        ],
        "caution": "CAUTION: the feedback contract is SACRED - dataTextureC is read as history at the upstream offset, dataTextureA is written with `mixed` (history feedback AND display color, same value) - keep this exactly, never tonemap the A write. Preserve ALL the dev thinking-out-loud comments VERBATIM (file personality, same as b21 interactive-emboss/mouse-gravity), the get_luma helper, the threshold speed gate, the aspect correction, and the attract/repel step VERBATIM. All 4 slider ids/names/defaults/ranges EXACTLY (Trail Decay range 0.5-0.99!). extraBuffer in [133..255] ONLY.",
    },
]


def main():
    pool = scan_pool()
    picks = [e["id"] for e in pool[:8]]
    expected = [s["id"] for s in SHADERS]
    print("Batch 26 pool picks:", picks)
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
