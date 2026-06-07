# gen-vortex-cathedral — Batch 1 Upgrade Notes

## Changes Made
- Added `acesToneMap` function
- Applied `color = acesToneMap(color * 1.1)` before final write
- Added `aces-tone-map` to WGSL header features
- Updated `Upgraded:` date to `2026-06-06`

## Why These Changes
Shader had all modern features except ACES tone mapping. No hash21 helper — only sat() — so acesToneMap inserted cleanly before @compute.

## Wow Factor
The cathedral's purple arches and ghost-light center bloom gain cinematic roll-off. Bright column highlights compress naturally instead of clipping, giving the vortex a more ethereal, cathedral-like atmosphere.

## Risks for Polish
None — pure plumbing addition.

## Validation
- naga: ✅ pass
- generate_shader_lists.js: ✅ pass
- check_duplicates.js: ✅ pass
