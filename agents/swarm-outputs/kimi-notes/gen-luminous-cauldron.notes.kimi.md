# gen-luminous-cauldron — Batch 1 Upgrade Notes

## Changes Made
- Added `acesToneMap` function
- Applied `color = acesToneMap(color * 1.1)` before final write
- Added `aces-tone-map` to WGSL header features
- Updated `Upgraded:` date to `2026-06-06`

## Why These Changes
Full plumbing already present. ACES was the only missing upgraded-rgba requirement.

## Wow Factor
The cauldron's purple bowl and orange heat core gain richer, more controlled color saturation. ACES prevents the bright white foam from clipping and gives the bubbling surface a more luminous, magical quality.

## Risks for Polish
None — mechanical change.

## Validation
- naga: ✅ pass
- generate_shader_lists.js: ✅ pass
- check_duplicates.js: ✅ pass
