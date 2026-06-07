# gen-coral-reef-colony v2 Upgrade Notes

## Agent Perspectives Synthesized
- **Algorithmist**: Space colonization via fbm-driven branch angles and DLA pattern accumulation. Polyp detail from fBm with 5 octaves. Spawning events triggered by treble threshold step function.
- **Visualist**: Bioluminescent palette (fluorescent proteins: green/cyan/pink), subsurface scattering approximation via coralDensity smoothing, HDR bloom on polyps scaled by bass, caustic light patterns from overlapping sine waves, ACES tone mapping.
- **Interactivist**: Bass drives nutrient availability (0.6-1.4x growth multiplier), mids control current direction vector, treble triggers spawning pulse (green/cyan flash), mouse attracts coral via proximity falloff, depth attenuates water tint and light.
- **Optimizer**: Single-pass DLA via hash-seeded fBm, smoothstep instead of branching for all thresholds, precomputed depth attenuation.

## Alpha Semantics
`alpha = coralDensity * bioluminescence * depthAttenuation` — brightest and most opaque where polyps glow near the foreground.

## Parameter Mapping
- zoom_params.x: growth (nutrient base)
- zoom_params.y: polypSize
- zoom_params.z: colorVariety
- zoom_params.w: mouseAttraction

## Naga Validation
Run: `naga public/shaders/gen-coral-reef-colony.wgsl`
