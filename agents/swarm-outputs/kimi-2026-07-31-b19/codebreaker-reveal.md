# Agent Notes: codebreaker-reveal (Batch 19, Interactivist)

**Date:** 2026-07-31
**Shader:** `public/shaders/codebreaker-reveal.wgsl`
**JSON:** `shader_definitions/interactive-mouse/codebreaker-reveal.json`

## Line Counts

- **Before:** 102 lines
- **After:** 170 lines (**+68**, within the +50..+90 brief range; 152–192 target ✓)

## Per-Slider Mapping (unchanged ids/defaults — saved-preset contract)

| Slider | JSON id / name | Default | `u.zoom_params` | Drives in WGSL |
|---|---|---|---|---|
| 0 | param1 / Reveal Radius | 0.3 | `.x` | `baseRadius = max(0.01, x * 0.4)` — cursor reveal disc + click-burst disc base size |
| 1 | param2 / Rain Speed | 0.2 | `.y` | `speed = y * 2.0 * (1.0 + mids * 0.3)` — matrix rain fall speed |
| 2 | param3 / Code Density | 0.5 | `.z` | `density = max(10.0, z * 150.0)` — rain column count |
| 3 | param4 / Glow Intensity | 0.5 | `.w` | `glow = w * 2.0` — blink/shimmer flash + edge ring + burst rim brightness |

Mapping was already shader-specific (not boilerplate), so the wiring was kept and documented in-code.

## Techniques Implemented

1. **Spring-damper reveal center (priority 1):** Critically-damped spring (ω=9.0, fixed-step semi-implicit Euler, dt=1/60) with state in `extraBuffer[133..136]` (center.xy, vel.xy). Raw mouse (`u.zoom_config.yz`) is the spring target; first-frames snap guard avoids fly-in from origin. The **bass radius boost is applied after the spring** (`radius = baseRadius * (1.0 + bass*0.2)`) so the audio punch stays instant.
2. **Click reveal bursts:** Loop over `u.ripples[]` guarded by `min(u32(u.config.y), 50u)`; each live ripple (age 0..1.5s) opens a temporary second reveal disc at the click point using the same smoothstep mask math, radius growing then collapsing via a `sin(π*life)` envelope, combined with the cursor mask via `max()`. Added a faint expanding rim ring per burst for energy.
3. **Per-column treble shimmer:** `plasmaBuffer[(u32(colIndex) % 8u) + 1u].x` (f32 colIndex cast via u32) modulates a per-column glitter rate; shimmer added alongside the original blink into `finalMatrix`, so the code wall glitters across the spectrum instead of blinking uniformly.
4. **Stale comment fix:** struct comment `config.y` changed `MouseClickCount` → `RippleCount` (comment-only, per CAUTION).
5. **Alpha** extended to include `burstRing` contribution (stays meaningful).

## VERBATIM-Preserved Structures (CAUTION list)

- `hash12` helper — untouched.
- Matrix rain column/row math: `colIndex/colRandom/fallSpeed/yFlow`, `rowDensity/rowIndex/charRandom/cellUV/pixelCode`, and the original `blink` line — all verbatim.
- Luminance-driven `matrixColor` mix (`vec3(0.0, 1.0 + treble*0.2, 0.4)` → mix toward white by `luminance²`) — verbatim.
- Edge ring glow (`ring = 1.0 - smoothstep(0.0, 0.02, abs(dist - radius))`, `finalColor += vec3(0.5,1.0,0.8) * ring * glow`) — verbatim.
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, `textureSampleLevel(..., 0.0)`, writes to `writeTexture`/`writeDepthTexture`/`dataTextureA` every frame — preserved.
- `dataTextureA` stays DISPLAY color (same `fc` as writeTexture).

## JSON Changes

- Added ONLY the `updatedParams` array (indices 0–3, names/defaults/min/max/step exactly as the brief's JSON block) and `"updated": true`. No other fields touched. Validated with `json.load`.

## Deviations from the Brief

- **Burst rim ring:** brief asked only for the temporary reveal disc; I added a faint expanding rim (`burstRing`, decaying over the 1.5s life) fed into color/alpha at half glow weight. Reason: clicks were described as "deaf" — a rim makes the punch perceptible at the hole boundary without altering the VERBATIM cursor ring. Extra state: none (pure per-frame math).
- **Blink line kept verbatim + separate shimmer term** rather than rewriting the blink rate in place, to minimize intrusion on the hand-tuned code-wall identity while still delivering per-column FFT-driven glitter.

## Gate Result

```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/codebreaker-reveal.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ codebreaker-reveal.wgsl — naga OK, bindgroup compatible
```

extraBuffer writes: only indices 133–136 (within [133..255]). 0 warnings, 0 violations.
