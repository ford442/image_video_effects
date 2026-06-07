# gen-murmuration-phantom — Batch 2 Upgrade Notes

## Changes Made
- Renamed `aces(c)` → `acesToneMap(x)` for standard compliance
- Added temporal feedback: read dataTextureC, blend with prev.rgb * 0.92
- Added chromatic aberration: R/B channel shift by bass + density
- Added dataTextureA writeback
- Updated header: added upgraded-rgba, aces-tone-map, temporal-feedback, chromatic-aberration
- Added Upgraded: 2026-06-06

## Validation
- naga: ✅ pass
