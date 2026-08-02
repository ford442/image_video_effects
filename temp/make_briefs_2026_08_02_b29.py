#!/usr/bin/env python3
"""Generate 8 self-contained swarm briefs in swarm-tasks/kimi-briefs-2026-08-02-b29/.

Batch 29 (smallest-first all-category, wave 11): same theme as Batches 17-27 -
formalize updatedParams from EXISTING params (saved-preset contract), make each
slider drive meaningful shader-specific constants, +2-3 tailored techniques each,
+50-90 lines, gate green. Pool scan reused from the b17 generator (all categories,
multipass-safe).

ENGINE UNIFORM TRUTH (verified src/renderer/UniformBuffer.ts + webgpu/frame.ts):
  config      = [time, rippleCount, resW, resH]
  zoom_config = [time, mouseX, mouseY, mouseDown]  -> mouse = .yz, down = .w
  ripples guard: min(u32(u.config.y), 50u)
NOTE: docs/BINDING_CONTRACT.md claims config.y=delta_time - STALE, trust the TS source.

Recon notes baked in (2026-08-02, Batch 29):
- sonic-boom: honest wiring; raw mouse; ripples unused; temporal tail via C read
  (prevTail * 0.82), A=display color. Mach/PHI-ring/shock-diamond/condensation/
  doppler stack is the identity.
- spectrum-bleed: CATASTROPHIC UNIFORM BUG - WGSL reads u.zoom_config.x/y/z as
  diffusion/hueDrift/satBoost (zoom_config.x is TIME - diffusion ramps forever,
  y/z are mouseX/mouseY) while zoom_params is NEVER READ (comment says 'reserved
  for future use') - ALL 4 JSON sliders (generic Intensity/Speed/Scale/Detail)
  are dead. Bonus bug: the multi-pass blur loop is IDEMPOTENT (re-samples
  readTexture every pass into the same var - passes>1 changes nothing).
  rgb2hsv/hsv2rgb + persist feedback (A=(persist,1), C read) are keepers.
- anamorphic-caustic-flare: honest; raw mouse (only mouse.x tilt used); ripples
  unused; A stores FIELD data (c, causticMask, flareStrength, semantic_alpha).
- ascii-lens: JSON category interactive-mouse, header 'distortion' (stale);
  plasmaBuffer never sampled; dataTextureA NEVER WRITTEN (frame-write contract
  broken); all 4 sliders honest. Branchy glyph selection (if/else luma tiers).
- digital-haze: JSON category interactive-mouse, header 'distortion' (stale);
  DEAD SLIDER - w 'Haze Density' is in the JSON but never read (only x/y/z
  used). Raw mouse; ripples unused; Beer-Lambert volumetric stack is the
  identity.
- heat-haze-mirage: CRITICAL - reads AUDIO FROM extraBuffer[0..2] ('let bass =
  extraBuffer[0]') - RESERVED ZONE ([0..4] reserved, FFT lives at [5..132],
  plasmaBuffer carries the bands) - the audio-reactive feature reads reserved
  zeros; plasmaBuffer never sampled. dataTextureB.w stores that bogus 'bass'.
  Mouse heat only via mouseDown; mDist not aspect-corrected; ripples unused.
  hazeAcc 0.85 accumulation A/C contract + B packing layout kept.
- interactive-film-burn: honest; raw mouse; ripples unused; A mask packing
  (holeMask, fireMask, smokeMask, alpha) keep; fbm/ember/fire-ramp identity.
- porcelain-fracture-glow: honest; raw mouse; ripples unused; A field packing
  (totalCrack, leak, lightTemp, alpha) keep; edge-follow crack network identity.
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
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-briefs-2026-08-02-b29")
os.makedirs(OUT_DIR, exist_ok=True)

SHADERS = [
    {
        "id": "sonic-boom",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This mach-cone shock's physics stack is genuinely aerodynamic - but the shock center snaps to the cursor and clicks never break the sound barrier. Give it flybys:",
        "techniques": [
            "Spring-damper the shock center (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the cone trails the cursor like a jet that can't turn instantly; raw mouse stays the spring target. Keep the aspect correction.",
            "Click mach bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple fires a secondary expanding shock ring from its click point (same ring0 gaussian form with radius growing at mach speed ~0.5/s, strength exp(-age * 1.5), ~2s) composed into ringSum before the distortion taps, so clicks launch sonic booms.",
            "Per-ring FFT voices: the three PHI rings each ride their own bin (ring0 <- plasmaBuffer[2].x, ring1 <- plasmaBuffer[4].x, ring2 <- plasmaBuffer[6].x, +-20% amplitude), so the shock diamonds shimmer across the spectrum instead of only global bass/treble.",
        ],
        "caution": "CAUTION: preserve the aces_tonemap, the mach number/angle math, the PHI ring hierarchy (d0/d1/d2, ring0/1/2 gaussians), the shock diamond phase, the condensation/fog scatter, the doppler chromatic taps (uv_r/uv_g/uv_b), the temporal tail (prevTail * 0.82 via C read), and the alpha formula VERBATIM - the aero identity is hand-tuned. dataTextureA stays DISPLAY color. All 4 slider ids/names/defaults/ranges EXACTLY (Ring Width range 0.01-0.2, Chrom. Split 0-0.1). extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "spectrum-bleed",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This shader reads its 'sliders' from u.zoom_config.x/y/z - which is TIME and the MOUSE POSITION, not parameters - so 'diffusion' ramps forever with the clock and ALL FOUR real sliders (zoom_params) are dead. Bonus bug: the multi-pass blur loop re-samples the source into the same variable every pass, so passes 2+ change nothing. Rebuild the plumbing:",
        "techniques": [
            "FIX THE UNIFORM BUG + WIRE ALL 4 DEAD SLIDERS (priority 1 - ids/names/defaults EXACTLY): stop reading zoom_config for parameters entirely. x ('Intensity', 0.5) -> blendFactor = x * 0.6 (default = today's mid-bleed look). y ('Speed', 0.5) -> hue drift rate (newHue = fract(hsv.x + y * time * 0.1)). z ('Scale', 0.5) -> blur radius: sampleBlur takes a radius multiplier (texel * mix(1.0, 4.0, z)) making the spread real instead of the idempotent loop - DELETE the dead passes loop. w ('Detail', 0.5) -> satBoost = w * 0.5 (default 0.25, a vivid but legal bleed). zoom_config.yz returns to its TRUE role: the mouse.",
            "HONEST MOUSE + CLICKS: tagged mouse-driven - add a bleed lens: near the (aspect-corrected, spring-damped - extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) cursor, blendFactor rises (+= lensMask * 0.3) so color bleeds outward from the pointer. Loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple stamps a saturation bloom at its click point (hsv.y += 0.4 * falloff * exp(-age*2.0), ~1.5s), so clicks splatter ink.",
            "Per-region FFT voices: 8 vertical bands each shift their hue drift phase by `plasmaBuffer[(band % 8u) + 1u].x * 0.2`, so the bleed rainbow shimmers across the spectrum.",
        ],
        "caution": "CAUTION: preserve the rgb2hsv/hsv2rgb helpers, the sampleBlur 4-tap kernel (parameterized by radius), the persist/max temporal feedback (A=(persist, 1.0) write, C read, 0.93 decay), and the depth passthrough VERBATIM. The hsv2rgb branchy tier style may stay (file character). All 4 slider ids/names/defaults/ranges EXACTLY (generic names Intensity/Speed/Scale/Detail are the saved-preset contract - do NOT rename). extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "anamorphic-caustic-flare",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This cinematic flare's caustic field is alive - but the flare is nailed to screen center, the tilt snaps with the cursor, and clicks never flash. Give it lens behavior:",
        "techniques": [
            "Spring-damper the tilt + flare anchor (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT); the mouseTilt rides the SPRUNG x, and the anamorphic flare line (currently pinned at uv.y = 0.5) follows the sprung y (centerDist = abs(uv.y - mix(0.5, sprungMouse.y, 0.35)) * 1.8 - mostly centered but the lens breathes toward the cursor).",
            "Click flare bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple fires a decaying anamorphic flash centered on its click's y-line (a second streak term: exp(-age * 2.0) * smoothstep(0.02, 0.0, abs(uv.y - clickY)) * flareStrength, ~1.2s) plus a brief caustic energy spike near the click point.",
            "Per-band FFT caustic shimmer: 8 vertical bands each modulate their causticMask by `plasmaBuffer[(band % 8u) + 1u].x * 0.3`, so the water light dances across the spectrum instead of only global mids/treble.",
        ],
        "caution": "CAUTION: dataTextureA stores FIELD data (c, causticMask, flareStrength, semantic_alpha) - NOT display color - keep that packing VERBATIM. Preserve the hash21/caustic helpers, the anamorphic smoothstep flare + streak construction, the refraction offset, the filmic chromatic aberration block (keep its branchy form), the contrast curve, the semantic alpha formula, and the depth-energy write VERBATIM. Slider ranges are custom (Flare 0-1.6, Caustic 0-1.8) - keep ids/names/defaults/ranges EXACTLY. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "ascii-lens",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This lens renders honest procedural glyphs - but it never writes dataTextureA (breaking the every-frame contract), never samples audio, and the lens snaps to the cursor. Tighten it up:",
        "techniques": [
            "FIX THE FRAME CONTRACT + SPRING THE LENS (priority 1): add the missing `textureStore(dataTextureA, ...)` every frame (display color, same value as writeTexture). Ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the lens glides; raw mouse (with the existing negative-coord center fallback) stays the spring target.",
            "Click glyph scrambles: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple scrambles glyphs near its click point (a decaying hash jitter added to the luma tier selection inside an aspect-corrected ~0.2 radius, exp(-age * 2.5), ~1s), so clicks glitch the text even outside the lens (scramble applies inside the lens region; outside the lens a brief RGB split flicker marks the click).",
            "Wire the dead audio: per-cell flicker - each glyph cell's charVal shimmers by its own bin (`plasmaBuffer[(u32(cellHash * 8.0) % 8u) + 1u].x * 0.4`) so the text dances with the music; bass subtly breathes the lens radius (lensRadius * (1.0 + bass * 0.15)). Fix the stale header ('Category: distortion' -> interactive-mouse, comment-only).",
        ],
        "caution": "CAUTION: preserve the grid/cellUV/localUV construction, the aspect-corrected cell sizing, the luma tier glyph selection (keep its branchy if/else form - pixel-crisp character), the width mapping, the depth-weighted alpha, and the outside-lens passthrough VERBATIM. All 4 slider ids/names/defaults EXACTLY (radius/density/line_width/brightness_bias with mapping fields). extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "digital-haze",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This volumetric haze has a DEAD SLIDER - the JSON advertises 'Haze Density' (w) but the WGSL never reads zoom_params.w; the extinction is hardcoded. Wire what you sell, then give the fog a hand:",
        "techniques": [
            "WIRE THE DEAD SLIDER (priority 1 - bit-exact at default 0.5): scale the haze extinction by the slider (`hazeDensity *= mix(0.4, 1.6, u.zoom_params.w)` - default 0.5 = 1.0, bit-identical to today). Now 'Haze Density' is real.",
            "Spring-damper the clear window: ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the clearing drags behind the cursor like wiping fogged glass; raw mouse stays the spring target. Keep the aspect correction.",
            "Click clear pulses + per-cell FFT static: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple punches a temporary clear hole at its click point (mask reduced by exp(-age * 2.0) in an aspect-corrected ~0.2 radius, ~1.5s), so clicks wipe the fog. Modulate each pixel-cell's noiseVal by its own bin (`plasmaBuffer[(u32(cellHash * 8.0) % 8u) + 1u].x * 0.3`) so the digital static flickers across the spectrum. Fix the stale header ('Category: distortion' -> interactive-mouse, comment-only).",
        ],
        "caution": "CAUTION: preserve the SIGMA_T_HAZE/SIGMA_T_CLEAR/STEP_SIZE constants, the Beer-Lambert transmittance/optical-depth math, the volumetric composition (inScattered + transmittedClear + transmittedHaze), the quantized-UV pixelation, the green tint, and the volumetric alpha VERBATIM - the fog physics are the identity. dataTextureA stays DISPLAY color (finalOut). All 4 slider ids/names/defaults EXACTLY (with mapping fields). extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "heat-haze-mirage",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This mirage reads its 'audio' from extraBuffer[0..2] - the RESERVED zone ([0..4] reserved; the FFT bands live in plasmaBuffer and extraBuffer[5..132]) - so bass/mid/treble are reading reserved zeros and the whole audio-reactive feature tag is dead. Fix the plumbing, then make the heat rise:",
        "techniques": [
            "FIX THE AUDIO SOURCE (priority 1): replace `extraBuffer[0]/[1]/[2]` with `plasmaBuffer[0].x/.y/.z` (real bass/mid/treble) - the heatIntensity bass boost (x2.0!), the mid glow, and the dataTextureB.w stored bass all become live. This is the only extraBuffer access in the file; after the fix the shader touches NO reserved state.",
            "Spring-damper the heat source + aspect fix: ease the mouse with a critically-damped spring (extraBuffer[133..136] - the FIRST extraBuffer state this shader may write, [0..4] reserved, [5..132] = engine FFT) so the hot spot drifts like a real thermal; raw mouse stays the spring target. Aspect-correct mDist (currently elliptical) so the heat column is circular.",
            "Click heat bursts + per-band FFT: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple injects a decaying heat bloom at its click point (heatFactor += exp(-age * 1.5) * aspect-corrected ~0.2 falloff, ~2s - no mouseDown needed), so clicks pop mirages. Modulate the wavy displacement per 8 vertical bands (`plasmaBuffer[(band % 8u) + 1u].x * 0.3` on disp amplitude), so the shimmer varies across the spectrum. Fix the stale comment (comment-only): config.y = ripple COUNT.",
        ],
        "caution": "CAUTION: preserve the hash/vnoise/fbm2 helpers, the risingUV advection, the heatBase column, the vertical-bias heatDisp, the chromatic r/g/b tap structure, the warm tint, the glow, the hazeAcc 0.85 accumulation (A write / C read contract - keep the mix form), and the dataTextureB packing (heatDisp, heatFactor, bass) VERBATIM. All 4 slider ids/names/defaults EXACTLY. extraBuffer writes in [133..255] ONLY (reads: none after the fix).",
    },
    {
        "id": "interactive-film-burn",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This film burn's fire edge and ember noise are genuinely pyrotechnic - but the burn snaps to the cursor and clicks never scorch the film. Give it arson:",
        "techniques": [
            "Spring-damper the burn center (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the burn hole drags behind the cursor like a real ember; raw mouse stays the spring target. Keep the aspect correction.",
            "Click cigarette burns: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple sears a small secondary burn at its click point (same hole/fire/smoke mask evaluation against a radius that grows to ~0.08 then chars over ~2s, composed via max() with the main burn masks), so clicks brand the film - the classic cigarette-burn cue mark.",
            "Per-sector ember FFT: divide the burn edge into 8 angular sectors; each sector's emberGlow rides its own bin (`plasmaBuffer[(sector % 8u) + 1u].x * 0.4`), so the fire line crackles unevenly around the hole instead of only global audio.x.",
        ],
        "caution": "CAUTION: dataTextureA stores MASK data (holeMask, fireMask, smokeMask, finalAlpha) - NOT display color - keep that packing VERBATIM. Preserve the hash12/noise/fbm helpers (5-octave rot matrix), the distortedDist construction, the hole/fire/smoke mask smoothsteps, the fireColor ramp + charColor, the sepia/grain intact color, the alpha composition, and the depthOut math VERBATIM - the burn identity is hand-tuned. All 4 slider ids/names/defaults EXACTLY. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "porcelain-fracture-glow",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This kintsugi crack network follows the image's own edges - beautiful - but clicks (the natural 'drop the plate' gesture) do nothing and the mouse only cracks while held. Give it impact:",
        "techniques": [
            "Click fracture impacts (priority 1): loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple strikes a crack burst at its click point (a decaying radial crack star: totalCrack += aspect-corrected ~0.15 falloff * crackAmt * exp(-age * 1.2), ~2.5s slow heal, PLUS a brief bright vein flash on impact), so clicks drop the porcelain.",
            "Spring-damper the crack focus: ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the press-crack point glides; raw mouse stays the spring target and mousePress keeps its role riding the sprung point.",
            "Per-band FFT vein song: 8 vertical bands each modulate their leak term by `plasmaBuffer[(band % 8u) + 1u].x * 0.35`, so the glowing veins sing different notes across the spectrum instead of only global bass/treble.",
        ],
        "caution": "CAUTION: dataTextureA stores FIELD data (totalCrack, leak, lightTemp, semantic_alpha) - NOT display color - keep that packing VERBATIM. Preserve the hash21/valueNoise/fbm helpers, the edge-following crack network (both fbm octaves + smoothstep), the vein/leak/rim construction, the porcelain base mix, the patina, the semantic alpha, and the depth write VERBATIM. Slider ranges are custom (Crack 0-1.4, Glow 0-1.6) - keep ids/names/defaults/ranges EXACTLY. extraBuffer in [133..255] ONLY.",
    },
]


def main():
    pool = scan_pool()
    picks = [e["id"] for e in pool[:8]]
    expected = [s["id"] for s in SHADERS]
    print("Batch 29 pool picks:", picks)
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
