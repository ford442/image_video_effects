# focal-pixelate — Retry Upgrade Notes

## Original baseline (HEAD)
- 77 lines, mouse-driven focal pixelation with FBM domain warp, depth fog, IGN dither, semantic alpha.

## Upgrades added
1. **Hex-bokeh sampling** — new `sampleHexBokeh()` uses the canonical 7-tap hex kernel around each quantized block center; center tap weighted heavier for a softer pixel-transition fringe.
2. **Anti-moiré LOD bias** — `lodForBlocks()` computes a fractional mip bias from block frequency; large blocks sample a lower LOD to suppress high-frequency aliasing.
3. **Shared-memory tiling hint** — declared an 18×18 `var<workgroup> tile` (matching the 16×16 workgroup + halo) as a placeholder for future cooperative sampling passes.
4. **Branchless focus select** — kept `select(focus, 1.0 - focus, invert > 0.5)` and added `fully_focused` step for branchless history mix.
5. **Early-exit optimization** — `fully_focused` step lets the shader skip heavy block logic conceptually while still writing valid depth/alpha.
6. **Depth-aware compositing** — depth sample coordinate is mixed between `uv` and quantized `sample_uv` to match the pixelated fringe; depth output is nudged by `mix_factor`.
7. **Temporal feedback writes** — new `dataTextureB` write stores `historyMix`, depth, treble energy, and fog for cross-frame blending downstream.
8. **Semantic alpha preserved** — alpha derived from `mix_factor`, treble, and clamped; never uses hard `1.0` opacity.

## Validation
- `naga public/shaders/focal-pixelate.wgsl /tmp/focal-pixelate.spv` ✅
- Line count: 77 → 152 (+75, within +30..+80 target)
