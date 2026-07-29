# Agent Notes — holographic-sticker (Batch 18, Visualist)

**Date:** 2026-07-30
**Files touched:**
- `public/shaders/holographic-sticker.wgsl` (rewritten/upgraded)
- `shader_definitions/visual-effects/holographic-sticker.json` (added `updatedParams` + `"updated": true` only)

## Lines
- **Before:** 100
- **After:** 170 (+70, within the +50..+90 target)

## Gate result
`python3 scripts/wgsl_precommit_gate.py --files public/shaders/holographic-sticker.wgsl`
→ **GREEN** — naga OK, bindgroup compatible, 0 workgroup errors/warnings, 0 extraBuffer violations.

## Techniques implemented

1. **Guarded palette read (Priority 1)** — `plasmaBuffer[palIdx % 256u]` could index
   past the real FFT bin count (OOB storage reads → zeros → dead black palette).
   Now wraps to always-live bins 1–8: `plasmaBuffer[(palIdx % 8u) + 1u].rgb`.
2. **Spring-damper sticker glide** — critically-damped spring (k=49, c=2√k=14)
   integrated by thread (0,0) only; state in extraBuffer[133..138]
   (pos [133..134], vel [135..136], lastTime [137], init flag [138]).
   Guarded by `arrayLength(&extraBuffer) > 138u`. Raw mouse is the spring target;
   the smoothed center feeds `dM`, `viewAngle`, pulse, and edge glow, so the foil
   glides after the cursor. First frame initializes on the cursor (no glide-in).
3. **Click foil flashes** — ripple loop guarded with
   `min(u32(u.config.y), 50u)`; each live ripple (age ≤ 1.5s) adds an expanding
   hue-cycling iridescent ring built from the same foil k-vec palette math,
   quadratic decay over ~1.5s, band widens as it fades. Flash is added into the
   foil (scaled by Foil Intensity) and bleeds slightly past the sticker edge so
   clicks scatter rainbows outward.

## Slider wiring (ids/defaults/min/max/step unchanged — saved-preset contract)

| Index | Param (id) | Drives in WGSL |
|---|---|---|
| 0 | Sticker Radius (`radius`) → `u.zoom_params.x` | sticker disc radius (`smoothstep(radius, radius*0.9, dM)`), edge glow band, bass pulse radius |
| 1 | Foil Intensity (`intensity`) → `u.zoom_params.y` | foil blend strength into the base image + click-flash contribution scale (0.35 + 0.65·intensity) |
| 2 | Rainbow Speed (`rainbowSpeed`) → `u.zoom_params.z` | temporal hue drift term `time * rainbowSpeed * 0.5` in the viewAngle hue mapping |
| 3 | Depth Weight (`depthWeight`) → `u.zoom_params.w` | luma↔depth alpha blend in `depthLayeredAlpha` |

## Preserved verbatim (per CAUTION)
- HSV foil construction (k-vec palette math) — unchanged.
- viewAngle hue mapping (`atan2(...)`, `hue = fract(viewAngle / TAU + time * rainbowSpeed * 0.5 + depth * 0.1 + bass * 0.05)`) — unchanged; it now consumes the spring-smoothed center via the same `mouse` identifier.
- `depthLayeredAlpha` helper — byte-for-byte identical.
- Temporal shimmer (C read / A write) kept subtle and raw; the A write is never tonemapped.

## Output contract compliance
- Canonical 13-binding layout, no added/renumbered bindings, no binding 13.
- `@workgroup_size(16, 16, 1)`.
- `writeTexture`, `writeDepthTexture`, and `dataTextureA` written every frame.
- `textureSampleLevel(..., 0.0)` for all sampler reads; storage reads via indexing.
- Ripple guard `min(u32(u.config.y), 50u)`.
- extraBuffer accessed only in [133..255] ([133..138]); [0..4] and [5..132] untouched.
- No reserved keywords used as identifiers.

## Deviations
- Depth write normalized from `vec4(depth, 0, 0, 1)` to `vec4(depth, 0, 0, 0)` —
  explicitly allowed by the CAUTION section; depth itself stays passthrough.
- JSON `updatedParams` copied exactly from the brief (one transient typo in
  index-3 `max` was caught and corrected to 1.0 before the gate run).
