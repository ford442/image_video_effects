# gen-magnetic-kelp — Batch 1 Upgrade Notes

## Changes Made
- Added `acesToneMap` function
- Applied `color = acesToneMap(color * 1.1)` before final write
- Added `aces-tone-map` to WGSL header features
- Updated `Upgraded:` date to `2026-06-06`

## Why These Changes
Shader had complete plumbing (semantic alpha, temporal, audio, depth, dataA). Only ACES was missing.

## Wow Factor
ACES lifts the bioluminescent kelp greens and cyan fronds into a more vivid, filmic range. The gold spores gain warmer highlights without blowing out.

## Risks for Polish
None — mechanical ACES addition only.

## Validation
- naga: ✅ pass
- generate_shader_lists.js: ✅ pass
- check_duplicates.js: ✅ pass
