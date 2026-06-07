# origami-fold v2 Upgrade Notes

## Agent Perspectives Synthesized
- **Algorithmist**: Mountain/valley crease parity from MouseClickCount (config.y). Kawasaki-Justin theorem approximated via alternating angle sums around the fold vertex. Dihedral angle constraints via smoothstep on fold distance. Reflection geometry for flap UV computation.
- **Visualist**: Paper fiber texture from high-frequency sine + hash grain, shadow casting via fold-distance smoothstep, HDR specular highlights on creases (power 12.0), ACES tone mapping, chromatic edge darkening modulated by treble.
- **Interactivist**: Bass drives fold animation speed and crease glow intensity, mouse performs folds (mountain vs valley by click parity, isMouseDown boosts crease glow), depth controls paper layer ordering and shadow intensity.
- **Optimizer**: Branchless where possible, single reflection sample per pixel, precomputed paper texture scalar, depthShadow pre-mix.

## Alpha Semantics
`alpha = abs(dihedral) * paperOpacity * (0.5 + depth * 0.5)` — stronger where fold angle is large, paper is opaque, and foreground depth is high.

## Parameter Mapping
- zoom_params.x: foldSpeed
- zoom_params.y: shadowStrength
- zoom_params.z: angle (base fold angle)
- zoom_params.w: paperOpacity

## Naga Validation
Run: `naga public/shaders/origami-fold.wgsl`
