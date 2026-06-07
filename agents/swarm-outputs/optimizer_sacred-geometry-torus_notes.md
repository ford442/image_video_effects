# Optimizer Notes: sacred-geometry-torus

## Key Changes
1. **Branchless phi-layers**: Replaced the divergent `for (i < u32(phiLayers))` loop with a fixed 7-iteration loop masked by `sat(phiLayers - fi)`. Eliminates per-pixel warp divergence while preserving the soft layer fade.
2. **Fast math approximations**: Added `fast_atan2` (max error ~0.0015 rad) and `fast_exp` with clamping to reduce ALU pressure.
3. **Early exit for sky pixels**: Pixels with `r > 0.95` write background and return immediately, reducing wasted work on empty background.
4. **Named constants**: PHI, TAU, INV_PHI, MAX_PHI_LAYERS, KNOT_TAPS replace magic numbers.
5. **Premultiplied alpha writeback**: Output is now `vec4(rgb * alpha, alpha)` for correct slot-chain compositing.
6. **Helper extraction**: `nodeGlow()` encapsulates the Gaussian falloff math.

## Pipeline Integration
- Alpha channel carries bloom/presence weight for downstream tone-map.
- dataTextureA packs (pattern, ring, phiLayers*0.1, alpha) for state chaining.
- writeDepthTexture stores depth for depth-aware passes.

## Lines
~155 lines (target ~170 ±20%).
