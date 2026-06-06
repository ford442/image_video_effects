# gen-opal-circuit — Batch 1 Upgrade Notes

## Changes Made
- Added `acesToneMap` function
- Applied `color = acesToneMap(color * 1.1)` before final write
- Added `aces-tone-map` to WGSL header features
- Updated `Upgraded:` date to `2026-06-06`

## Why These Changes
Opal circuit had iridescent signal traces, temporal echoes, semantic alpha, audio reactivity, depth, and dataA writeback. Only ACES missing.

## Wow Factor
The opal iridescence (R/G/B signal-phase shifts) gains a more jewel-like, saturated quality under ACES. The white via blooms roll off smoothly instead of clipping to flat white.

## Risks for Polish
None — minimal change.

## Validation
- naga: ✅ pass
- generate_shader_lists.js: ✅ pass
- check_duplicates.js: ✅ pass
