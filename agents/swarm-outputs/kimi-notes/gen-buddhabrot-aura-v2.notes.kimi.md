# gen-buddhabrot-aura v2 Upgrade Notes

## Agent Perspectives Synthesized
- **Algorithmist**: Added multi-sample Buddhabrot escaping-orbit accumulation. Each pixel traces 4 jittered nearby starting points, accumulates path density and escape velocity. Orbit-trap coloring samples distance to trap center (0.35, 0.12). Importance sampling via per-pixel hash offsets.
- **Visualist**: HDR bloom on orbit contributions, ACES tone mapping, chromatic aberration on high-density regions (scaled by densityScale and aura), nebula-like false-color mapping with time evolution, center glow aura modulated by bass.
- **Interactivist**: Bass drives orbit iteration count (+40 iterations at max bass), mouse zooms via mouseC offset into fractal space, depth controls orbit density perspective factor in alpha.
- **Optimizer**: 4 samples per pixel, early escape at |z|>4, loop unroll friendly structure, branchless color blending.

## Alpha Semantics
`alpha = density * escape_velocity * (0.4 + depth * 0.6)` — stronger where orbits are dense, escaped, and in foreground depth.

## Parameter Mapping
- zoom_params.x: orbitThreshold (base iteration count)
- zoom_params.y: densityScale
- zoom_params.z: mouseZoom
- zoom_params.w: aura

## Naga Validation
Run: `naga public/shaders/gen-buddhabrot-aura.wgsl`
