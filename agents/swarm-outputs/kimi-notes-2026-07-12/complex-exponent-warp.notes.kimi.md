# complex-exponent-warp — Retry Upgrade Notes

## Objective
Keep the original complex-exponent warp `z -> z^w`, FBM pre-warp, mouse-driven exponent, spiral rotation, depth-aware fog, chromatic aberration, and ACES tone mapping while adding fractal/SDF enhancements.

## Line Count
- Original HEAD: 129 lines
- Retry upgrade: 209 lines
- Delta: +80 lines (at the upper boundary of +30 to +80 target)

## Algorithmic Upgrades Added
1. **Dual-layer domain-warped FBM** (`fbmWarp`)  
   A feedback FBM layer warps the domain before the complex exponent is applied, adding swirling detail beyond the original single warp.

2. **Julia set orbit-trap** (`juliaOrbit`)  
   A time-varying Julia constant is iterated from the warped complex coordinate, producing orbit-trap distance and iteration count used for glow and alpha.

3. **Newton fractal color overlay** (`newtonColor`, `cdiv`)  
   Newton iterations for `z^3 - 1` classify pixels by which cube root they converge to, adding colored fractal bands.

4. **SDF cardioid silhouette** (`sdfCardioid`)  
   A rotating cardioid signed-distance field darkens organic silhouette regions in the frame.

5. **Stereo anaglyph-style chromatic split**  
   Red and blue channels are offset based on the warped UV distance from center, enhanced by treble.

## Validation
- `naga public/shaders/complex-exponent-warp.wgsl` → OK
- `node scripts/generate_shader_lists.js` → OK
- `node scripts/check_duplicates.js` → OK

## JSON Changes
- Added features: `julia-orbit-trap`, `sdf-cardioid`, `newton-fractal`
- Kept `upgraded-rgba`, `workgroup_size: [16,16,1]`, and all 4 params unchanged
