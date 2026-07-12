# hyb-kaleidoscope-pulse — Retry Upgrade Notes

## Objective
Preserve the original HEAD behavior (kaleidoscope mirror + radial pulse + FBM domain warp + semantic alpha) and expand it with richer algorithmic layers.

## Line Count
- Original HEAD: 112 lines
- Retry upgrade: 167 lines
- Delta: +55 lines (within +30 to +80 target)

## Algorithmic Upgrades Added
1. **Two-layer domain-warped FBM** (`fbmWarp`)  
   A feedback FBM layer displaces the domain of a second FBM pass, producing more organic, evolving warp than the original single-layer warp.

2. **SDF star primitive blended with smooth-min** (`sdfStar`, `smin`)  
   A star-shaped signed-distance field is folded by the same segment count as the kaleidoscope and merged with the radial pulse via `smin` for smooth, glowing rays.

3. **Strange-attractor orbit-trap coloring** (`attractorOrbit`)  
   A Pickover/Clifford-style 2D attractor iterates from each pixel and measures orbit-trap distance to modulate pulse hue.

4. **Phase-animated kaleidoscope**  
   The kaleidoscope function now accepts a phase offset, used to give slow counter-rotating inner/outer rings.

5. **Chromatic split along radial direction**  
   RGB channels are separated along the normalized radius using the kaleidoscope sample UVs.

## Validation
- `naga public/shaders/hyb-kaleidoscope-pulse.wgsl` → OK
- `node scripts/generate_shader_lists.js` → OK
- `node scripts/check_duplicates.js` → OK

## JSON Changes
- Added features: `sdf-primitives`, `strange-attractor`, `chromatic-split`
- Kept `upgraded-rgba`, `workgroup_size: [16,16,1]`, and all 4 params unchanged
