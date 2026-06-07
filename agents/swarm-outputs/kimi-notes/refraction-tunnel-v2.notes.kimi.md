# refraction-tunnel v2 Upgrade Notes

## Agent Perspectives
- **Algorithmist**: Replaced simple warp with multi-layer Snell's-law refraction. Added per-channel chromatic dispersion (RGB IOR splitting via `asin`). Rainbow caustics driven by hash noise on tunnel walls.
- **Visualist**: Volumetric fog mixed by depth and tunnel proximity. ACES filmic tone mapping. Anamorphic streaks along the tangential direction. Wall-proximity glow.
- **Interactivist**: Bass drives rotation speed (`rotSpeed = 1.0 + bass * 2.5`). Mouse controls tunnel curvature via `mouseOffset`. Depth adds atmospheric perspective in fog term.
- **Optimizer**: Early boundary check. `textureSampleLevel` with LOD 0.0. Branchless `select` where possible. Distance-based LOD via `safeDist` smoothing.

## Alpha Strategy
`alpha = wallProximity * aberration * 3.0 + insideWall * 0.25 + bass * 0.08`
Wall proximity modulated by refraction strength ensures transparent center, opaque edges.

## Lines
129 lines (was 89)

## Files Written
- `public/shaders/refraction-tunnel.wgsl`
- `shader_definitions/distortion/refraction-tunnel.json`
