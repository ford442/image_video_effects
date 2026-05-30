# spirograph-reveal v2 — Upgrade Notes

## Agent Synthesis
- **Algorithmist**: True epicycloid/hypocycloid math: `spiro = sin(theta) + l * sin((1-k)*theta/k)`. Multiple gears (3 layers) with varying `gearRatio = (outerTeeth + g) / (innerTeeth + g * 0.5)`. Gear-ratio modulated patterns replace simple circles.
- **Visualist**: Metallic ink aesthetic (`inkColor` base + `specColor` cusp highlights). Gradient fills along curve length (`gradientFill` mixed by density). HDR bloom at cusps (`cuspSharp` via `pow(1.0 - smoothstep(...), 3.0)`).
- **Interactivist**: Bass drives rotation speed (`gearSpeed = speed * (1.0 + g * 0.3) * (1.0 + bass * 0.4)`). Mouse modulates gear ratio via `l = 0.5 + mouse.x * 0.5`. Depth creates 3D spirograph layers (`depthLayers = 1.0 + depth * 2.0`).
- **Optimizer**: 3-gear loop unrolls well. Single texture sample for input image. Reuses `atan2`/`length` for all gears. Depth sample amortized.

## Alpha Semantic
`alpha = clamp(totalDensity * depthOcclusion * fade + totalBloom * 0.3, 0.0, 1.0)`
- `totalDensity`: accumulated spirograph curve coverage
- `depthOcclusion`: `1.0 - depth * 0.5` (farther = more transparent)
- `fade`: radial distance falloff

## Lines
131 lines (upgraded from ~75)

## Bindings
Canonical 13-binding header, exact `Uniforms` struct, `@workgroup_size(16, 16, 1)`.

## Chunks Used
- `hash12` (unused but reserved for future grain)

## Params
1. Outer Teeth (`zoom_params.x`) — outer gear tooth count
2. Inner Teeth (`zoom_params.y`) — inner gear tooth count
3. Rotation Speed (`zoom_params.z`) — base animation speed
4. Line Thickness (`zoom_params.w`) — spirograph line width
