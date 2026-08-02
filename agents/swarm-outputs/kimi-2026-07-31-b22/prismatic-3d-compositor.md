# Swarm Output: prismatic-3d-compositor (Batch 22)

**Shader:** `public/shaders/prismatic-3d-compositor.wgsl` (PASS 2 of 2 compositor)
**Lines:** 109 → 182 (+73, target 159–199 ✅)
**Gate:** ✅ GREEN — `python3 scripts/wgsl_precommit_gate.py --files public/shaders/prismatic-3d-compositor.wgsl`
  → Passed 1/1, naga OK, bindgroup compatible, 0 workgroup errors/warnings, 0 extraBuffer violations.

## Bugs Fixed

1. **Inverted mouse units (Priority 1):** `mousePos = vec2(u.zoom_config.y / dims.x, u.zoom_config.z / dims.y)`
   double-divided the already-normalized [0,1] mouse, pinning the parallax driver to the corner pixel
   (headline parallax feature never worked). Fixed to `let mousePos = u.zoom_config.yz;`.
2. **'cameraZ' was really mouseDown:** renamed local to `mouseDown`. Old code multiplied parallax by
   `cameraZ`, so parallax was gated to ZERO unless the mouse was held. Now parallax is always live and
   pressing deepens it: `parallax = parallax * (1.0 + mouseDown * 0.5)`. Mapping-notes comment updated.
3. **Dead treble read:** `plasmaBuffer[0].z` now wired into glow:
   `liveGlowIntensity = glowIntensity * (1.0 + treble * 0.3)` — all three audio bands live.

## Slider Map (unchanged ids/ranges — saved-preset contract)

| zoom_params | Param | Range | Drives |
|---|---|---|---|
| .x | Glow Radius | 0–10 | 5x5 gather offset scale (`* 0.01`) |
| .y | Glow Intensity | 0–4 | glow add term (now treble-modulated) |
| .z | Parallax | 0–4 | depth-weighted cursor shift (`* PARALLAX_SCALE 0.05` → max ±0.2 UV) |
| .w | Aberration | 0–0.2 | depth-scaled chromatic split magnitude |

## Techniques Added

- **Parallax edge fade:** `step` in-bounds mask mixes back to unshifted pixel where the shift leaves
  the frame (no clamped border streaks).
- **Spectral glow tint:** hue rotates with depth (`cos(2π(depth + phase))` prism palette, 35% mix) so
  the halo reads prismatic, applied after the verbatim 5x5 gather.
- **Click prism flares:** ripple loop guarded `min(u32(u.config.y), 50u)`; each live ripple with
  `0 ≤ age ≤ 1.2s` adds `exp(-age * 2.0) * exp(-dist² * 40)` flare (aspect-corrected distance);
  flare multiplies aberration (`* (1 + flare * 3)`) plus a flat `flare * 0.02` spike, accumulates a
  radial split direction from the click, and adds a `prismTint * flare * 0.25` flash to `lit`.
- **Radial aberration direction:** 65% radial-from-centre / 35% horizontal blend, further blended
  toward the flare radial when a click is hot.

## Preserved VERBATIM

- 13-binding canonical layout (no add/renumber); `@workgroup_size(16, 16, 1)`
- readTexture / readDepthTexture reads as GIVEN pass-1 inputs (not restructured)
- 5x5 glow gather loop (offsets, weights `exp(-sampleDepth) * max(brightness - 0.2, 0)`, normalize `max(count,1)`)
- Depth-separated layered mix: `mix(aberrantColor, parallaxColor, clamp(depth * (0.4 + bass * 0.5), 0, 1))`
- Temporal feedback: `mix(finalColor, prev, 0.85 - mids * 0.25)` (A=feedback color, C=prev, symmetric)
- Alpha luminance key: `clamp(length(finalColor) * 0.7 + depth * 0.3, 0, 1)`
- Writes writeTexture, writeDepthTexture, dataTextureA every frame; `textureSampleLevel(..., 0.0)`
- `videoBlend = 0.5` composite structure

## JSON Changes

`shader_definitions/interactive-mouse/prismatic-3d-compositor.json`: added ONLY `updatedParams`
(index 0–3, exact names/defaults/min/max + step 0.01 per brief) and `"updated": true`. No other keys touched.

## Deviations

- Added `PARALLAX_SCALE = 0.05` constant: without the bogus `cameraZ` gate the raw slider range (0–4)
  would shift up to ±2 UV; scale keeps the now-working parallax visually sane (max ±0.2 UV).
- `let videoColor = cloudColor;` reuses the existing pass-1 sample instead of a duplicate identical
  `textureSampleLevel` (same value, one less sampler read); also makes `cloudColor` a used input.
- extraBuffer: not written at all (no persistent state needed) — [133..255] rule trivially satisfied.
