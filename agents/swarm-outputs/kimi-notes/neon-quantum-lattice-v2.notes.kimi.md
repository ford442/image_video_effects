# neon-quantum-lattice v2 Upgrade Notes

## Agent Perspectives
- **Algorithmist**: Replaced simple grid with quasi-crystal Penrose-like aperiodic tiling using 5-fold symmetry axes and `min` distance to multiple plane families. Three independent tile layers with golden-ratio scaling (`1.0`, `1.618`, `2.618`).
- **Visualist**: Neon edge glow on tile boundaries with audio-modulated width. Metallic fill gradients using warm/cool tile color function. HDR bloom at vertices where layers intersect. ACES tone mapping. Third deep layer adds violet depth.
- **Interactivist**: Bass triggers tile inflation (`inflation = base * (1.0 + bass * 0.5)`). Mouse creates quantum uncertainty zones with pseudo-random noise. Depth drives parallax between three tile layers.
- **Optimizer**: Single-pass compute. Reused `penrose_dist` helper. Early out-of-bounds return. All texture samples are from `readDepthTexture` only (no color texture dependency for generative geometric output).

## Alpha Strategy
`alpha = edgeConfidence * (0.7 + depth * 0.3) + vertexGlow * 0.1 + uncertainty * 0.1`
Tile edge confidence modulated by depth gives layered transparency.

## Lines
122 lines (was 81)

## Files Written
- `public/shaders/neon-quantum-lattice.wgsl`
- `shader_definitions/geometric/neon-quantum-lattice.json` (new)
