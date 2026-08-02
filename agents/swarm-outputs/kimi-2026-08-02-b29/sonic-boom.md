# Swarm Completion: sonic-boom (kimi, b29)

**Shader:** `public/shaders/sonic-boom.wgsl` (category: distortion)
**Lines:** 118 → 184 (target 168–208, +66)
**Naga:** `Validation successful` (clean, no warnings)
**JSON:** `shader_definitions/distortion/sonic-boom.json` — brief JSON applied verbatim (added `updatedParams` index 0–3 + `updated: true`); existing id/name/url/features/params/tags untouched. Params ids/names/defaults/ranges unchanged (Ring Width 0.01–0.2, Chrom. Split 0–0.1).

## Changes

1. **Sprung shock center (priority 1):** critically-damped spring (K=48, damp=2√K, dt=0.016) chases the raw mouse (`zoom_config.yz` stays the spring target). State in `extraBuffer[133..136]` (pos.xy, vel.xy) + `[137]` init flag — [0..4] reserved / [5..132] engine FFT untouched; persistent state only in [133..255]. Every invocation integrates locally, thread (0,0) persists (matches `aero-chromatics.wgsl` codebase pattern). Aspect correction preserved on `to_pixel`.
2. **Click mach bursts:** ripple loop guarded by `min(u32(u.config.y), 50u)`; each live ripple (age = `config.x - ripple.z`, 0–2s) fires a secondary expanding shock ring from its click point — radius grows at mach speed 0.5/s, fade `exp(-age*1.5)`, same ring0 gaussian form (aspect-corrected), composed into `ringSum` before the distortion taps. `burstSum * 0.25` also feeds `shockFront` for a visible boom flash.
3. **Per-ring FFT voices:** ring0 ← `plasmaBuffer[2].x`, ring1 ← `plasmaBuffer[4].x`, ring2 ← `plasmaBuffer[6].x`, each as a `(0.8 + 0.4 * voice)` multiplier (±20% amplitude) on the existing PHI gaussians.
4. **Sliders:** all 4 wired via `zoom_params.x/y/z/w` (radius→cone radius, width→gaussian half-width, strength→mach/refraction, split→doppler chromatic spread) — mapping order/ids/defaults match the saved-preset contract; documented in header comments.

## Contracts preserved (CAUTION block)

- `aces_tonemap` verbatim; mach number/angle math (`machNum`, `machAngle = asin(1/M)`, `coneDist`) verbatim.
- PHI ring hierarchy: d0/d1/d2, gaussian exponents 4/6/8 and weights 1.0/0.55/0.30 intact (voices multiply on top, per brief).
- Shock diamond phase, condensation/fog scatter, doppler chromatic taps (uv_r/uv_g/uv_b), temporal tail `prevTail * 0.82` via C read, and the **alpha formula VERBATIM** all unchanged.
- `dataTextureA` stays DISPLAY color (`finalColor, alpha`); writeTexture + writeDepthTexture + dataTextureA written every frame.
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, `textureSampleLevel(..., 0.0)` for sampler reads. No binding 13 added (not used). No reserved-keyword identifiers. No git operations; precommit gate left to coordinator.

## Coordinator closeout

- Final lines: **118 → 193 (+75)**. The strongest click boom now displaces radially from its own launch point rather than borrowing the main sprung-center direction; click/PHI intensity is bounded.
- Display A, temporal C read, ACES output, pass-through depth, and the original four parameter contracts remain intact.
- Final focused gate, dead-slider/strict-buffer audit, JSON/list parity, Jest, and production build: pass.
