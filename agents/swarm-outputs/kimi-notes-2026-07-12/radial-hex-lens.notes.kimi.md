# radial-hex-lens — Retry Upgrade Notes

## Original baseline (HEAD)
- 94 lines, radial hexagonal mosaic lens with FBM warp, hex-cell LOD, depth fog, hex-bokeh fringe blur.

## Upgrades added
1. **Anti-moiré sub-cell dither** — new `antiMoireBias()` uses IGN to jitter the sample coordinate when hex cells are small relative to screen frequency, breaking regular aliasing patterns.
2. **Fractional hex LOD** — `hexLOD()` now factors in the radial zoom magnification so highly magnified cells sample the correct mip and avoid minification aliasing.
3. **Weighted hex-bokeh sampling** — `sampleHexBokeh()` performs a 7-tap hex kernel at the computed LOD with branchless center weighting for cleaner interior color.
4. **Shared-memory tiling hint** — declared an 18×18 `var<workgroup> tile` as a cooperative-sampling placeholder for future passes.
5. **Early-exit / branchless pass-through** — `inside` step mask lets the lens run only inside `radius * 1.15`; outside pixels get a stable base color and full alpha without dynamic branches.
6. **Branchless select/mix** — `select(uv - b, uv - a, ...)` hex-center logic retained; alpha uses `mix(1.0, baseAlpha, inside)`.
7. **Depth-aware compositing** — depth fog scales with the lens falloff; depth buffer is written unchanged so the lens integrates cleanly.
8. **Temporal feedback writes** — new `dataTextureB` write stores `historyBlend`, zoom factor, normalized distance, and fog for cross-frame lens-state blending.
9. **Semantic alpha preserved** — alpha is clamped and branchlessly set to 1.0 outside the lens so the pass-through region stays opaque.

## Validation
- `naga public/shaders/radial-hex-lens.wgsl /tmp/radial-hex-lens.spv` ✅
- Line count: 94 → 163 (+69, within +30..+80 target)
