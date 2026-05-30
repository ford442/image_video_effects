# predator-camouflage v2 Upgrade Notes

## Agent Perspectives Synthesized
- **Algorithmist**: Chromatophore simulation via dual-layer noise (expanding/contracting pigment sacs). sacScale derived from smoothstep noise. Predator thermal vision uses luminance-to-heat mapping with custom thermal palette (blue -> green -> red/yellow).
- **Visualist**: IR false-color thermal overlay, chromatophore tint transitions, HDR bloom on heat signatures and sac edges, ACES tone mapping, chromatic RGB channel separation scaled by rim and audio treble.
- **Interactivist**: Bass drives chromatophore oscillation speed and pigment intensity, mouse acts as prey heat source (thermal center), depth controls thermal haze refraction strength.
- **Optimizer**: Single-pass with 3 texture samples for chromatic separation, branchless thermal mapping via smoothstep, precomputed depth-based haze.

## Alpha Semantics
`alpha = cloakMask * thermalContrast * (0.4 + depth * 0.6)` — strongest where camouflage is active, thermal contrast is high, and foreground depth is near.

## Parameter Mapping
- zoom_params.x: cloakRadius
- zoom_params.y: refractionStrength
- zoom_params.z: chromatophoreSpeed
- zoom_params.w: noiseScale

## Naga Validation
Run: `naga public/shaders/predator-camouflage.wgsl`
