# Blackbody Phase-C leftover six — NOTES

Per `docs/SHADER_UPGRADE_BATCH.md` §9. Cards in BRIEFS.md (written first).

## thermal-vision-blackbody
- Kept: temp_low / temp_high / contrast / shift; luma pow-contrast; mouse heat disk; 12-tap bright bloom
- Ideas in diff: row-correlated NUC noise + periodic calibration bars; hot lag `max(T, prev.a*15000*0.94)` from exact C
- Floor: plasmaBuffer[0].xyz; semantic alpha; ACES on display only
- A packing: raw thermal RGB + normalized T in `.a`

## chroma-kinetic-blackbody
- Kept: strength / radius / luma_influence / rotation; rotated mouse-dir split
- Ideas in diff: λ-scaled offsets 1.0 / 0.18 / 0.68 on the split axis; kinetic boost from `|luma - C luma|`
- Floor: stopped dual-mapping sliders to thermal ranges / glowAmount; temperature from luma; write A (HEAD did not)
- A packing: ACES display RGBA

## energy-shield-blackbody
- Kept: hex_scale / ripple_speed / impact_strength / decay; hexDist grid; click-ripple heat; cyan trail
- Ideas in diff: hashed whole-cell strike radius; edge Faraday current with cooler fill
- Floor: exact `textureLoad` on C (was filtered sample); temperature from activation not stolen hex_scale
- A packing: raw trail scalar in A.r (not ACES)

## stellar-plasma-blackbody
- Kept: temp_shift / speed / zoom_scale / thermal_intensity; q/r domain warp; held-mouse hotspot
- Ideas in diff: `|∇f|` filaments via extra FBM tap; warp-advected C heat along `r`
- Floor: `plasmaBuffer[0].xyz` instead of `u.config.yzw`; early `dist>3` writes A; dropped 12-tap ember ring
- A packing: raw thermal RGB + normalized T

## sim-heat-haze-blackbody
- Kept: temperature / convection_speed / distortion / heat_sources; 3×3 diffuse + 0.98 cool; ground/source/mouse heat
- Ideas in diff: Schlieren along ∇T; plume shear `displacement.x += grad.y * …`
- Floor: clamped neighbor C loads; no T in depth; dropped 8-tap ember ring
- A packing: raw temperature in A.r

## encaustic-wax-blackbody
- Kept: thickness / texture / radius / thermal_intensity; 5×5 blur; height-field spec; wax_alpha
- Ideas in diff: cooling skin (`waxDetail` cooler); iron ridges along height tangent
- Floor: write A (HEAD did not); pass through scene depth (HEAD stored melt_thickness); dropped photo-luma ember loop
- A packing: ACES display RGBA

## Gates
Naga 6/6, extraBuffer 0 new, dead sliders 0, catalog 1,367 (unchanged — existing IDs), Jest 689 pass / 6 fail = pre-existing WASM `bridge/api.js`, SKIP_WASM_BUILD=1 build green. Real-GPU QA external.
