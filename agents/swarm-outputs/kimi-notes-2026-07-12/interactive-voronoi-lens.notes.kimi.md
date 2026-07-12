# interactive-voronoi-lens — retry upgrade notes

## Goal
Richer, expanded upgrade of the original Interactive Voronoi Lens. Preserves the Voronoi-cell lens distortion, parameter behaviour, and semantic alpha while adding more interactive physical layers.

## What was kept
- Original 13-binding canonical header and `Uniforms` layout.
- `@compute @workgroup_size(16, 16, 1)`.
- Hash-based Voronoi cell generation with audio-jittered points.
- Mouse-driven focus, temporal trail accumulation, depth fog, and neon cell-boundary accents.
- Parameter mapping: cell_density (p1), lens_strength (p2), chaos (p3), lens_curve (p4).
- Semantic alpha based on cell edges and mouse influence.

## New interactivity upgrades
1. **Spring-damper mouse follow**
   - Persists `smoothMouse` and `velocity` in `extraBuffer`, integrated with `dt`.
   - The gravity well uses the smoothed cursor so the lens feels weighted.

2. **Mouse gravity well on cell centres**
   - Nudges each cell centre toward the lagging cursor, warping the lens field in a continuous, mouse-attracted flow.
   - Strength falls off smoothly with distance and is boosted by the bass envelope.

3. **Click shockwave**
   - Detects mouse-down transitions and stores click position/time.
   - Expands a ring in corrected UV space that pushes the lens offset outward and paints a brief neon-blue ring.

4. **Emergent feedback loop**
   - Adds a displacement component proportional to `length(prev.rgb)` so previously bright lens regions continue to drift, creating evolving cell distortion.

## Validation
- `naga public/shaders/interactive-voronoi-lens.wgsl` → Validation successful.
- Line count: original HEAD 132 → retry 209 (+77 lines).

## Files touched
- `public/shaders/interactive-voronoi-lens.wgsl` (overwrite)
- `shader_definitions/interactive-mouse/interactive-voronoi-lens.json` (already satisfied requirements; not modified)
