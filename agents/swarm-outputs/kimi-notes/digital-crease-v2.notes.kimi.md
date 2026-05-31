# digital-crease v2 Upgrade Notes

## Agent Perspectives

### Algorithmist
- Origami crease pattern with mountain/valley assignment from signed sine fold.
- Kawasaki-Justin flat-foldability approximation via `1.0 - abs(sin(baseFold * 0.5)) * 0.35` damping.
- Mouse performs local folds using exponential falloff from cursor.
- Temporal fold persistence sampled from `dataTextureC`.
- Depth-driven layer ordering with shadow casting (`step` logic).

### Visualist
- Digital paper texture with directional fiber grain (`paperTex`).
- Paper normal shading with directional light.
- Chromatic folding: R/B/G sample from offset UVs based on crease depth.
- HDR specular on crease highlights + separate crease-normal specular.
- Mountain/valley tint variation for origami realism.
- Vignette, ambient fill, and ACES tone mapping.

### Interactivist
- Bass drives fold animation speed (`speed = time * (1.0 + audio.x * 0.5)`).
- Mouse creates local creases near cursor.
- Depth controls paper layer ordering and shadow intensity.

### Optimizer
- Reused `angle` and `dist` for multiple effects (fold, fiber, vignette).
- Single `dataTextureC` read for temporal persistence.
- `select()` for mountain/valley sign; branchless shadow via `step()`.

## Files Modified
- `public/shaders/digital-crease.wgsl`
- `shader_definitions/geometric/digital-crease.json`

## Metrics
- Lines: 179
- naga: ✅ Validation successful
