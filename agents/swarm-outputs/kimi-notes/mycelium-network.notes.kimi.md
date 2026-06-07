# mycelium-network — Batch 2 Upgrade Notes

## Changes Made
- Added temporal feedback: read dataTextureC, blend with prev.rgb * 0.92
- Added chromatic aberration: R/B channel shift by bass + glow
- dataTextureA write already present, now writes blended color

## Validation
- naga: ✅ pass
