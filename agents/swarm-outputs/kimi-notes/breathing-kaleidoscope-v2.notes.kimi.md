# breathing-kaleidoscope v2 Upgrade Notes

## Agent Synthesis
- **Algorithmist**: Added organic "breathing" via 4-octave FBM domain warp modulating kaleidoscope symmetry count (float → fractional sectors). Temporal phase accumulates with bass offset (`phase = time*cycleSpeed*6.28318 + bass*3.0`).
- **Visualist**: Saturated jewel-tone palette cycling via cosine hue triple. Soft glow at symmetry axes with exponential radial falloff. ACES tone mapping. Film grain overlay (`filmGrain`) modulated by inverse depth.
- **Interactivist**: Bass expands/contracts breathing amplitude. Mouse controls symmetry center. Treble adds sparkle at symmetry boundaries (`smoothstep(0.06, 0.0, edgeDist) * treble * 0.35`). Depth fades distant sectors (`depthFade = mix(1.0, 0.5, depth*dist*1.5)`).
- **Optimizer**: `@workgroup_size(16,16,1)`. Reused `noise2`/`hash2` across FBM. Early exit on bounds.

## Alpha Semantic
`alpha = clamp(lum * 0.4 + breathAmp * 0.25 + depth * 0.2 + sparkle * 0.15, 0.1, 0.92)`
- Sector luminance × breathing amplitude × depth. Semantic, never 1.0.

## Lines
~146 WGSL lines

## Changes
- New helpers: `acesToneMap`, `hash2`, `noise2`, `fbm2`, `filmGrain`
- Fractional symmetry count via FBM warp
- Jewel palette + axis glow + sparkle layers
- Film grain post-process
- JSON description updated; tags expanded
