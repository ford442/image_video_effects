# Swarm Completion: cyber-trace (kimi-2026-08-02-b27)

**Status:** ✅ Complete
**Lines:** 117 → 187 (target 167–207, +70)
**Naga:** `Validation successful` — no errors, no warnings

## Changes

- **Sprung brush (priority 1):** Critically-damped spring (zeta = 1, omega = 8.0) eases the
  brush toward the raw mouse so the trace ribbons behind the cursor. State in
  `extraBuffer[133..136]` (pos.xy, vel.xy), `[137]` last integration time, `[138]` init flag —
  all within [133..255]; [0..4] reserved and [5..132] engine FFT bins untouched. Integrated
  once per frame by invocation (0,0); first frame snaps onto the raw cursor. Raw mouse
  (`u.zoom_config.yz`) stays the spring target. Aspect correction and the down/idle brush
  strength `select(0.5, 1.0, isMouseDown)` preserved.
- **Dead audio wired (composite-only):** `bass = plasmaBuffer[0].x`, `mids = plasmaBuffer[0].y`.
  Bass pulses glow at composite: `glowIntensity * (1.0 + bass * 0.5)`. Mids drive hue cycle
  speed: `colorTick = time * 0.2 * (1.0 + mids * 0.8) + hueShift`. 8 vertical bands each
  shimmer composite glow by `plasmaBuffer[(band % 8u) + 1u].x * 0.3`. None of the glow
  modulation feeds back into history.
- **Click stamp blooms:** Ripple loop guarded by `min(u32(u.config.y), 50u)`; each live
  ripple (age 0–1.5s) stamps a soft round bloom (radius `brushSize * 1.5`, linear fade over
  1.5s) through the same drawColor pipeline, so clicks paint stars without dragging.
- **Sliders:** 4 existing params wired via `u.zoom_params.x/y/z/w` (decay, glow, hueShift,
  brushSize) — same ids/defaults/ranges; each drives a real constant of the algorithm.

## Contracts preserved

- **History contract SACRED:** `dataTextureC` read as prev history; `dataTextureA` written
  RAW as `clamp(historyColor.rgb * decaySpeed + drawColor * brush, 0.0, 2.0)` — never
  tonemapped; audio glow modulation happens ONLY at the composite.
- The display composite alone uses a hue-preserving soft knee (3.0 asymptote) to bound burn emission; raw history packing is unchanged.
- `hue2rgb` / `hslToRgb` helpers and ALL dev commentary comments preserved VERBATIM.
- Canonical 13-binding layout, no binding 13, `@workgroup_size(16, 16, 1)`.
- `writeTexture`, `writeDepthTexture`, `dataTextureA` written every frame.
- `textureSampleLevel(..., 0.0)` for sampler reads; no reserved-keyword identifiers.
- JSON: additive `updatedParams` mirror indices 0–3, `updated: true`, and truthful
  `audio-reactive` / `temporal` features; custom ranges exact (Trail Decay 0.8–0.99, Glow 0–3, Brush 0.005–0.2).
- Engine truth honored: config = [time, rippleCount, resW, resH];
  zoom_config = [time, mouseX, mouseY, mouseDown].
