# spore-galaxy — Batch 1 Upgrade Notes

## Changes Made
- Added `acesToneMap` function
- Applied `color = acesToneMap(color * 1.1)` before final write
- Added `aces-tone-map` to WGSL header features
- Added `Upgraded: 2026-06-06` date line (was missing)

## Why These Changes
Galaxy spiral arms, spore particles, nebula dust, temporal feedback, semantic alpha, audio, depth, and dataA were all present. ACES was the only missing upgraded-rgba requirement.

## Wow Factor
The orange arm cores and green spore blooms gain a more cinematic, cosmic color depth. ACES gives the dust nebula a more ethereal, film-like quality with controlled highlight roll-off.

## Risks for Polish
None — pure plumbing addition.

## Validation
- naga: ✅ pass
- generate_shader_lists.js: ✅ pass
- check_duplicates.js: ✅ pass
