# Worker Implementation Notes — Gemini Argon4 (`argon4/batch-04`)

**Swarm:** `gemini-2026-10-18-argon4-batch-04`
**Date:** 2026-10-18
**Contract:** `docs/SHADER_UPGRADE_BATCH.md` (including `§12` Mechanism Interrogation, Formula Admission, and Batch De-duplication)

---

## Batch Formula De-duplication Ledger (§12.2 / §12.4)

No `§12.2` row appears on more than 2 shaders in the batch:

| `§12.2` Row | Count (≤ 2) | Shaders Using Row |
|---|---:|---|
| **§12.2A Anti-halo envelope** (`clamp(u, erosion-r, dilation+r)`) | 1 | `glass-shatter-morph` |
| **§12.2A Local contrast / bevel relief** | 1 | `fractal-glass-distort` |
| **§12.2D 9-point Laplacian** (`lap9`) | 1 | `gen-liquid-crystal-hive-mind` |
| **§12.2E 5-tap AO** (`aoFive` / `cavityAO`) | 2 | `gen-prismatic-singularity-engine`, `gen-prismatic-cyber-chrono-void-kitsune` |
| **§12.2E Tetrahedral curvature** (`sdfCurvature`) | 1 | `gen-bismuth-crystal-citadel` |
| **§12.2E Fold count as material** | 2 | `gen-kimi-crystal`, `gen-holographic-bismuth-core-reactor` |
| **§12.2E Smooth min (`smin`) / chamfer** | 2 | `gen-chrono-kitsune-prism-weaver`, `gen-chronomorphic-glass-tesseract` |
| **§12.2E Orbit trap** | 1 | `fractal-glass-distort` |
| **§12.2F Fresnel–Schlick** | 2 | `gen-bismuth-crystal-citadel`, `gen-holographic-bismuth-core-reactor` |
| **§12.2F Snell vector refraction** | 2 | `gen-chrono-kitsune-prism-weaver`, `glass-shatter-morph` |
| **§12.2F Cauchy dispersion** | 1 | `gen-kimi-crystal` |
| **§12.2F Thin-film interference** | 1 | `gen-liquid-crystal-hive-mind` |
| **§12.2F Beer–Lambert absorption** | 1 | `gen-prismatic-cyber-chrono-void-kitsune` |
| **§12.2F Henyey–Greenstein phase** | 1 | `gen-prismatic-singularity-engine` |
| **§12.2F Airy ring** | 1 | `gen-chronomorphic-glass-tesseract` |

---

## Per-Shader Implementation Summary

### 1. `gen-prismatic-singularity-engine` (`public/shaders/gen-prismatic-singularity-engine.wgsl`)
- **Idea 4 (`// ── Idea 4: Relativistic n=1 Photon Ring & Doppler-Beamed Accretion Disk (§12.2F Henyey–Greenstein phase) ──`)**: Added `photonRing = exp(-pow((b - 1.48) * 18.0, 2.0))` around the critical impact parameter and `dopplerBoost = pow(clamp(1.0 + 0.52 * orbitalTangent, 0.35, 1.85), 3.0)` with Henyey–Greenstein forward phase weighting (`hgPhase(dot(rd, tangentDir), 0.55)`) across the accretion disk.
- **Idea 5 (`// ── Idea 5: Gyroid Containment Lattice 5-Tap AO & Temporal Photon-Echo Persistence (§12.2E 5-tap AO) ──`)**: Added `aoFive(p, n, time)` (`§12.2E`) on gyroid containment shell hits to ground the containment struts against the glowing core, plus `dataTextureC` temporal persistence (`prevHistory`).
- **Sliders (`zoom_params`)**: `x` = Intensity, `y` = Speed, `z` = Scale, `w` = Mouse Influence.

### 2. `gen-kimi-crystal` (`public/shaders/gen_kimi_crystal.wgsl`)
- **Prelude migration**: Migrated pasted 13-binding header to `#include "_prelude.wgsl"` via `python3 scripts/migrate_to_prelude.py --files public/shaders/gen_kimi_crystal.wgsl`.
- **Idea 4 (`// ── Idea 4: Stepped Hexagonal Dendrite Hopper Terraces & Midrib Spine Veils (§12.2E Fold count as material) ──`)**: Extended `sdSnowflake` with quantized basal `z` hopper steps (`hopperStep`) and 6-fold sector fold-ridge risers (`hopperRiser`) plus internal basal midrib air-inclusion veils (`midribVeil`).
- **Idea 5 (`// ── Idea 5: Circumzenithal 90-Degree Basal-Plate Halo Arc & Temporal Frost Persistence (§12.2F Cauchy dispersion) ──`)**: Added a 3-wavelength Cauchy-dispersed circumzenithal halo arc (`circumzenithalArc`) overhead (`rd.y < -0.1`) and blended `dataTextureC` temporal frost persistence (`prevFrost`).
- **Sliders (`zoom_params`)**: `x` = Branch Complexity, `y` = Prism Dispersion, `z` = Rim Glow, `w` = Specular Sharpness.

### 3. `gen-liquid-crystal-hive-mind` (`public/shaders/gen-liquid-crystal-hive-mind.wgsl`)
- **Idea 4 (`// ── Idea 4: Homeotropic Cell-Wall Director Anchoring & Grandjean Pitch Stripes (§12.2F Thin-film interference) ──`)**: Anchored the nematic director perpendicular to each hex wall (`wallAnchoring = normalize(hexUv)`) near `smoothstep(0.18, 0.48, d)` and modulated optical retardance with quantized cholesteric Grandjean pitch stripes (`grandjean`).
- **Idea 5 (`// ── Idea 5: 9-Point Laplacian Synaptic Excitable Wave & Hex-Corner Meniscus Pooling (§12.2D 9-point Laplacian) ──`)**: Added a 9-point isotropic Laplacian (`lap9HivePulse`) over `dataTextureC.a` to propagate excitable synaptic waves across neighboring hex cells, plus hex-vertex capillary meniscus lenses (`meniscus`).
- **Sliders (`zoom_params`)**: `x` = Hive Scale, `y` = Birefringence, `z` = Director Twist, `w` = Synaptic Pulse.

### 4. `gen-bismuth-crystal-citadel` (`public/shaders/gen-bismuth-crystal-citadel.wgsl`)
- **Idea 4 (`// ── Idea 4: Tetrahedral Curvature Terrace-Edge Oxide Shift & Polysynthetic Twin Lamellae (§12.2E Tetrahedral curvature) ──`)**: Added `calcCurvature(p)` (`§12.2E sdfCurvature`) to drive gold-to-violet oxide thin-film run-up along convex hopper edges (`curv * 0.42`) and diagonal polysynthetic twin lamellae striations (`twinLamellae`) on vertical step risers.
- **Idea 5 (`// ── Idea 5: Molten Bismuth Meniscus Incandescence & Solidifying Hopper Rafts (§12.2F Fresnel–Schlick) ──`)**: Added drifting stepped micro-hopper crystal rafts (`solidifyingRafts`) with Fresnel–Schlick metallic reflections and glowing incandescent meniscus rims (`meniscusEmber`) where the citadel walls meet the molten bismuth floor (`p.y < -1.8`).
- **Sliders (`zoom_params`)**: `x` = Citadel Scale, `y` = Oxide Iridescence, `z` = Step Depth, `w` = Metallic Sheen.

### 5. `gen-prismatic-cyber-chrono-void-kitsune` (`public/shaders/gen-prismatic-cyber-chrono-void-kitsune.wgsl`)
- **Idea 4 (`// ── Idea 4: Faceted Kitsune Fox-Ear & Snout Crest SDF with 5-Tap Armor Crevice AO (§12.2E 5-tap AO) ──`)**: Added explicit fox ears (`d_ears`) and tapered snout bridge (`d_snout`) to `sceneSDF` so the central core reads unmistakably as a kitsune mask, grounded by 5-tap `aoFive` crevice occlusion (`armorAO`) and glowing cyber-visor eye slits (`visorEyeGlow`).
- **Idea 5 (`// ── Idea 5: Beer-Lambert Prismatic Armor Subsurface Absorption & 9-Tail Arc Filaments (§12.2F Beer–Lambert absorption) ──`)**: Added Beer–Lambert chromatic subsurface transmission (`armorAbsorption = exp(-thickness * vec3(1.8, 0.65, 0.22))`) through the armor facets and 9-fold inter-tail plasma arc filaments (`interTailArc`) bridging adjacent tail ribbons.
- **Sliders (`zoom_params`)**: `x` = Intensity, `y` = Speed, `z` = Scale, `w` = Mouse Influence.

### 6. `gen-chrono-kitsune-prism-weaver` (`public/shaders/gen-chrono-kitsune-prism-weaver.wgsl`)
- **Idea 4 (`// ── Idea 4: Fox-Ear Prism Crest SDF & 3-Wavelength Snell-Cauchy Internal Refraction (§12.2F Snell vector refraction) ──`)**: Added twin faceted kitsune ear crests (`d_earCrest`) joined by `smin` to the octahedral core and 3-wavelength 3D vector Snell refraction (`refract(rd, n, 1.0 / iorRGB)`) sampling internal folded chrono-loom caustics (`prismInternalRefract`).
- **Idea 5 (`// ── Idea 5: Chevron Guard-Hair Fur Barbules & Dispersive Chrono-Echo Trail (§12.2E Smooth min / chamfer) ──`)**: Sculpted directional chevron guard-hair fur barbules (`furBarbules`) along the 9 tail ribbons (`res.y == 2.0`) and upgraded the `dataTextureC` temporal echo into a 3-wavelength radial dispersive chrono-trail (`prevR`, `prevG`, `prevB`).
- **Sliders (`zoom_params`)**: `x` = Intensity, `y` = Speed, `z` = Scale, `w` = Mouse Influence.

### 7. `gen-chronomorphic-glass-tesseract` (`public/shaders/gen-chronomorphic-glass-tesseract.wgsl`)
- **Idea 4 (`// ── Idea 4: Schlegel 4D Inner-Cube & 16-Vertex Diagonal Strut Frame with Beveled Cell Panes (§12.2E Smooth min / chamfer) ──`)**: Extended `map()` with the inner hypercube frame (`distInner`), the 8 diagonal 4D-to-3D vertex-connecting struts (`distDiag`) joined via `smin`, and chamfer-inset translucent cell panes (`paneInset`).
- **Idea 5 (`// ── Idea 5: 16-Vertex Airy Diffraction Glints & Temporal 4D Rotation Trail (§12.2F Airy ring) ──`)**: Projected the 16 4D hypercube vertices onto the view ray to render `§12.2F` Airy diffraction rings (`airyDisc(vTheta * 55.0)`) and 4-point cross flares (`vertexAiryGlint`), plus `dataTextureC` temporal persistence (`chronoHistory`).
- **Sliders (`zoom_params`)**: `x` = 4D Rotation Speed, `y` = Glass Thickness, `z` = Chromatic Dispersion, `w` = Temporal Echo.

### 8. `gen-holographic-bismuth-core-reactor` (`public/shaders/gen-holographic-bismuth-core-reactor.wgsl`)
- **Idea 6 (`// ── Idea 6: KIFS Fold-Generation Terrace Oxide Stepping & 4-Tap Cavity AO (§12.2E Fold count as material) ──`)**: Extended `coreSeamTrap` to count mirror-plane reflections (`foldGen`) across the 4 KIFS levels, stepping the physical oxide thickness (`oxideThicknessNm + foldGen * 68.0`) per terrace generation in `bismuthOxidationColor` and grounding stepped recesses with 4-tap `cavityAO`.
- **Idea 7 (`// ── Idea 7: Cherenkov Phase-Cone Radiation & Control-Rod Coolant Wake Rings (§12.2F Fresnel–Schlick / Henyey–Greenstein) ──`)**: Added criticality-throttled Cherenkov blue-violet phase-cone radiation (`cherenkovCone` peaking around `cosPhase = 0.72`) and concentric cyan-white coolant wake rings (`rodWakeAccum`) radiating around the 4 control-rod tips.
- **Sliders (`zoom_params`)**: `x` = Intensity, `y` = Speed, `z` = Scale, `w` = Mouse Influence.

### 9. `glass-shatter-morph` (`public/shaders/glass-shatter-morph.wgsl`)
- **Prelude migration**: Migrated pasted 13-binding header to `#include "_prelude.wgsl"` via `python3 scripts/migrate_to_prelude.py --files public/shaders/glass-shatter-morph.wgsl`.
- **Idea 4 (`// ── Idea 4: F2-F1 Polygonal Voronoi Fracture Bevels & Conchoidal Wallner Hackle Ripples (§12.2F Snell vector refraction) ──`)**: Extended `voronoi()` to return true `F2 - F1` polygonal boundary distance (`edgeDist`) and inward normal (`edgeNormal`), driving 3D vector Snell bevel refraction (`refract(vec3(0,0,-1), normal, 1.0/1.52)`) and concentric conchoidal Wallner stress-wave hackle ripples (`wallnerWave`).
- **Idea 5 (`// ── Idea 5: Morphological Top-Hat Crack Frosting & Anti-Halo Interior Clamp (§12.2A Anti-halo envelope) ──`)**: Combined white/black morphological top-hat residuals (`whiteTopHat`, `blackTopHat`) into crystalline ground-glass crack frosting (`topHatFrost`) along `edgeProx` and clamped interior shard refraction within `[erosion - r, dilation + r]` (`§12.2A`).
- **Sliders (`zoom_params`)**: `x` = Shard Size, `y` = Displacement, `z` = Morph Blend, `w` = Edge Width.

### 10. `fractal-glass-distort` (`public/shaders/fractal-glass-distort.wgsl`)
- **Idea 4 (`// ── Idea 4: IFS Orbit-Trap Ream Striae Veins & Trapped Air-Seed Bubbles (§12.2E Orbit trap) ──`)**: Extended `ifsAttractorDensity` to return the cross-axis orbit trap `veinTrap = min(veinTrap, min(abs(q.x), abs(q.y)))`, driving antique hand-blown glass ream striae (`reamVein`, `striaeRefract`) and specular trapped air-seed bubbles (`seedBubble`).
- **Idea 5 (`// ── Idea 5: 3D Rounded Lead-Came H-Channel Relief, Silvered Solder Bosses & Pane Bevel Drop-Shadow (§12.2A Local contrast / bevel relief) ──`)**: Upgraded the flat lead line into a 3D cylindrical H-channel pewter came (`cameNormal`, `cameSpec`) with silvered solder-joint bosses (`solderBoss = leadX * leadY`) at 4-way intersections and a directional pane bevel drop-shadow (`paneShadow`).
- **Sliders (`zoom_params`)**: `x` = Contraction, `y` = IFS Rotation, `z` = Refraction, `w` = Aberration.
