# rain-ripples — Retry Upgrade Notes

## Objective
Preserve the original ripple displacement, FBM micro-ripples, specular highlights, depth fog, chromatic aberration, and audio reactivity while layering richer surface effects.

## Line Count
- Original HEAD: 126 lines
- Retry upgrade: 186 lines
- Delta: +60 lines (within +30 to +80 target)

## Algorithmic Upgrades Added
1. **Domain-warped FBM micro-ripples**  
   The original micro-ripple FBM now uses a two-layer domain warp (`q`) for more natural water-surface turbulence.

2. **Voronoi cellular raindrop impacts** (`voronoi`, `hash22`)  
   A 3×3 Voronoi neighborhood generates new cellular raindrop rings with per-cell random phases, added to the displacement field.

3. **Caustic refraction overlay** (`caustics`)  
   Overlapping warped sine gradients simulate water caustics, masked to wet areas.

4. **Wet-area SDF mask** (`wetMask`)  
   FBM-driven soft patches restrict caustics and thin-film effects to plausible wet regions.

5. **Thin-film rainbow interference**  
   A curvature-derived phase shifts RGB channels independently, producing rainbow sheen on wet ripples.

## Validation
- `naga public/shaders/rain-ripples.wgsl` → OK
- `node scripts/generate_shader_lists.js` → OK
- `node scripts/check_duplicates.js` → OK

## JSON Changes
- Added features: `voronoi-raindrops`, `caustics`, `thin-film-interference`
- Kept `upgraded-rgba`, `workgroup_size: [16,16,1]`, and all 4 params unchanged
