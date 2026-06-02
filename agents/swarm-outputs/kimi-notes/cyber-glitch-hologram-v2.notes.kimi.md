# cyber-glitch-hologram v2 Upgrade Notes

## Overview
Upgraded from 81 lines to 137 lines. Added block-based datamoshing with structure tensor motion vector estimation, holographic cosine interference fringes, cyan/magenta color separation, chromatic aberration on glitch blocks, scanline banding, and ACES tone mapping.

## Algorithmist Changes
- Added `structure_tensor(uv, res)` function computing local image gradients via central differences on luminance
- Block-based datamoshing: `floor(uv * blockScale) / blockScale` with hash-driven block swap triggers
- Motion vectors from structure tensor displace sampling UV: `motion * glitchAmount * 0.04`
- Holographic interference fringes via `cos((uv.x + uv.y * 0.7) * fringeFreq + time * 4.0)`
- Dual-layer parallax sampling using depth to mix between offset layers

## Visualist Changes
- Cyan/magenta holographic color separation: `vec3(0.0, 0.85, 1.0)` and `vec3(1.0, 0.0, 0.75)`
- Chromatic aberration on glitch blocks with per-layer RGB separation
- Scanline banding: `step(0.35, scanline) * 0.12 * mouseInfluence`
- ACES tone mapping applied to final HDR color
- Dead zones tinted with noise-driven cyan-grey corruption

## Interactivist Changes
- Bass triggers glitch block swaps: threshold `0.88 - bass * 0.22`
- Mouse creates holographic "dead zones" with noise corruption inside `smoothstep(0.12, 0.0, mouseDist)`
- Depth adds parallax between glitch layers: `depth * 0.025 * vec2(sin(...), cos(...))`

## Alpha Strategy
- `alpha = clamp(confidence * (1.0 - glitchCorruption) * 0.85 + banding * 0.3 + bass * 0.04, 0.06, 0.92)`
- `confidence = mouseInfluence * (1.0 - deadZone * 0.6)`
- `glitchCorruption = swapTrigger * glitchAmount * 0.45 + deadZone * 0.25`
- Alpha = hologram confidence × (1.0 - glitch_corruption)
- Never uses `vec4(..., 1.0)`

## Parameter Changes
- Replaced `mouseRadius` with `blockScale` (Block Scale) to expose datamoshing block size control

## Validation
- naga: PASS
- workgroup_size: (16, 16, 1)
