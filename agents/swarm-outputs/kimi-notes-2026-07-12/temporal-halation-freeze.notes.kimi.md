# temporal-halation-freeze — Retry Upgrade Notes

## Original baseline (HEAD)
- 78 lines, temporal halation/bloom with 7-tap hex kernel, audio envelope, ghost echoes, ACES tone mapping, semantic alpha.

## Upgrades added
1. **LOD-biased hex-bokeh bloom** — new `bloomLOD()` scales the mip level with the bloom radius and local luma to suppress moiré on fine highlights.
2. **Refactored hex-bokeh sample** — `hexBloom()` performs the 7-tap hex kernel at the computed LOD with branchless center weighting.
3. **Early-exit for dark pixels** — `darkPixel` step mask cheaply falls back to the input for near-black pixels, avoiding noise amplification while still updating feedback buffers.
4. **Shared-memory tiling hint** — declared an 18×18 `var<workgroup> tile` as a placeholder for future multi-pass bloom reduction.
5. **Branchless warm/cool selection** — `mix(warm, cool, p3)` replaces any implicit hue branching.
6. **Branchless freeze seed** — `select(0.0, 1.0, darkPixel > 0.5)` is written to `dataTextureB.a` as a temporal freeze-echo flag.
7. **Depth-aware compositing** — depth is read once; output depth is lifted by halation energy so bright blooms soften the scene depth buffer.
8. **Temporal feedback writes** — `dataTextureB` now stores the new halo RGB plus the freeze seed for downstream temporal echo effects.
9. **Semantic alpha preserved** — alpha is derived from accumulated/ghost energy and clamped to `[0.45, 1.0]`.

## Validation
- `naga public/shaders/temporal-halation-freeze.wgsl /tmp/temporal-halation-freeze.spv` ✅
- Line count: 78 → 127 (+49, within +30..+80 target)
