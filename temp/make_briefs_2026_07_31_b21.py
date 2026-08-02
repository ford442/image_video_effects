#!/usr/bin/env python3
"""Generate 8 self-contained swarm briefs in swarm-tasks/kimi-briefs-2026-07-31-b21/.

Batch 21 (smallest-first all-category, wave 5): same theme as Batches 17-20 -
formalize updatedParams from EXISTING params (saved-preset contract), make each
slider drive meaningful shader-specific constants, +2-3 tailored techniques each,
+50-90 lines, gate green. Pool scan reused from the b17 generator (all categories,
multipass-safe).

Recon notes baked in (2026-07-31, Batch 21):
- moire-interference: wiring honest; DEAD `dir` variable (normalize(uv-0.5),
  never used); odd depth write vec4(depth,0,0,1.0); stale header 'Category:
  image' (JSON interactive-mouse); mouse raw; ripples unused.
- mouse-gravity: clean and honest (dev-monologue comments are its charm -
  preserve); depth already warped via uvG; mouse raw; ripples/mouseDown unused.
- fireworks-edge-ignite: FLAT-0.0 DEPTH CLOBBER (vec4(0.0) - 3rd sighting,
  features claim 'depth-aware'!) + MOUSE COORD UNITS BUG ((zoom_config.yz -
  res*0.5)/min(res) treats normalized as pixels - same bug as its sibling
  b18 fireworks-portrait-burst, held-click bursts never land on cursor);
  ripples unused; temporal feedback (A=display, C=prev) consistent.
- spec-histogram-equalize: JACKPOT - TWO dead sliders: clip_limit (clipLimit is
  computed into `clippedCount` which is NEVER USED - no actual CLAHE clip) and
  tile_blend (read, NEVER referenced). dataTextureA stores MASKS (equalizedLuma,
  luma, scaleFactor, cdf) instead of display color (A-role violation). Dead
  PI/TAU consts. Header says 8x8 tile, workgroup is 16x16 (stale doc).
- speed-lines-focus: wiring honest; odd depth write vec4(depth,0,0,1.0); mouse
  raw; ripples/mouseDown unused; stale header 'Category: image' (JSON artistic).
- fireworks-patriotic-july4: FLAT-0.0 DEPTH CLOBBER + SAME MOUSE COORD UNITS BUG
  (family trait - 3rd/4th sightings) + mids declared but never read; ripples
  unused; temporal feedback consistent.
- interactive-emboss: wiring honest; no header block at all; mouse light raw;
  ripples unused; depth sampled but passthrough-only despite 'depth-aware' tag.
- kinetic-dispersion: wiring honest; mouse raw; ripples unused; stale comments
  (config.y='ClickCount', zoom_config.w='Generic2'); stale header category
  'distortion' (JSON interactive-mouse).
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
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-briefs-2026-07-31-b21")
os.makedirs(OUT_DIR, exist_ok=True)

SHADERS = [
    {
        "id": "moire-interference",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This interference field is honest but carries a dead variable, an odd depth write, and a snapping mouse point. Clean it up and give it touch:",
        "techniques": [
            "Remove the dead `dir` variable (normalize(uv - 0.5), never used) and normalize the depth write `vec4(depth, 0.0, 0.0, 1.0)` -> `vec4(depth, 0.0, 0.0, 0.0)`. Fix the stale header ('Category: image' -> interactive-mouse, comment-only) and config.y comment (ripple COUNT).",
            "Spring-damper the second emitter (priority 1): ease the mouse point with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the moire field morphs fluidly as the cursor moves; raw mouse stays the spring target. Keep the aspect correction on the SPRUNG position.",
            "Click interference bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple acts as a temporary THIRD wave emitter at its click point (same sin(d * freq - time * 2.0) form, weight exp(-age * 2.0), ~2s fade), so clicks drop stones into the interference pond. Also modulate each wave's amplitude by a per-emitter FFT bin (emitter 1 -> bin 1, mouse emitter -> bin 5) so the two sources listen to different bands.",
        ],
        "caution": "CAUTION: preserve the two-point sin() interference core, the complexity third-wave branch, the cos/sin displacement vector, and the r/g/b aberration tap structure VERBATIM. All 4 sliders honestly wired (note Complexity default 0 = third wave off) - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "mouse-gravity",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This gravity well is honest and already warps depth - but the singularity snaps to the cursor and clicks fall on deaf ears. Make the well feel massive:",
        "techniques": [
            "Spring-damper the singularity (priority 1): ease the mouse position with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) - heavy and slow is GOOD here (stiffness ~6, the well should feel massive); raw mouse stays the spring target.",
            "Click gravity pulses: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple creates a temporary SECONDARY gravity well at its click point (same exp(-dist/radius) distortion form, strength exp(-age * 2.0), ~2s fade, combined multiplicatively with the main distortion), so clicks punch dents into spacetime.",
            "Photon ring shimmer: add a subtle bright accretion ring at the event horizon (`ring = smoothstep(0.02, 0.0, abs(dist - radius * 0.35))`, tinted by treble bins `plasmaBuffer[7].x`, gated by darkness so it only shows when the core is dark) - earns the black-hole look. mouseDown can deepen the well slightly (strength * (1.0 + mouseDown * 0.3)).",
        ],
        "caution": "CAUTION: preserve the distortion falloff (1.0 - strength * exp(-dist/radius)), the r/g/b aberration offset structure, the core smoothstep darkness mix, the warped-depth read (uvG), AND the dev's thinking-out-loud comments (they are this file's personality) VERBATIM. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "fireworks-edge-ignite",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This fireworks shader has its sibling's exact diseases (fireworks-portrait-burst, Batch 18): the depth write is a flat 0.0 clobber despite a 'depth-aware' feature tag, and the mouse math treats normalized [0,1] coords as pixels so held-click bursts detonate off-screen. Same family, same cures:",
        "techniques": [
            "FIX THE MOUSE COORD BUG (priority 1): `let mUV = (u.zoom_config.yz - res*0.5)/min(res.x,res.y);` - zoom_config.yz is NORMALIZED [0,1]; subtracting res*0.5 (hundreds of pixels) puts mUV at a fixed off-screen point. Correct: `let mUV = (u.zoom_config.yz * res - res * 0.5) / min(res.x, res.y);`. Verify the held-click burst then centers on the cursor.",
            "HONEST DEPTH: writeDepthTexture stores vec4(0.0), clobbering chain depth while the features claim 'depth-aware' - write real depth: luminance-derived from the tonemapped color (`clamp(dot(col, vec3(0.299,0.587,0.114)) * 0.9 + edge * 0.2, 0.0, 1.0)`) so sparks and contours sit forward.",
            "Click shell launches: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple launches a one-shot shell at its click point (same sparkPos/softGlow pipeline as the probe bursts, correct coord conversion as above, age = time - ripple.z, burst at age 0.6), so individual clicks fire without holding the button.",
        ],
        "caution": "CAUTION: preserve acesToneMap, hash1, softGlow, sampleImg (centered-UV convention!), edgeAt, sparkPos, the 8-probe ignition loop with its continue guards, the temporal feedback (mix(prev*trail, col, 0.32); A=display color, C=prev; keep the dataTextureB write) VERBATIM - the pyrotechnics are hand-tuned. All 4 sliders honestly wired - keep roles EXACTLY. extraBuffer (if used) in [133..255] ONLY.",
    },
    {
        "id": "spec-histogram-equalize",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This CLAHE shader is a double agent: 'Clip Limit' computes a clippedCount that is NEVER USED (no actual clipping happens), 'Tile Blend' is read and NEVER REFERENCED, and dataTextureA gets masks instead of display color. Two dead sliders and a poisoned slot - make it the real CLAHE it claims to be:",
        "techniques": [
            "REAL CLAHE CLIP (priority 1): implement the actual clip-and-redistribute - after the histogram barrier, each thread computes the clipped CDF for its bin: cdfClip = sum over i<=bin of min(count[i], u32(clipLimit)) PLUS uniform redistribution of the total clipped excess (excess = sum over all i of count[i] - min(count[i], clip); add excess * (bin + 1) / 256). Use cdfClip / totalPixels for equalizedLuma. A 256-iteration loop per thread is fine. Note: the slider was DEAD, so any wiring changes the look - that is the fix, not a regression; document the chosen mapping.",
            "WIRE TILE BLEND + FIX THE A SLOT: tileBlend (z) should soften tile seams - blend the final color toward a 4-tap neighbor average remapped with the same scaleFactor (`mix(outColor, neighborAvg * scaleMix, tileBlend * 0.5)`), so 0 = crisp per-tile, 1 = spatially smoothed. Then write the DISPLAY color (outColor, color.a) to dataTextureA and move the debug quad (equalizedLuma, luma, scaleFactor, cdfNorm) to dataTextureB. Remove the dead PI/TAU consts and the dead clippedCount line. Fix the stale '8x8' doc comment (workgroup is 16x16).",
            "Mouse contrast lens (optional flavor, not tagged mouse-driven): near the cursor, locally raise `strength` (+0.3 smoothstep falloff ~0.3 radius) so the pointer peels open local contrast. Loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple pulses a temporary clip-limit loosening at its click point (~1.5s fade), so clicks pop the tonal range locally.",
        ],
        "caution": "CAUTION: the workgroup choreography is SACRED - all workgroupBarrier() calls must stay OUTSIDE conditionals (divergence = UB), keep the cooperative clear/vote structure, the atomic ops, the luma binning, and the inBounds write guard VERBATIM in structure. totalPixels stays 256u. @workgroup_size(16, 16, 1) is load-bearing here. dataTextureB is write-only storage - fine for the debug quad. extraBuffer (if used) in [133..255] ONLY.",
    },
    {
        "id": "speed-lines-focus",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This manga speed-line focus is honest - but the focus point snaps, clicks do nothing, and the depth write ships a stray alpha. Sharpen it:",
        "techniques": [
            "Spring-damper the focus point (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the zoom-blur vortex trails the cursor with momentum; raw mouse stays the spring target. The 16-tap zoom blur then naturally smears during fast moves.",
            "Click action bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple flashes a radial speed-line burst at its click point (temporary lineEffect boost with lines emanating from the click angle, ~1.0s fade), so clicks punctuate the action like a manga impact frame.",
            "Angular FFT voices: divide the angle around the focus into 8 sectors; each sector's line intensity rides its own bin (`plasmaBuffer[(sector % 8u) + 1u].x` where sector = u32((angle / 6.28318 + 0.5) * 8.0)) so the speed lines pulse around the spectrum. Normalize the depth write `vec4(depth, 0.0, 0.0, 1.0)` -> `vec4(depth, 0.0, 0.0, 0.0)`; fix the stale header ('Category: image' -> artistic, comment-only).",
        ],
        "caution": "CAUTION: preserve the hash11/noise1 helpers, the 16-tap zoom blur loop, the noise1(angle * lineDensity + time * lineSpeed) line construction, the centerMask, and the vignette VERBATIM. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "fireworks-patriotic-july4",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. Third fireworks shader, same two family diseases: flat-0.0 depth clobber behind a 'depth-aware' tag, and the mouse-coord-units bug that parks held-click bursts off-screen. Plus mids is declared and never read. Fix the family traits:",
        "techniques": [
            "FIX THE MOUSE COORD BUG (priority 1): `let mUV = (u.zoom_config.yz - res*0.5)/min(res.x,res.y);` - yz is NORMALIZED [0,1]; correct form: `let mUV = (u.zoom_config.yz * res - res * 0.5) / min(res.x, res.y);`. Verify the held-click 40-spark ring then centers on the cursor.",
            "HONEST DEPTH + DEAD MIDS: writeDepthTexture stores vec4(0.0) - write real depth (`clamp(dot(col, vec3(0.299,0.587,0.114)) * 0.9 + stripe * 0.15, 0.0, 1.0)`) so shells and stripes sit forward. Wire the dead mids read into the stripe wave (e.g. stripe phase or wave mix amplitude rides mids * 0.3) so all three bands are honest.",
            "Click grand-finale shells: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple launches a one-shot patriotic shell at its click point (correct coord conversion, same sparkPos/softGlow/patriotColor pipeline, burst at age 0.6, cycling red/white/blue by click index), so clicks fire the finale.",
        ],
        "caution": "CAUTION: preserve acesToneMap, hash1, softGlow, sampleImg (centered-UV convention!), sparkPos, patriotColor (band math exact), the 8-probe launch loop with continue guards, the temporal feedback (mix(prev*0.92, col, 0.33); A=display, C=prev; keep the dataTextureB write) VERBATIM. All 4 sliders honestly wired - keep roles EXACTLY. extraBuffer (if used) in [133..255] ONLY.",
    },
    {
        "id": "interactive-emboss",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This emboss aims its light with a raw snapping cursor, ignores clicks, and samples depth only to pass it through despite a 'depth-aware' tag. Give the relief some feel:",
        "techniques": [
            "Spring-damper the light source (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the light direction sweeps smoothly across the relief; raw mouse stays the spring target.",
            "Click relief stamps: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying emboss pop at its click point (a local diff boost modulated by an expanding ring, ~1.2s fade), so clicks dent the surface.",
            "Depth-aware relief (earn the tag): scale reliefContrast by the sampled depth (`reliefContrast *= mix(0.7, 1.3, depth)`) so near geometry embosses harder than background. Also clamp the gray/color emboss output to [0,1] hue-preserving (diff can push past 1 at high strength) - soft-knee, don't hard-clip.",
        ],
        "caution": "CAUTION: preserve the 4-tap Sobel-ish gradient, the light_dir dot-product emboss core, the gray/color mode step, the mix_amt compositing, AND the dev's thinking-out-loud comments (they're this file's personality - keep them, you may add your own) VERBATIM. All 4 sliders honestly wired (Intensity default 1.0 = full effect; Color Mode is a step switch) - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "kinetic-dispersion",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. This kinetic shatter is honest and already depth-aware - but the influence snaps to the cursor, clicks do nothing, and the uniform comments lie. Tighten the machine:",
        "techniques": [
            "Spring-damper the influence center (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the dispersion field trails the cursor like inertia; raw mouse stays the spring target. The description says 'mouse-velocity dispersion' - the spring VELOCITY magnitude can also subtly boost `intensity` (+vel * 2.0, clamped), making the description literally true.",
            "Click shatter bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple spikes a decaying dispersion burst at its click point (local intensity + displacement kick, ~1.0s fade), so clicks crack the field.",
            "Per-block FFT voices: derive a bin from blockUV (`u32(hash12(blockUV * 7.0) * 8.0) % 8u + 1u`) and let that bin modulate each block's scatter amplitude (+-30%), so different blocks shatter to different frequencies. Fix the stale comments (comment-only): config.y = ripple COUNT, zoom_config.w = mouseDown, header 'Category: distortion' is stale (JSON lives in interactive-mouse).",
        ],
        "caution": "CAUTION: preserve the hash12/bass_env/curl2D helpers, the blockUV quantization, the displacement + curl composition, the r/g/b split taps, and the bass shockwave VERBATIM. All 4 sliders honestly wired (Sensitivity min 0.1 - keep the range) - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
]


def main():
    pool = scan_pool()
    picks = [e["id"] for e in pool[:8]]
    expected = [s["id"] for s in SHADERS]
    print("Batch 21 pool picks:", picks)
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
