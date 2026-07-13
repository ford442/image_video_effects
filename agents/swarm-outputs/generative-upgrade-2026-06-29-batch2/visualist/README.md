# Visualist Upgrade — `gen-minimal-surface-soap-iridescence`

**Agent:** Visualist (Batch 2)  
**Target:** HDR color science, cinematic lighting, atmospheric depth, emotional impact  
**Date:** 2026-06-29

## Changelog

### Core improvements
- **Analytic normals & cinematic lighting**  
  Replaced the original finite-difference curvature proxy with analytic tangent vectors, yielding a true view-space normal for every pixel. Added diffuse key light, Fresnel rim, and Blinn-Phong specular with roughness driven by *Surface Tension*.
- **Enhanced thin-film iridescence**  
  Chromatic optical path now varies with viewing angle (glancing angles shift hue), film thickness, audio mids, and Bonnet rotation. Per-channel phase offsets preserve the rainbow soap-film character.
- **HDR bloom + ACES tone mapping**  
  Values intentionally exceed 1.0; a bloom threshold adds glowing caustic highlights before ACES brings the result into display gamut.
- **Subsurface scattering glow**  
  Back-light term warms the translucent film from behind, reacting to bass hits.

### Atmospheric & color upgrades
- **Volumetric fog**  
  Depth-aware fog tinted by mids, controlled by *Surface Tension*.
- **Dynamic color grading**  
  Time-varying color temperature plus split-tone shadows (cool cyan) and highlights (warm gold).
- **Film grain & chromatic aberration**  
  Subtle fbm grain and radial CA tied to bass/depth for a cinematic finish.
- **Branchless mouse dimple**  
  Mouse depression is now applied with `select()` instead of an `if` block.

### Preserved soul
- Catenoid ↔ helicoid Bonnet rotation remains the geometric heartbeat.
- Audio-reactive bubble distortion (treble) and curvature caustics stay intact.
- Temporal surface memory still trails previous frames.
- Original `id`, `name`, `category`, and `url` are unchanged.

## Techniques Used

| Toolkit area | Technique |
|--------------|-----------|
| HDR workflow | HDR bloom threshold, exposure scaling, ACES tone mapping |
| Color grading | Dynamic temperature, split-tone shadows/highlights |
| Lighting | Fresnel rim, roughness-aware specular, soft diffuse key light |
| Atmosphere | Depth-aware volumetric fog, atmospheric scattering tint |
| Special FX | View-dependent thin-film interference, subsurface scattering glow, chromatic aberration |

## Performance Estimate

- **Workgroup:** `16x16x1` (canonical)
- **Per-pixel cost:** ~3 surface evaluations (position + two analytic tangents), a handful of trig calls, one `textureLoad`, three `textureStore`s, and cheap 3-octave fbm for grain.
- **Expected:** 60 fps at 1080p on mid-tier discrete GPUs; 1440p/4K should remain smooth on modern hardware. No heavy per-pixel loops.

## Dependencies

- Canonical 13-binding generative header from `agents/WGSL_BUILTINS_GENERATIVE.md` §0.
- Compute-safe functions only: `textureSampleLevel`, `textureLoad`, `textureStore`; no `tan`, `textureSample`, `dpdx`, or `dpdy`.
