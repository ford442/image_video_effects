# retro_phosphor_dream — Kimi notes (b13)

## Summary
- **Line delta:** 175 → 252 lines (**+77**, within the +50–90 brief target; final count inside the 225–265 range).
- **Gate:** `python3 scripts/wgsl_precommit_gate.py --files public/shaders/retro_phosphor_dream.wgsl` → **exit 0, 0 warnings** (naga OK, bindgroup compatible, workgroup `(16,16,1)` OK).
- **JSON:** `shader_definitions/generative/retro_phosphor_dream.json` parses; added `updatedParams` (exactly 4 entries, index 0–3, same names/defaults/min/max/step as `params`) + `"updated": true`. Nothing else touched (0.1 steps preserved).

## Key changes per technique

1. **BUG FIX (priority 1):** `audioPulse` was bound to `u.zoom_config.w` (MouseDown) and `plasmaBuffer` was declared but never read. Rewired: `audioPulse = clamp(plasmaBuffer[0].x, 0, 1)` (bass). Persistence decay (`0.85 + bass*0.08`, max **0.93 ≤ 0.95**) and the HDR glow boost now pump with music, not clicks.
2. **Analog hum & jitter:** `trebleEnergy = clamp(plasmaBuffer[0].z, 0, 1)` now drives:
   - **Scanline phase jitter** — per-scanline hash offset (`treble * 0.004` UV) inside the `scanlines()` function (new 4th param), simulating sync instability.
   - **Hum-bar roll** — new `humBar()` function: a slow vertical brightness bar (`sin((uv.y + time*rollSpeed)*2π)`) whose roll speed and depth scale with treble.
3. **Mouse degauss:**
   - Mouse X (`u.zoom_config.x / resolution.x`) modulates curvature strength (`curvature *= 0.6 + mouseUV.x * 0.8`).
   - On mouse-down (`u.zoom_config.w ≥ 0.5`), thread (0,0) records the trigger time in `extraBuffer[133]` (persistent-state range only, 0.35 s retrigger gap). New `degaussOffset()` applies a time-decaying sinusoidal UV offset (`exp(-age*3.5) * sin(age*28)`, center-weighted falloff) plus a brief chromatic "degauss flash" glow.
4. **Slider wiring (unchanged ids/defaults, zoom_params.x/y/z/w):** Curvature → barrel strength, Phosphor Size → triad size, Scanlines → scanline intensity, Flicker → interlace flicker. These were already meaningful; kept the mapping and made Curvature additionally mouse-modulated.
5. **Polish:** new `phosphorAperture()` softens triad subpixels with a cos roll-off; added epsilon to `normalize()` in chromatic aberration to avoid NaN at screen center.

## Contract compliance
- Canonical 13-binding layout preserved verbatim (no new/renumbered bindings, no binding 13).
- `@workgroup_size(16, 16, 1)`; `writeTexture`, `writeDepthTexture`, `dataTextureA` written every frame.
- All sampler reads use `textureSampleLevel(..., 0.0)`; storage reads use `textureLoad`.
- No WGSL reserved identifiers (`target` etc. avoided).
- `max(current, prev*decay)` persistence kept (non-additive); decay ≤ 0.93. Barrel distortion, RGB triad mask, and vignette math preserved — upgrade, not rewrite.

## QA flags
- `dataTextureB`, `extraBuffer` slots 0–132, `readDepthTexture`, and the comparison sampler remain unused (declared per canonical layout — gate-clean).
- Degauss state in `extraBuffer[133]`: if a previous shader's state lingers in that slot with a huge value, the first degauss may be delayed until `time` catches up; harmless and self-healing.
- **No-GPU caveat:** this VM has no WebGPU adapter (`requestAdapter()` returns null), so visual QA (degauss wobble feel, hum-bar subtlety, jitter amplitude) is deferred to real hardware. Validated via naga + bindgroup gate only.

Nothing committed.
