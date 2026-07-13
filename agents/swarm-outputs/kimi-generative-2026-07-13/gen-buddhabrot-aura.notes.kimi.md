# gen-buddhabrot-aura — Interactivist upgrade notes

## Changes made
- Expanded from 150 to 193 lines (+43).
- Preserved existing `(16, 16, 1)` workgroup size and canonical 13-binding header.
- Added `TAU` constant and attack/release `envFollow()` helper.
- Added `shockwave()` using the canonical `u.ripples` buffer for click bursts.
- Mouse now acts as a gravity well:
  - Increases orbit iteration count near the cursor.
  - Displaces the fractal center toward the cursor.
- Mouse-down boosts shockwave intensity.
- Switched `dataTextureC` read from `textureSampleLevel` to `textureLoad` for consistency with storage-state reads.
- Raw `bass/mids/treble` replaced with smoothed envelopes read from `dataTextureC.rgb` and written back to `dataTextureA.rgb`.
- `dataTextureA.a` carries the combined interaction intensity (gravity well + shockwave).
- Temporal feedback trail: previous frame color sampled from `readTexture` and blended with the new Buddhabrot color.
- Semantic alpha based on density, escape velocity, depth, and shockwave intensity.
- `writeTexture`, `writeDepthTexture`, and `dataTextureA` are written every frame.
- Branchless `select()` used for envelope attack/release.

## JSON update
- Added tags: `temporal`, `attack-release`.
- Added features: `mouse-gravity-well`, `click-shockwaves`, `attack-release-envelopes`, `temporal-feedback`.

## Verification
```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-buddhabrot-aura.wgsl
```
Result: ✅ naga OK, bindgroup compatible.
