# gen-lorenz-attractor — Interactivist upgrade notes

## Changes made
- Expanded from 140 to 183 lines (+43).
- Preserved existing `(16, 16, 1)` workgroup size and canonical 13-binding header.
- Added attack/release `envFollow()` helper.
- Added `shockwave()` using the canonical `u.ripples` buffer for click bursts.
- Mouse now acts as a gravity well:
  - Modulates the `rho` chaos parameter.
  - Attracts / displaces the projected view position.
  - Narrows the glow radius near the cursor.
- Mouse-down boosts shockwave intensity.
- Raw `bass/mids/treble` replaced with smoothed envelopes read from `dataTextureC.gba` and written back to `dataTextureA.gba`.
- `dataTextureA.r` continues to carry the accumulated density for the Monte Carlo feedback loop.
- Temporal color feedback: previous frame color sampled from `readTexture` and blended with the new lobe color.
- Semantic alpha based on density, bass envelope, and shockwave intensity.
- `writeTexture`, `writeDepthTexture`, and `dataTextureA` are written every frame.
- Branchless `select()` used for envelope attack/release.

## JSON update
- Added tags: `mouse-interactive`, `attack-release`.
- Added features: `mouse-gravity-well`, `click-shockwaves`, `attack-release-envelopes`, `temporal-feedback`.

## Verification
```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-lorenz-attractor.wgsl
```
Result: ✅ naga OK, bindgroup compatible.
