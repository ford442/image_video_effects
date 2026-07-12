# ambient-liquid — Retry Upgrade Notes

## Objective
Keep the original curl-noise liquid distortion, mouse attraction, ripple eddies, HSV shift, and semantic alpha while adding several new algorithmic layers.

## Line Count
- Original HEAD: 141 lines
- Retry upgrade: 195 lines
- Delta: +54 lines (within +30 to +80 target)

## Algorithmic Upgrades Added
1. **Advected curl noise** (`curl2DAdv`)  
   The curl field is sampled at an advected offset to add extra vorticity and richer rotational detail.

2. **Domain-warped FBM turbulence**  
   A separate FBM pass is warped by the displacement field and added to the total liquid displacement.

3. **Reaction-diffusion spot pattern** (`grayScott`)  
   A sinusoidal approximation of Gray-Scott spots modulates local hue and saturation.

4. **SDF metaball ink blobs** (`metaballField`, `smin`)  
   Four smooth-min metaballs generate organic dark ink silhouettes blended into low-luma regions.

5. **Anisotropic specular highlight**  
   A specular lobe aligned with the flow direction adds liquid-surface sheen, boosted by treble from `plasmaBuffer`.

6. **Vignette + film grain**  
   A radial vignette darkens the corners and hash-based grain is added for texture.

## Validation
- `naga public/shaders/ambient-liquid.wgsl` → OK
- `node scripts/generate_shader_lists.js` → OK
- `node scripts/check_duplicates.js` → OK

## JSON Changes
- Added features: `reaction-diffusion`, `sdf-metaballs`, `anisotropic-specular`
- Kept `upgraded-rgba`, `workgroup_size: [16,16,1]`, and all 4 params unchanged
