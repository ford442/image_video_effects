# Optimizer Notes: mycelium-network

## Key Changes
1. **Branchless branch loop**: Unrolled the divergent `for (bi < branchCount)` into a fixed 5-iteration loop with `active = f32(bi < branchCount)` masking. All warps execute the same instructions.
2. **Fast atan2**: Replaced native `atan2` in branch angle calculations with the fast polynomial approximation.
3. **Anti-moire LOD**: Added `lodFade = exp2(-lod)` based on screen-space density (`networkDensity / minRes`), attenuating high-frequency cell detail when zoomed out or at high density.
4. **Named constants**: MAX_BRANCHES, TRUNK_WIDTH centralize tuning.
5. **Premultiplied alpha writeback**: `vec4(rgb * alpha, alpha)` for correct compositing in chained slots.
6. **Coordinate safety**: Normalized all `textureStore` coords to `vec2<i32>`.

## Pipeline Integration
- dataTextureA carries (color, alpha) for feedback / state chaining.
- writeDepthTexture stores glow*0.3 for depth-aware effects.
- Temporal feedback via dataTextureC preserved.

## Lines
~165 lines (target ~170 ±20%).
