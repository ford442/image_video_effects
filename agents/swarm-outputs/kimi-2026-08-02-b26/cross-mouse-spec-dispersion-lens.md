# Completion Note: cross-mouse-spec-dispersion-lens ("Prismatic Lens")

**Agent:** Algorithmist (kimi, swarm batch b26) — 2026-08-02

## Summary of Changes

Rewrote `public/shaders/cross-mouse-spec-dispersion-lens.wgsl` per the brief, upgrading the
existing Cauchy-dispersion lens without changing its identity:

1. **ASPECT-CORRECTED LENS (priority 1):** both `uv` and the (spring-smoothed) mouse position
   are scaled by `(aspect, 1.0)` before the distance is measured, so the lens is circular on
   any canvas. The same corrected `toMouse` vector feeds the rotation matrix / refraction
   normal so dispersion stays radial, and the rim gaussian uses the corrected `mouseDist`.
   Displacements are computed in corrected space and mapped back (`/ aspectVec`) for sampling,
   keeping the per-channel sample split verbatim.
2. **Spring-damper mouse:** critically-damped spring (omega = 8.0) integrated by thread (0,0);
   persistent state in `extraBuffer[133..138]` only (pos xy, vel xy, lastTime, init flag).
   Raw mouse stays the spring target.
3. **Treble wired:** per-channel sparkle — `dispR` shimmers by `plasmaBuffer[6].x * 0.3`,
   `dispB` by `plasmaBuffer[8].x * 0.3`.
4. **Click spectrum flares:** ripple loop guarded by `min(u32(u.config.y), 50u)`; each live
   ripple (< 1.2s age) adds a decaying dispersion burst `exp(-rippleAge * 2.0) * 1.5` in an
   aspect-corrected ~0.25 radius plus a brief spectral ring (violet) at the burst edge.
5. **4 sliders honestly wired** via `u.zoom_params.x/y/z/w` with the existing roles:
   Lens Radius → aperture, Dispersion Scale → spectral split width, Lens Strength → refraction
   magnitude, Rotation Speed → prism rotation (unchanged mappings, now driving real constants
   of the upgraded algorithm, including ripple bursts which scale with dispersionScale).

## Line Count

116 → **194** (expand +78, within the +50..+90 / 166–206 target).

## Contract Items Preserved Verbatim

- `cauchyIOR` helper (`n0 + B / (lambda * lambda)`)
- `n0 = 1.4`, `B = 3000.0`; wavelengths 650/530/460 nm
- Parabolic `lensProfile = max(0.0, 1.0 - (mouseDist * mouseDist) / (lensRadius * lensRadius))`
- Time-rotation matrix (`angle = time * rotationSpeed * 0.2 + lensProfile * 3.14159`, ca/sa rotDir)
- Per-channel r/g/b sample split (`uv - dispR` / `uv` / `uv - dispB`)
- Rim gaussian form `exp(-pow((mouseDist / max(lensRadius, 0.001)) - 1.0, 2.0) * 30.0)`
- `clickBoost = select(1.0, 2.0, mouseDown)` retained
- `dataTextureA` stays DISPLAY color (same outColor as writeTexture)
- extraBuffer touched in [133..255] ONLY (slots 133–138)
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, writes writeTexture +
  writeDepthTexture + dataTextureA every frame
- JSON: brief JSON applied verbatim (params ids/defaults untouched + additive
  `updatedParams` mirror index 0–3 + `updated: true`); nothing else changed

## Naga Status

`/root/.cargo/bin/naga public/shaders/cross-mouse-spec-dispersion-lens.wgsl` →
**Validation successful** (exit 0, no errors/warnings).
