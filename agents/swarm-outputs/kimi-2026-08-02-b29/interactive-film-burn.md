# Swarm Completion: interactive-film-burn (Film Burn)

**Agent:** Kimi (b29, Visualist role)
**Date:** 2026-08-02
**Status:** COMPLETE

## Changes

1. **Sprung burn center (priority 1):** Critically-damped spring (omega = 7.0, damping = 2*omega) persists
   burn center pos/vel in `extraBuffer[133..136]`, prev frame time in `extraBuffer[137]`. Raw cursor
   (`u.zoom_config.yz`) stays the spring target; `dt` clamped to `[0, 0.1]` for stability; first-frame
   init snaps center to cursor. State written back by invocation (0,0) only. Aspect correction kept.
2. **Click cigarette burns:** Ripple loop guarded by `min(u32(u.config.y), 50u)`. Each live ripple
   (age 0..3s) sears a secondary brand at its click point: radius grows to ~0.08 over 0.6s, flame
   dies within ~1s (`flameLife`), smoke/char settles over ~2s (`charSettle`). Brand masks use the same
   hole/fire/smoke smoothstep shapes and are composed via `max()` with the main burn masks.
3. **Per-sector ember FFT:** Burn edge split into 8 angular sectors via `atan2(distVec.y, distVec.x)`;
   each sector's emberGlow scaled by `(0.8 + plasmaBuffer[(sector % 8u) + 1u].x * 0.4)` so the fire
   line crackles unevenly around the hole.
4. **Sliders:** All 4 existing params stay wired to meaningful constants of this shader's algorithm:
   x=BurnRadius (hole size), y=BurnSpeed (fbm scroll), z=GrainStrength (film grain), w=EdgeGlow
   (glow width + fire alpha). IDs/names/defaults untouched.

## Contracts preserved (CAUTION block)

- `dataTextureA` MASK packing `(holeMask, fireMask, smokeMask, finalAlpha)` VERBATIM — not display color.
- `hash12` / `noise` / `fbm` (5-octave, rot matrix 0.8/0.6/-0.6/0.8) VERBATIM.
- `distortedDist` construction, hole/fire/smoke mask smoothsteps, fireColor ramp + charColor,
  sepia/grain intactColor, alpha composition, depthOut math — all VERBATIM.
- Canonical 13-binding layout unchanged; `@workgroup_size(16, 16, 1)`; writes writeTexture +
  writeDepthTexture + dataTextureA every frame; `textureSampleLevel(..., 0.0)` for sampler reads.
- extraBuffer used ONLY in [133..137] (within [133..255]); [0..4] reserved and [5..132] FFT untouched.
- JSON: full brief JSON applied verbatim (additive `updatedParams` + `updated: true`, params ids
  radius/speed/grain/glow with original names/defaults unchanged).

## Metrics

- Lines: 119 → 180 (target 169–209, +61)
- Naga: `Validation successful` (clean, no warnings/errors)
- JSON: valid (`python3 -m json.tool` OK)

## Coordinator closeout

- Final lines: **119 → 186 (+67)**. Added an explicit `[138]` init flag and a dedicated hot click-fire color so secondary cigarette brands visibly burn instead of inheriting the distant main-hole char ramp.
- Mask-state A, relief depth, alpha, and fire/noise ownership remain unchanged; click/depth capabilities are now explicit in metadata.
- Final focused gate, dead-slider/strict-buffer audit, JSON/list parity, Jest, and production build: pass.
