# acoustic-string-theory — Batch 1 Upgrade Notes

## Changes Made
- Added `acesToneMap` function
- Applied `color = acesToneMap(color * 1.1)` before final write
- Added `aces-tone-map` to WGSL header features
- Added `Upgraded: 2026-06-06` date line (was missing)

## Why These Changes
String theory shader had warm fundamentals, cool harmonics, bright nodes, temporal persistence, semantic alpha, audio reactivity, depth, and dataA. ACES was missing.

## Wow Factor
The warm string fundamentals (orange/gold) and cool harmonics (cyan/blue) gain more separation and vibrancy under ACES. The bright white node highlights roll off smoothly, giving the vibrating strings a more luminous, physical presence.

## Risks for Polish
None — mechanical ACES addition.

## Validation
- naga: ✅ pass
- generate_shader_lists.js: ✅ pass
- check_duplicates.js: ✅ pass
