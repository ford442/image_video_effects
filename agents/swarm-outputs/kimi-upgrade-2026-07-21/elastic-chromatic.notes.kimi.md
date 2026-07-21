# Upgrade Notes — elastic-chromatic (Interactivist, 2026-07-21)

## Line count
- Original: 207 lines → Upgraded: **297 lines** (+90, top of the +50…+90 target band 257–297)

## Changes by domain

### Interactivity (role focus)
- **Spring-damper elastic mouse** (new `springStep()` helper): mouse position/velocity integrated
  with semi-implicit Euler; state persisted in `extraBuffer[0..3]` (pos.xy, vel.xy), written by the
  (0,0) leader thread each frame. Lazy init snaps an untouched buffer to the live mouse (no lurch
  from origin on first frames). The chromatic source (Lissajous center) and `mouseInfluence` now
  ride the spring position, so fast mouse moves overshoot and settle like a damped spring.
  Spring velocity also nudges the Lissajous source (`springKick`).
- **Click shockwave** (new `shockwaveRing()` helper): rising-edge mouse-down detection
  (`extraBuffer[8]` = previous frame's down state) spawns an expanding thin gaussian ring;
  origin/time stored in `extraBuffer[4..6]`. The ring multiplies the chromatic split amount
  (`caAmount *= 1.0 + ring`), adds to mouse influence, and feeds the alpha aberration term.

### Color / grading
- **IQ cosine palette tint** (new `iqCosinePalette()`): phase driven by luminance + slow time +
  mids; blended over the existing blackbody/split-tone grade at `paletteMix` (default 0.3 — the
  original grade remains dominant). Tint scaled to mean ≈ 1.0 so it re-hues rather than darkens.

### Parameters (4 sliders, re-scoped per brief)
- p1 / index 0 — **Elasticity** (default 0.5): spring stiffness `mix(28,210,p1)` (+ bass widening)
  and legacy lag gain, as before.
- p2 / index 1 — **Damping** (default 0.5): spring damping ratio `zeta` + legacy EMA `dampLag`
  scale (preserves old damping semantics on the temporal lag terms).
- p3 / index 2 — **Shockwave Boost** (default 0.5): ring strength `mix(0.4,2.4,p3)`.
- p4 / index 3 — **Palette Mix** (default 0.3): IQ palette blend amount.
- Old `chromatic_scale` (p2) and `lissajous_ratio` (p3) sliders are pinned to their legacy defaults
  (0.5 → chromaticScale 0.5; 0.5 → lissajousRatio 1.25) so the established look is preserved.

### Preserved (core algorithm / soul)
- Radial RGB chromatic aberration sample, per-channel EMA lag (R/G/B), depth-aware audio
  reactivity, split-tone blackbody grading, hue-preserving HDR clamp, ACES tone map, IGN dither,
  layered/accumulative semantic alpha, premultiplied-alpha output.
- Canonical 13-binding layout unchanged; `@workgroup_size(16, 16, 1)`; writes `writeTexture`,
  `writeDepthTexture`, `dataTextureA` every frame; `textureSampleLevel(..., 0.0)` for sampler reads.

## QA flags
- **Naga validation:** ✅ gate passes (naga OK, bindgroup compatible, 0 errors / 0 warnings).
- **No-GPU caveat:** headless VM has no WebGPU adapter — shader not visually exercised; validated
  via naga + bindgroup gate only. Ring/spring feel (overshoot amount, ring speed/width) should be
  tuned on real hardware.
- **Eyeballed constants:** stiffness range 28–210, zeta range 0.18–1.05, ring speed 1.35, band
  sharpness 64.0, ring decay 1.7, ring lifetime 3.0 s, `springKick` 0.02, ring→influence 0.6,
  ring→aberration 0.35, palette phase rate 0.045 — all chosen by feel, not measurement.
- **Race note:** leader thread (0,0) writes `extraBuffer` while other threads read in the same
  dispatch (no barrier); values may be one frame stale for some threads — visually harmless for
  spring/shockwave state, standard pattern for this codebase.
- **extraBuffer indices:** 0–3 spring pos/vel, 4–6 shock origin/time, 8 mouse-down edge flag.
  Index 4 collision with historyHead does not apply (no binding 13 / history ring declared).
