# gen-bioluminescent-reaction-diffusion Upgrade Notes

**Agent:** kimi (Algorithmist)  
**Date:** 2026-07-13  
**Brief:** `/root/image_video_effects/agents/swarm-tasks/kimi-generative-briefs-2026-07-13-batch10/gen-bioluminescent-reaction-diffusion.md`

## Summary

Upgraded the `Bioluminescent Reaction-Diffusion` generative shader from 131 lines to **260 lines**, adding algorithmic depth while preserving the living, glowing reaction-diffusion soul.

## Changes Made

- **Dual Laplacian kernels:** Replaced the simple 3x3 Laplacian with a helper `laplacianDual()` that blends a 3x3 Moore neighbor-weight set and a higher-quality 5x5 high-order cross neighbor-weight set.
- **Multi-scale reaction-diffusion:** Simulates two competing species:
  - Species 1 stored in `xy` — fast, fine-scale, audio-tight.
  - Species 2 stored in `zw` — slower, large-scale, inhibited by species 1's activator.
- **Curl-noise advection:** Added `curl2()` and sampled advected neighbors to blend organic flow into species 1.
- **Domain-warped FBM:** Added `fbm()`, `noise2()`, `hash21()`, and `domainWarp()` to spatially modulate feed/kill rates.
- **Strange-attractor orbit trap:** Added `strangeAttractorOrbit()` as a branchless seed source.
- **Procedural plankton/bacteria SDF layer:** Added `planktonSDF()` for glowing micro-organism-like detail.
- **Branchless logic:** Replaced the per-pixel `if (time < 0.1)` and hard mouse-disc branches with `select()`/`mix()`/`smoothstep()` falloffs.
- **Preserved canonical layout:** 13 bindings, `@workgroup_size(16, 16, 1)`, writes to `writeTexture`, `writeDepthTexture`, and `dataTextureA`.
- **Updated JSON definition** at `shader_definitions/generative/gen-bioluminescent-reaction-diffusion.json` with an expanded description and feature tags.

## Files Modified

- `public/shaders/gen-bioluminescent-reaction-diffusion.wgsl` (overwritten, 260 lines)
- `shader_definitions/generative/gen-bioluminescent-reaction-diffusion.json` (updated)

## Validation Results

1. `python3 /root/image_video_effects/scripts/wgsl_precommit_gate.py --files /root/image_video_effects/public/shaders/gen-bioluminescent-reaction-diffusion.wgsl`  
   ✅ Passed — naga OK, bindgroup compatible.

2. `cd /root/image_video_effects && node scripts/generate_shader_lists.js`  
   ✅ Passed — all shader lists generated successfully.

3. `cd /root/image_video_effects && node scripts/check_duplicates.js`  
   ✅ Passed — no duplicate IDs found.

## Issues Encountered

- Initial draft was 264 lines, slightly above the 190–260 target. Trimmed 4 decorative section-divider comment lines to reach exactly 260 lines.
- No WGSL syntax or binding errors; all validations passed on first run after the trim.
