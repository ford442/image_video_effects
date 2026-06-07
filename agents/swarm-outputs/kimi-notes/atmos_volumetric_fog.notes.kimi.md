# atmos_volumetric_fog — Batch 2 Upgrade Notes

## Changes Made
- Added `acesToneMap` function and applied to final composite
- Added audio reactivity: bass → fog density, mids → color shift, treble → noise
- Added temporal feedback: read dataTextureC, blend with prev.rgb * 0.95
- Added chromatic aberration: R/B shift by bass + depth
- Added dataTextureA writeback
- Updated header features and Upgraded date

## Validation
- naga: ✅ pass
