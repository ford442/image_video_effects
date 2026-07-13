# gen-de-jong-attractor — Interactivist upgrade notes

## Changes made
- Expanded from 135 to 176 lines (+41).
- Preserved existing `(16, 16, 1)` workgroup size and canonical 13-binding header.
- Added attack/release `envFollow()` helper.
- Added `shockwave()` using the canonical `u.ripples` buffer for click bursts.
- Mouse now acts as a gravity well:
  - Attracts / displaces the view position.
  - Modulates the attractor parameter amplitude.
  - Narrows the glow radius near the cursor.
- Mouse-down boosts shockwave intensity.
- Raw `bass/mids/treble` replaced with smoothed envelopes read from `dataTextureC.gba` and written back to `dataTextureA.gba`.
- `dataTextureA.r` continues to carry the accumulated density for the Monte Carlo feedback loop.
- Temporal color feedback: previous frame color sampled from `readTexture` and blended with the new attractor color.
- Semantic alpha based on density, bass envelope, and shockwave intensity.
- `writeTexture`, `writeDepthTexture`, and `dataTextureA` are written every frame.
- Branchless `select()` used for envelope attack/release.

## JSON update
- Added tags: `mouse-interactive`, `attack-release`.
- Added features: `mouse-gravity-well`, `click-shockwaves`, `attack-release-envelopes`, `temporal-feedback`.

## Verification
```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-de-jong-attractor.wgsl
```
Result: ✅ naga OK, bindgroup compatible.
