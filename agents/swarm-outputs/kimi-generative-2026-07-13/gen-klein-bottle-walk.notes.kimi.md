# gen-klein-bottle-walk — Interactivist upgrade notes

## Changes made
- Expanded from 148 to 201 lines (+53).
- Workgroup size changed from `(8, 8, 1)` to `(16, 16, 1)`.
- Added `PI` / `TAU` constants and an attack/release `envFollow()` helper.
- Added `shockwave()` using the canonical `u.ripples` buffer for click bursts.
- Mouse now acts as a gravity well:
  - Warps Klein-bottle walk speed.
  - Warps the parametric surface radius.
  - Adds a subtle positional offset to the walk coordinates.
- Mouse-down boosts gravity-well strength and shockwave intensity.
- Raw `bass/mids/treble` replaced with smoothed envelopes read from `dataTextureC` and written back to `dataTextureA`.
- Temporal feedback trail: previous frame color sampled from `readTexture` and blended with the new frame using an audio/reactivity-driven mix.
- Semantic alpha based on diffuse lighting, surface noise, specular, shockwaves, and gravity-well proximity (not hardcoded 1.0).
- `writeTexture`, `writeDepthTexture`, and `dataTextureA` are written every frame.
- Branchless `select()` used for envelope attack/release; `mix()`/`clamp()` preferred over per-pixel branches.

## JSON update
- `workgroup_size` updated to `[16, 16, 1]`.
- Added tags: `mouse-interactive`, `temporal`, `attack-release`.
- Added features: `mouse-gravity-well`, `click-shockwaves`, `attack-release-envelopes`, `temporal-feedback`.

## Verification
```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-klein-bottle-walk.wgsl
```
Result: ✅ naga OK, bindgroup compatible.
