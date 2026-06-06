# gen-celestial-weave — Batch 1 Upgrade Notes

## Changes Made
- Added `acesToneMap` function (copy from `gen-conway-game-of-life.wgsl`)
- Applied `color = acesToneMap(color * 1.1)` before final `textureStore`
- Added `aces-tone-map` to WGSL header features
- Updated `Upgraded:` date to `2026-06-06`

## Why These Changes
Shader already had full upgraded-rgba plumbing: semantic alpha, temporal feedback, chromatic color separation, audio reactivity, depth writes, dataTextureA writeback. Only missing piece was ACES filmic tone mapping.

## Wow Factor
ACES adds cinematic contrast and color saturation to the cosmic weave. The purple/pink warp threads and cyan star field gain richer midtones and more controlled highlights without clipping.

## Risks for Polish
None — minimal mechanical change. Existing alpha, depth, and dataA logic untouched.

## Validation
- naga: ✅ pass
- generate_shader_lists.js: ✅ pass
- check_duplicates.js: ✅ pass
