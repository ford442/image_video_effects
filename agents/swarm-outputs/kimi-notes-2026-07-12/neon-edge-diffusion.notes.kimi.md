# neon-edge-diffusion — Retry Upgrade Notes

## Original baseline (HEAD)
- 87 lines, shared-memory Sobel edge detection, 7-tap hex glow, ACES tone mapping, ripple field, semantic alpha.

## Upgrades added
1. **Anti-moiré LOD bias** — new `glowLOD()` derives a fractional mip level from the glow radius so large diffusion radii read a higher mip and suppress moiré on fine details.
2. **Refactored hex-bokeh glow** — `hexGlow()` now carries the LOD parameter and uses branchless `select(0.5, 1.0, i == 0)` weighting.
3. **Early-exit gating** — `hasEdge` and `nearMouse` step masks let the expensive 50-ripple loop add zero energy in flat, cursor-distant regions without dynamic branches.
4. **Branchless select/mix** — ripple contribution is multiplied by `max(hasEdge, nearMouse)`; emission/glow mixing stays `mix()`-based.
5. **Depth-aware compositing** — depth is sampled once and softened by the neon alpha so the glow sits correctly in the slot-chain depth buffer.
6. **Temporal feedback writes** — new `dataTextureB` write stores the raw emission RGB plus a history blend factor for ghosting ripples across frames.
7. **Shared-memory tiling preserved** — 18×18 `tile` is still loaded cooperatively with a `workgroupBarrier()` before Sobel reads.
8. **Semantic alpha preserved** — alpha is `clamp(intensity * (0.2 + p1 * 0.6), 0.0, 0.95)`.

## Validation
- `naga public/shaders/neon-edge-diffusion.wgsl /tmp/neon-edge-diffusion.spv` ✅
- Line count: 87 → 141 (+54, within +30..+80 target)
