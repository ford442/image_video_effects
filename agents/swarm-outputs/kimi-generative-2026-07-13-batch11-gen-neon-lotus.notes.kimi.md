# gen-neon-lotus upgrade notes

**Shader:** Neon Lotus  
**Category:** generative  
**Role:** Interactivist  
**Upgraded:** 2026-07-13

## Changes made

- Added click-triggered shockwave expanding from the lotus center, using `MouseClickCount` and a stored `shockTime` in `extraBuffer`.
- Added gravity-well mouse attraction that warps coordinates toward the cursor when the mouse button is held.
- Re-mapped audio reactivity: bass drives bloom expansion, mids drive hue-shift speed, treble drives edge sparkle.
- Added audio envelope followers (attack/release) in `extraBuffer` indices 0-2 for smooth, non-jittery reactivity.
- Added temporal feedback: samples `dataTextureC` at a drifting UV to leave brief neon trails from the previous frame.
- Added luma/depth keyed particle spawn from `readTexture` / `readDepthTexture` around petal edges.
- Replaced inline RGB cosine palette with an `hsv2rgb` helper for richer prismatic petal coloring.
- Expanded from 3 to 4 petal layers and widened the petal-count range.
- Updated JSON definition description and added a `features` array reflecting the new capabilities.

## Files touched

- `/root/image_video_effects/public/shaders/gen-neon-lotus.wgsl` (overwritten)
- `/root/image_video_effects/shader_definitions/generative/gen-neon-lotus.json` (updated)
- `/root/image_video_effects/agents/swarm-outputs/kimi-generative-2026-07-13-batch11-gen-neon-lotus.notes.kimi.md` (this file)

## Final metrics

- Final WGSL line count: **225** (target 220-300)

## Validation results

1. `python3 /root/image_video_effects/scripts/wgsl_precommit_gate.py --files /root/image_video_effects/public/shaders/gen-neon-lotus.wgsl`  
   ✅ Passed — naga OK, bindgroup compatible

2. `cd /root/image_video_effects && node scripts/generate_shader_lists.js`  
   ✅ Passed — all shader lists generated

3. `cd /root/image_video_effects && node scripts/check_duplicates.js`  
   ✅ Passed — no duplicate IDs

## Issues encountered

- Naga rejected the parameter name `target` as a WGSL reserved keyword. Renamed it to `goal` in the `envelope` helper and the precommit gate passed.
