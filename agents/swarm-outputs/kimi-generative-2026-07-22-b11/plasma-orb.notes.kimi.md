# plasma-orb — Upgrade Notes

**Role:** Optimizer
**Date:** 2026-07-22 (batch b11)

## Key Changes

- **Worley F2-F1 arc ridges:** Added `hash22` + animated `worleyF2F1()` cellular noise; thin ridge lines
  (`1 - smoothstep`) confined to the annulus between core and shell (`smoothstep(0.07,0.15,dist) *
  smoothstep(0.48,0.30,dist)`), domain slowly rotated with the field, scaled by `arcChaos`
  (density 5–11 cells, ridge width 0.12→0.05, temporal crawl speed). Arc color mixes blue→violet
  with a treble-synced pulse.
- **Spring-damper orb drift:** Thread (0,0) integrates offset+velocity in `extraBuffer[5..8]`
  (offset.xy, vel.xy — indices 5+ only, [0..4] untouched). Stiffness 24.0 / damping 5.0 gives a
  damped overshoot lunge toward the mouse; state stored relative to screen center so a zeroed
  buffer = no drift. Orb offset applied at 0.45 strength before the existing mouse-pinch warp.
- **Corona shimmer:** New outer-glow band driven by `mids`; slow rotating 6-lobe angular shimmer
  (`shimAngle = toroidal - time*0.35`), radius/thickness scaled by `glowSize`. Accumulated color is
  clamped at 1.2 pre-tint after temporal feedback (luma-echo-warp lesson) to prevent runaway glow.
- **Slider rewiring (same ids/defaults, mapping unchanged):**
  - `zoom_params.x` (Arc Intensity) → field-line brightness AND new worley arc brightness.
  - `zoom_params.y` (Arc Chaos) → now actually used (was dead): worley jitter, density, ridge width, crawl speed.
  - `zoom_params.z` (Glow Size) → sheet thickness + core halo + new corona radius/intensity.
  - `zoom_params.w` (Core Brightness) → core luminance + ACES exposure.
- **Cleanup:** Removed duplicated `aces_tone_map`/`acesToneMap` (kept one); collapsed the double
  ACES pass into a single tone map with combined exposure `(1.0 + coreBright) * 1.1`.
- Core MHD math (curl-ψ field, Alfvén perturbation, tokamak q-wrapping, reconnection, plasma beta,
  synchrotron palette, temporal feedback blend) preserved unchanged.

## Line Count Delta

- Before: 149 lines → After: 223 lines (**+74**, within the +50 to +90 target; 199–239 band ✓)

## Gate / Validation

- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/plasma-orb.wgsl` → **exit 0**,
  naga OK, bindgroup compatible, 0 warnings.
- Canonical 13-binding layout kept; `@workgroup_size(16, 16, 1)`; writes to `writeTexture`,
  `writeDepthTexture`, `dataTextureA` every frame; `textureSampleLevel(..., 0.0)` for sampler reads.
- JSON updated with `updatedParams` (indices 0–3) + `"updated": true` per brief; no other JSON
  fields changed (validated with `json.tool`).

## QA Flags

- Constants eyeballed, not tuned on hardware: spring stiffness/damping (24.0/5.0), drift strength
  0.45, worley scale 5–11, ridge width 0.12–0.05, corona radius 0.35–0.65, glow clamp 1.2.
- **This VM has no GPU** — visual QA deferred. Verify on hardware: arc annulus visibility at
  default chaos 0.4, spring overshoot feel on fast mouse moves, corona shimmer vs. feedback
  blowup under loud mids, and that double-ACES removal didn't shift overall brightness.
- extraBuffer read/write race (reader threads vs. writer thread 0,0) is benign: worst case a
  one-frame-stale drift value, same pattern as other swarm shaders.
