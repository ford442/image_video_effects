# holographic-crystal — Batch 1 Upgrade Notes

## Changes Made
- Added `acesToneMap` function
- Applied `color = acesToneMap(color * 1.1)` before final write
- Added `aces-tone-map` to WGSL header features
- Added `Upgraded: 2026-06-06` date line (was missing)

## Why These Changes
Shader had holographic interference, moiré patterns, temporal persistence, semantic alpha, audio reactivity, depth, and dataA. No ACES function present.

## Wow Factor
The holographic R/G/B phase interference gains a more vivid, prism-like saturation. ACES prevents the bright edge-glow and interior highlights from washing out, making the crystal feel more genuinely refractive.

## Risks for Polish
None — mechanical addition.

## Validation
- naga: ✅ pass
- generate_shader_lists.js: ✅ pass
- check_duplicates.js: ✅ pass
