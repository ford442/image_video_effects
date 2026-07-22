# gen-neural-dust — Interactivist notes (kimi, b13, 2026-07-22)

## Line delta
- `public/shaders/gen-neural-dust.wgsl`: 171 → **224 lines** (**+53**, target +50–90, final 224 ∈ 221–261 ✅)
- `shader_definitions/generative/gen-neural-dust.json`: added `updatedParams` (4 entries, index 0–3, mirroring existing params ids/names/defaults/min/max/step exactly); `"updated": true` was already set. Nothing else touched.

## Key changes per technique
1. **Comet trails (dataTextureC feedback, previously declared-but-unread).**
   Previous frame is sampled via `textureSampleLevel(dataTextureC, u_sampler, uv, 0.0)`,
   blended as `trail = prevFrame * trailDecay + col * inject`. Baseline decay ≈ 0.9
   (`mix(0.86, 0.93, speedNorm)`). Accumulated trail is **clamped pre-tint at 1.2**
   (`trail = min(trail, vec3(1.2))` — luma-echo-warp lesson), then tinted toward the
   live palette. The clamped pre-tint trail is persisted to `dataTextureA` every frame
   for next frame's feedback.
2. **Per-bin spectrum response.** New helper `cellBandEnergy(cellId)` hashes each dust
   grid cell to one of `plasmaBuffer[1..8]` (and to one of the vec4's x/y/z lanes), so
   individual cells jitter (`jitter += cellEnergy * 0.55`), glow (`bandBoost =
   0.7 + cellEnergy * 0.9` on both glow layers) and phase-shift (`phase += cellEnergy
   * 0.12`) to different frequency bands instead of the whole field following global
   bass+treble. Global bass/treble still contribute (0.2 weight) to keep a cohesive pulse.
3. **Depth-aware parallax.** `readDepthTexture` is sampled (center + 2 neighbors,
   `textureSampleLevel(..., 0.0)`); the depth gradient offsets the dust-field sample
   position (`pDust = p + depthGrad * mix(0.5, 2.5, densityNorm)`) so motes drift
   around foreground silhouettes. Input depth is also passed through to
   `writeDepthTexture` (was constant 0.0) so silhouettes stay depth-consistent
   downstream. Mouse gravity stays in un-parallaxed screen space.
4. **Slider wiring (existing mappings kept + extended, not rewired).**
   - `dustDensity` (zoom_params.x): grid scale/density as before **+** parallax strength.
   - `flowSpeed` (zoom_params.y): time scaling as before **+** trail decay length.
   - `glowRadius` (zoom_params.z): glow radius as before **+** trail injection brightness.
   - `hueShift` (zoom_params.w): palette phase as before **+** trail tint amount.
5. **Mouse convention fix (brief CAUTION).** Was `u.zoom_config.xy` (reads time as
   MouseX — engine layout is `[time, mouseX, mouseY, mouseDown]` per
   `src/renderer/UniformBuffer.ts`). Now `u.zoom_config.yz`; struct comment corrected.

## Contract compliance
- Canonical 13-binding layout unchanged; no new/renumbered bindings; binding 13 not declared.
- `@workgroup_size(16, 16, 1)` preserved.
- `writeTexture`, `writeDepthTexture`, `dataTextureA` written every frame.
- All sampler reads use `textureSampleLevel(..., 0.0)`; storage reads via direct indexing.
- No WGSL reserved identifiers; `extraBuffer` unused (no persistent-state writes).

## QA flags
- **No-GPU caveat:** this VM has no WebGPU adapter; visual QA (trail feel, parallax
  strength constants, per-bin energy distribution) is deferred to real hardware.
  Constants were chosen conservatively (trail clamped at 1.2, parallax scaled by small
  depth gradients) but may need tuning on-device.
- `plasmaBuffer[1..8]` per-bin layout assumed from brief + existing shaders
  (`gen-bioluminescent-chrono-plasma-astro-owl.wgsl` uses `plasmaBuffer[1].x`); index is
  hash-stable per cell, so even an unexpected bin layout degrades gracefully to static
  per-cell gains rather than artifacts.
- First frame(s) after load read an uninitialized/empty `dataTextureC` — trails fade in
  within ~10 frames due to the 0.9 decay; no special-casing added (kept simple).

## Gate result
```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-neural-dust.wgsl
✅ Passed: 1 | Failed: 0 | Warnings: 0 — naga OK, bindgroup compatible (exit 0)
```
JSON parse check: OK.
