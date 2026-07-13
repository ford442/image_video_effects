# gen-aurora-silk — Visualist Upgrade

**Agent:** Visualist  
**Domain:** HDR color science, cinematic lighting, atmospheric effects, emotional visual impact  
**Date:** 2026-06-29

## Changelog

### What Changed

- **HDR color workflow:** Aurora ribbons now compute in high-dynamic-range space, with a bloom-threshold pass that lets bright crests exceed 1.0 before ACES filmic compression.
- **ACES tone mapping:** Preserved and applied as the final color transform for cinematic, contrast-preserving highlights.
- **Dynamic temperature grading:** Color temperature oscillates vertically over time and is nudged by mid-range audio, shifting between cool polar blues and warm sunset golds.
- **Split-tone shadows/highlights:** Shadows receive a cool blue lift; highlights receive a warm amber lift, adding photographic depth.
- **Fresnel rim lighting:** Curtain edges glow with an icy rim that intensifies with mids and treble, emphasizing the silk-like folds.
- **Volumetric god rays:** Soft rays descend from the top of the frame, thickened by the Atmosphere parameter and shimmering with treble.
- **Caustic / dappled light:** A cheap three-sine caustic pattern adds sparkle across the ribbons.
- **Volumetric fog / haze:** A low-frequency fBM fog layer blends the aurora into a depth-aware atmospheric background.
- **Depth layering:** Output depth and color are modulated by the input depth buffer for parallax-style compositing.
- **Chromatric aberration:** A subtle compute-safe radial shift (no texture read) adds a final analog edge.
- **Domain warping:** The wind field is domain-warped for more organic, less grid-like curtain motion.

### What Stayed the Same

- Silky aurora-curtain soul: centered ribbons, audio-reactive breathing, mouse parallax, and slow temporal persistence.
- Canonical 13-binding generative header.
- `@compute @workgroup_size(16, 16, 1)`.
- Original `id`, `name`, `category`, and `url`.

## Parameter Mapping

| Param | Name | Effect |
|-------|------|--------|
| p1 | Band Density | Density of aurora ribbons (2–14 bands) |
| p2 | Flow Speed | Horizontal drift and shimmer speed |
| p3 | Atmosphere | Fog density, god-ray intensity, and ribbon width |
| p4 | Bloom | HDR glow amount, bloom threshold, and temporal decay |

## Performance Estimate

- **1080p mid-tier GPU:** ~60 fps expected.
- **Per-pixel cost:** ~14 octaves of value noise (domain warp 3+3, main fBM 5, fog 3), plus cheap sin-based god rays and caustics. No per-pixel heavy loops.
- **Workgroup:** 16×16×1.
- **Storage writes:** one each to `writeTexture`, `writeDepthTexture`, and `dataTextureA` per thread.

## Dependencies

- Uses the canonical 13-binding generative layout from `agents/WGSL_BUILTINS_GENERATIVE.md` §0.
- Built-ins used: `textureLoad`, `textureStore`, `textureSampleLevel` (bound but not used in this generative pass), `mix`, `smoothstep`, `clamp`, `saturate`, `sin`, `cos`, `exp`, `pow`, `normalize`, `dot`, `length`, `floor`, `fract`.
- No `tan`, `textureSample`, `dpdx`, `dpdy`, or fragment-only constructs.
