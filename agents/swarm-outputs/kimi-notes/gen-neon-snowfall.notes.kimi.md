# gen-neon-snowfall — Batch 1 Upgrade Notes

## Changes Made
- Added `acesToneMap` function
- Applied `color = acesToneMap(color * 1.1)` before final write
- Added `aces-tone-map` to WGSL header features
- Updated `Upgraded:` date to `2026-06-06`

## Why These Changes
Shader had chromatic per-flake hue, temporal persistence, semantic alpha, audio reactivity, depth, and dataA. Only ACES missing.

## Wow Factor
The rainbow snowflakes gain a more cinematic, neon-like saturation roll-off. Bright twinkling highlights compress naturally, making the snowfall feel more like falling light than flat color.

## Risks for Polish
None — pure ACES addition.

## Validation
- naga: ✅ pass
- generate_shader_lists.js: ✅ pass
- check_duplicates.js: ✅ pass
