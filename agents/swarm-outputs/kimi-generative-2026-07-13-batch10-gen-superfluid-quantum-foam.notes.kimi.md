# Upgrade Notes: gen-superfluid-quantum-foam

**Agent:** Interactivist  
**Shader:** Superfluid Quantum-Foam  
**Category:** generative  
**Date:** 2026-07-13

## Changes Made

- **Spring-damper mouse gravity well:** `extraBuffer[0..3]` now holds a smoothed mouse position and velocity. A spring-damper filter deforms the foam field toward a delayed, fluid mouse target instead of the raw cursor position.
- **Click shockwaves:** `extraBuffer[4..6]` tracks click count, expanding shockwave radius, and decaying strength. A radial ripple is injected into the SDF when a click occurs.
- **Multi-band audio splitting:**
  - **Bass** drives bubble boil intensity and shockwave expansion speed.
  - **Mids** drive vortex rotation speed/radius.
  - **Treble** sharpens iridescence frequency and adds additive sparkle flashes.
- **Temporal accumulation trails:** The feedback mix increases with `energy = bass + treble*2 + shockStrength`, so high-energy bursts persist briefly across frames.
- **Luma/depth-keyed spawn regions:** The input `readTexture` luma and `readDepthTexture` foreground depth are sampled per pixel and used to seed additional foam density (`g_spawn`).
- **Raymarched quantum foam preserved:** Original hyper-bubble field, iridescence, and volumetric glow remain intact; the additions layer on top without changing the core SDF layout.

## Files Touched

- `/root/image_video_effects/public/shaders/gen-superfluid-quantum-foam.wgsl` — upgraded WGSL (overwritten)
- `/root/image_video_effects/shader_definitions/generative/gen-superfluid-quantum-foam.json` — updated description and `features` array

## Final Metrics

- **Final WGSL line count:** 228 lines (target: 210–290)
- **JSON params:** unchanged (Boiling Volatility, Vortex Radius, Radiation Glow, Current Speed)
- **Bindings:** canonical 0–12 preserved, `@workgroup_size(16, 16, 1)`

## Validation Results

1. `python3 /root/image_video_effects/scripts/wgsl_precommit_gate.py --files /root/image_video_effects/public/shaders/gen-superfluid-quantum-foam.wgsl`  
   ✅ Passed — naga OK, bindgroup compatible

2. `cd /root/image_video_effects && node scripts/generate_shader_lists.js`  
   ✅ Passed — all category lists generated, no skipped/invalid/warn shaders

3. `cd /root/image_video_effects && node scripts/check_duplicates.js`  
   ✅ Passed — no duplicate IDs found

## Issues Encountered

- Naga rejected the variable name `target` as a reserved WGSL keyword. Renamed it to `mouseTarget` and the shader passed validation.
