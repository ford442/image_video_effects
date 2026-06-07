# encaustic-wax v2 Upgrade Notes

## Agent Perspectives

### Algorithmist
- Added thermal flow simulation: global bass heat gun + localized mouse hotspot.
- Viscosity decreases with heat, driving wax flow displacement.
- Replaced simple noise with 3-layer FBM wax strata; pigments separate by density per layer.
- Depth modulates wax thickness (nearer = thicker build-up).

### Visualist
- Translucent wax layers with subsurface scattering (warm amber transmission).
- Metallic pigment sparkle via hashed high-power specular.
- HDR specular on impasto ridges with Phong-like normal from flow.
- Procedural canvas grain (3-octave noise overlay).
- Luminance-driven bloom and vignette.
- ACES tone mapping on final composite.

### Interactivist
- Bass (plasmaBuffer[0].x) drives global heat gun intensity.
- Mouse applies localized heat and pull within a 0.45 radius.
- Depth controls pigment build-up thickness and SSS strength.

### Optimizer
- Loop unrolls to 3 fixed wax layers.
- Single `textureSampleLevel` for base read; reused flow for normal.
- `select()` used for sign; branchless smoothstep masks.

## Files Modified
- `public/shaders/encaustic-wax.wgsl`
- `shader_definitions/artistic/encaustic-wax.json`

## Metrics
- Lines: 165
- naga: ✅ Validation successful
