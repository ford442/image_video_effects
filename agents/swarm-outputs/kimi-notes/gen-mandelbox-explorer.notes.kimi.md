# gen-mandelbox-explorer — Batch 2 Upgrade Notes

## Changes Made
- Fixed duplicate ACES: removed sweep-added `acesToneMap` function and application
- Kept original `aces_tonemap` function and its application
- Added chromatic aberration: R/B channel shift by bass + depth
- Removed duplicate `aces-tone-map` from header

## Validation
- naga: ✅ pass
