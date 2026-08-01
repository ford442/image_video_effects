#!/usr/bin/env python3
"""Generate 8 self-contained swarm briefs in swarm-tasks/kimi-briefs-2026-07-31-b20/.

Batch 20 (smallest-first all-category, wave 4): same theme as Batches 17-19 -
formalize updatedParams from EXISTING params (saved-preset contract), make each
slider drive meaningful shader-specific constants, +2-3 tailored techniques each,
+50-90 lines, gate green. Pool scan reused from the b17 generator (all categories,
multipass-safe).

Recon notes baked in (2026-07-31, Batch 20):
- luma-topography: JSON labels HONEST (Relief Height/Light Intensity/Shininess/
  Ambient all match roles) - but the WGSL struct comment lies (x=Strength,
  y=Radius, z=Aberration, w=Darkness) and the header says 'Category: image' while
  the JSON lives in interactive-mouse. Mouse light raw (no glide); ripples unused;
  depth sampled but passthrough-only (not used in the lighting).
- scanline-drift: honest wiring; only mouse.y read (mouse.x/mouseDown/ripples
  unused); odd depth write vec4(depth,0,0,1.0); stale header category 'image'
  (JSON in retro-glitch).
- sonar-pulse: honest wiring; ripples[] UNUSED - in a SONAR shader (click pings
  are the thematic jackpot); sonar origin snaps to cursor; stale comments
  (config.y='ClickCount', zoom_config.w='Generic2').
- cyber-halftone-scanner: OOB palette read plasmaBuffer[palIdx % 256u] (3rd case -
  b18 holographic-sticker, b19 holographic-shatter); dead PHI const; mouse/ripples
  unused (not advertised as mouse-driven - keep additions optional-flavored).
- neon-edge-reveal: ALL 4 JSON labels generic/wrong ('Intensity'->reveal radius,
  'Speed'->edge boost, 'Scale'->glow intensity, 'Detail'->occlusionBalance which
  only affects ALPHA); UNCLAMPED HDR emission (glow*edgeBoost*glowIntensity can
  reach ~20 - kaleido-portal class); neon hue-cycle speed hardcoded (time*2.0);
  mouse flashlight raw; stale header category 'lighting-effects' (JSON in
  visual-effects).
- spectral-rain: honest wiring; mids + treble declared but NEVER USED (dead audio
  reads); mouse drives global angle/speed raw; ripples unused.
- lenticular-holographic-shift: honest wiring (non-0..1 ranges); dataTextureA
  stores MASKS (strip, moire, viewAngle, alpha) instead of display color (A-role
  violation - C unread here so latent, but chains expect display in A); mouse.y +
  ripples unused.
- long-exposure: FAKE GLOW RADIUS - gOff computed from the slider but NEVER USED;
  the 'bloom' is a fixed 3x3 +-1-texel blur regardless of glowRadius (dead var
  bug class); mouse POSITION unread (only mouseDown global reset - description
  promises click reset); ripples unused; stale header category 'temporal' (JSON
  in post-processing).
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
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-briefs-2026-07-31-b20")
os.makedirs(OUT_DIR, exist_ok=True)

SHADERS = [
    {
        "id": "luma-topography",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This relief-lighting shader's JSON labels are honest - but its own struct comment lies about the param roles, the mouse light snaps, clicks do nothing, and the depth buffer is sampled then ignored by the lighting. Polish the terrain:",
        "techniques": [
            "Spring-damper the light source (priority 1): ease the mouse light position with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the light sweeps across the relief with weight; raw mouse stays the spring target. Keep the attenuation falloff computed from the SPRUNG position.",
            "Click fill-light flashes: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying point light at its click point (same Blinn-Phong path as the mouse light, warm tint, ~1.5s fade, contributes to diff+spec additively), so clicks strike matches across the terrain.",
            "Depth-aware lighting + comment fixes: use the sampled depth to bias the pixel height (`pixelPos3D.z = luma * 0.2 + depth * 0.1`) so near geometry catches more specular - earns the depth read. Fix the stale comments (comment-only): zoom_params roles are x=ReliefHeight, y=LightIntensity, z=Shininess, w=Ambient (per the JSON); header 'Category: image' is stale (JSON lives in interactive-mouse); config.y = ripple COUNT.",
        ],
        "caution": "CAUTION: preserve the getLuma helper, the 2-tap luma gradient normal, the Blinn-Phong (diff/spec/H) math, the attenuation curve, and the warm lightColor mids shimmer VERBATIM - the relief look is hand-tuned. All 4 sliders are honestly wired - keep roles EXACTLY (saved-preset contract). dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "scanline-drift",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. This tracking-error drift is clean and honest - but it only reads mouse.y, ignores clicks entirely, and ships an odd depth-write alpha. Give it full touch without breaking the VHS feel:",
        "techniques": [
            "Spring-damper the tracking band (priority 1): ease mouse.y with a critically-damped 1D spring (extraBuffer[133..134], [0..4] reserved, [5..132] = engine FFT) so the jitter band glides vertically instead of snapping; raw mouse.y stays the spring target. Add a mouse.x term: horizontal proximity to each strip's displaced edge subtly boosts that strip's drift (keeps 'mouse-driven' honest in both axes).",
            "Click tracking tears: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple forces a hard horizontal tear on the strips near its click row (a one-shot offset spike decaying over ~0.8s, plus a brief colorShift doubling), so clicks slam the tracking.",
            "Normalize the depth write: `vec4(depth, 0.0, 0.0, 1.0)` -> `vec4(depth, 0.0, 0.0, 0.0)` (depth value passthrough; r32float only stores .r anyway). Fix the stale header comment ('Category: image' -> retro-glitch, comment-only).",
        ],
        "caution": "CAUTION: preserve the hash11 helper, the strip construction (stripId/stripRand), the sin-drift + mouse-jitter offset math, the fract-wrapped r/g/b taps, and the lineDark boundary smoothsteps VERBATIM - the VHS identity is hand-tuned. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "sonar-pulse",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This is a SONAR shader that ignores the ripples uniform - clicks should fire pings! The origin also snaps to the cursor. Give the sonar its voice:",
        "techniques": [
            "CLICK PINGS (priority 1): loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple is a sonar emitter at its click point: an expanding ring at radius age * 0.6 with the shader's own pulse smoothstep profile (reuse waveWidth), intensity exp(-age * 2.0), ~2s life, adding to pulseStrength AND the chromatic echo + distortion, so every click fires a visible ping that sweeps the image.",
            "Spring-damper the sonar origin: ease the mouse position with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the main emitter glides; raw mouse stays the spring target. Keep aspect correction on the SPRUNG position.",
            "Per-ring spectral shimmer: modulate the pulse color by FFT bins - ring phase proximity picks bins 1-8 (`plasmaBuffer[(ringIdx % 8u) + 1u].x` where ringIdx derives from floor(phase / 6.28318)) tinting pulseColor between the green sonar and the violet beat colors, so the rings shimmer across the spectrum. Fix stale comments (comment-only): config.y = ripple COUNT, zoom_config.w = mouseDown.",
        ],
        "caution": "CAUTION: preserve the bass_env helper, the phase/pulse/falloff core, the interference beat construction (phase2/beat/beatMask), the safeDist normalize guard, and the r/g/b chromatic echo taps VERBATIM. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "cyber-halftone-scanner",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This halftone's plasma tint reads out of bounds - `plasmaBuffer[palIdx % 256u]` indexes past the real FFT bin count and gets zeros (dead black tint). Third sighting of this bug class. Guard it, then give the scanner a pulse:",
        "techniques": [
            "GUARD THE PALETTE READ (priority 1): wrap the palette index to the live bin range (`(palIdx % 8u) + 1u`, bins 1-8) so the scan stripe tint is always real audio data. Remove the dead PHI constant (or use it - your call, but no unused consts).",
            "Click scan bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple spawns a secondary horizontal scanline sweeping from its click row (same exp(-d^2 * 90) profile, vertical velocity +-0.5 choosing direction by hash of the click position, ~1.5s fade), so clicks fire scanner sweeps.",
            "Mouse proximity dot bloom (optional flavor, this shader isn't tagged mouse-driven): near the cursor, locally raise `boost` (+0.15 smoothstep falloff ~0.25 radius) so dots bloom under the pointer like a magnifying lamp. Also modulate the scan stripe intensity by its vertical FFT band (`plasmaBuffer[u32(scanY * 8.0) + 1u].x`) so the sweep carries the spectrum.",
        ],
        "caution": "CAUTION: preserve the grid() helper, the canonical CMYK screen angles (15/75/0/45 + 1.05 K-scale), the step()-based halftone thresholding, the cyber tint palette (cyan/magenta/yellow + K darken), and the scanline exp profile VERBATIM. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer (if used) in [133..255] ONLY.",
    },
    {
        "id": "neon-edge-reveal",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. Every one of this shader's four slider labels is a placeholder - 'Intensity' drives the reveal radius, 'Speed' drives edge boost, 'Scale' drives glow, and 'Detail' only tweaks alpha. Meanwhile the emission is unclamped HDR that can hit ~20x. Rewire honest, then tame the blowout:",
        "techniques": [
            "REWIRE THE GENERIC LABELS (priority 1 - saved-preset contract: ids/names/defaults stay EXACTLY, only the WGSL roles change; default 0.5 must reproduce the current look): x ('Intensity', 0.5) -> emission/glow intensity (takes over glowIntensity's role: *2.0 mapping, default = x1.0); y ('Speed', 0.5) -> the neon hue-cycle speed (currently hardcoded time*2.0 - map mix(0.0, 4.0, y), default 0.5 = 2.0 bit-identical); z ('Scale', 0.5) -> reveal radius scale (takes over revealRadius's role: (0.2 + z * 0.3), default = 0.35 exactly as today); w ('Detail', 0.5) -> edge detail (Sobel smoothstep window: smoothstep(mix(0.10, 0.02, w), mix(0.5, 0.15, w), edgeStrength), default 0.5 = current 0.05/0.3 window). The old edgeBoost role folds into the emission chain as a constant 1.0 factor (its (1.0 + treble * 0.3) audio term moves onto the emission). occlusionBalance's alpha role can stay on w's alpha term OR ride along - document your choice.",
            "TAME THE HDR: the emission chain neonColor * glow * edge * edgeBoost * glowIntensity can reach ~19.8 - add a hue-preserving soft-knee (e.g. e / (1.0 + max(e - 1.5, 0.0) * 0.5) per-channel-max style, or the huePreserveClamp pattern) capping ~1.5-2.0 so the neon blows out gracefully instead of clipping to white.",
            "Click flare bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple flashes the reveal (temporary revealFalloff boost at its click point, ~1.2s fade) so edges near clicks ignite. Spring-damper the flashlight (extraBuffer[133..136]) so the beam glides.",
        ],
        "caution": "CAUTION: preserve the 9-tap Sobel (full vec4 neighbor samples, clamped), the neonColor1/2 palette + mixFactor cycling structure, and the branchless emission style VERBATIM - only the hardcoded speed constant and the param roles change. Fix the stale header comment ('Category: lighting-effects' -> visual-effects, comment-only). dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "spectral-rain",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This chromatic rain reads bass but declares mids and treble and NEVER USES THEM - dead audio reads. The rain angle/speed snap with the mouse. Make the whole spectrum fall:",
        "techniques": [
            "Per-column FFT voices (priority 1): kill the dead mids/treble reads by giving each rain column its own bin (`plasmaBuffer[(u32(gridID.x) % 8u) + 1u].x` - gridID.x is f32, cast it): bin amplitude modulates that column's drop brightness (`bright` term) and trail length (+-20%), so the streaks shimmer across the spectrum instead of all following global bass.",
            "Spring-damper the rain controls: ease the mouse-derived angleVal/speedVal with critically-damped springs (extraBuffer[133..138]: angle pos+vel, speed pos+vel; [0..4] reserved, [5..132] = engine FFT) so direction changes sweep smoothly; raw mouse stays the spring target.",
            "Click splash bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a radial chromatic splash at its click point (a decaying displace kick ~0.03 amplitude, ~1.0s fade, along the aspect-corrected radial direction), so clicks splatter the rain.",
        ],
        "caution": "CAUTION: preserve the hash12 helper, the rotated-grid rain construction (rotMat/rotUV/gridUV/colSpeed/dropNoise/drop), the displace vec2(s,c) structure, and the r/g/b samplePos/sampleNeg taps VERBATIM. All 4 sliders honestly wired - keep roles EXACTLY (note rain_angle_scale's 0-1.5 range). dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "lenticular-holographic-shift",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This lenticular print stores MASKS in dataTextureA (strip, moire, viewAngle, alpha) instead of display color - the A slot is for display, masks belong in B. Fix the plumbing, then give the view a glide:",
        "techniques": [
            "FIX THE A-SLOT ROLE (priority 1): write the DISPLAY color (col, semantic_alpha) to dataTextureA and move the debug/mask quad (strip, moire, viewAngle, semantic_alpha) to dataTextureB. dataTextureC is unread in this shader so nothing breaks today, but chained slots read C (= prev A) expecting COLOR - masks in A poison chains.",
            "Spring-damper the view angle: ease mouse.x with a critically-damped 1D spring (extraBuffer[133..134], [0..4] reserved, [5..132] = engine FFT) so the perspective shift rocks smoothly like tilting a real lenticular print; raw mouse.x stays the spring target. Keep the slow sin(time * 0.3) drift added AFTER the spring.",
            "Click holo flashes + vertical view tilt: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying moire flash ring at its click point (moireMask boost in an expanding band, ~1.2s fade), so clicks flare the foil. Wire the unused mouse.y as a vertical strip-phase tilt (small: strip phase += (mouse.y - 0.5) * 0.3) so both axes play.",
        ],
        "caution": "CAUTION: preserve the hash21 helper, the lenticular strip/band construction, the three-channel view-angle offsets (0.012/0.003/-0.009), the moire interference + pow 1.6 mask, the holo sin palette, and the vignette VERBATIM. All 4 sliders honestly wired (non-0..1 ranges - View Shift max 1.6, Frequency 0.1-1.0) - keep roles AND ranges EXACTLY. dataTextureB is write-only storage - fine for masks. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "long-exposure",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This light-painting shader's 'Glow Radius' slider is FAKE - gOff is computed from it and never used; the bloom is a fixed 3x3 +-1-texel blur no matter what. And the description promises 'mouse click resets the exposure' but the reset is a global fade that ignores WHERE you click. Make it honest:",
        "techniques": [
            "REAL GLOW RADIUS (priority 1): scale the bloom taps by gOff - sample the 4 neighbors at `coord +- vec2<i32>(i32(glowR), 0)` / `(0, i32(glowR))` (clamped as today, glowR already derived from the slider, clamp i32(glowR) to [1, 64]) instead of +-1. Default 0.3 maps glowR to ~0.0024*res.x (~5px at 2048) - the blur genuinely widens with the slider. Delete the dead gOff (or use it - no unused vars).",
            "POSITIONAL CLICK RESET: the current reset is mouseDown * 0.15 globally. Make it a brush: while mouseDown, the resetMix is full strength near the cursor (aspect-corrected smoothstep ~0.25 radius) and 0 elsewhere, so holding the button ERASES TRAILS WHERE YOU DRAG (light-painting eraser) - the global gentle reset can stay at 10% strength as a base. Loop ripples[] too (guard `min(u32(u.config.y), 50u)`): each live ripple stamps a bright exposure flash at its click point (adds a decaying white-warm blob into `accumulated`, ~1.5s fade), so single clicks paint light.",
            "Per-band decay drift: modulate decayRate per vertical band by FFT bins (`plasmaBuffer[u32(uv.y * 8.0) + 1u].x * 0.002`) so trails linger differently across the spectrum; clamp final decay to [0.95, 0.999]. Fix the stale header comment ('Category: temporal' -> post-processing, comment-only).",
        ],
        "caution": "CAUTION: the accumulation feedback contract is SACRED - dataTextureA stores RAW HDR accumulated color (clamped 1.5) and dataTextureC is textureLoad'd as prev accumulation; never tonemap the A write, keep the Reinhard only on the display path. Preserve the threshold/contribution/decay math, the luminance helper, and the clamp structure VERBATIM. All 4 sliders honestly wired - keep roles EXACTLY. extraBuffer (if used) in [133..255] ONLY.",
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
