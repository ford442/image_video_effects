# gen-bioreactor-bloom — Batch 1 Upgrade Notes

## Changes Made
- Added `acesToneMap` function
- Applied `color = acesToneMap(color * 1.1)` before final write
- Added `aces-tone-map` to WGSL header features
- Updated `Upgraded:` date to `2026-06-06`

## Why These Changes
Shader had full modern stack: hash21/hash22, colony simulation, poison clouds, temporal feedback, semantic alpha, audio, depth, dataA. ACES was the only gap.

## Wow Factor
The green colony glow and cyan nucleus pulse gain a more organic, bioluminescent richness. ACES gives the red poison-cloud blooms a more dangerous, saturated look without clipping.

## Risks for Polish
None — mechanical addition.

## Validation
- naga: ✅ pass
- generate_shader_lists.js: ✅ pass
- check_duplicates.js: ✅ pass
