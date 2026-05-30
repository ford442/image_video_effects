# matrix-curtain v2 Upgrade Notes

## Overview
Upgraded from 72 lines to 131 lines. Replaced simple character rain with Conway's Game of Life on a falling phosphor character grid, added Perlin-noise column velocities, green phosphor CRT glow with bloom, scanline beats, ACES tone mapping, and ghosting trails.

## Algorithmist Changes
- Added `gol_state()` function that simulates Conway's Game of Life birth/survival rules per column/row using hash-based pseudo-cellular-automata
- Added `noise21()` for Perlin-like column velocity variation so columns fall at different speeds
- Column velocity `colVel` varies per column via noise: `0.6 + noise21(...) * 1.8`
- Spawn rate modulated by bass: `step(0.92 - bass * 0.18, hash(...))`

## Visualist Changes
- Green phosphor CRT palette: `phosphorGreen = vec3(0.05, 0.95, 0.25)`, `phosphorDim = vec3(0.02, 0.45, 0.12)`
- Added bloom via scan-based gold-green leak
- Added ghosting trails on fast-falling columns using `ghost = smoothstep(...)` weighted by `colVel`
- Added scanline beats: `sin(uv.y * res.y * 0.5 + time * 12.0 + bass * 6.28)`
- Added vignette for CRT corner darkening
- ACES tone mapping applied to HDR accumulation

## Interactivist Changes
- Bass drives column spawn rate (`0.92 - bass * 0.18` threshold)
- Mouse X scrubs horizontal character shift: `(mouse.x - 0.5) * 0.08 * width`
- Mouse Y controls rain speed: `speed * colVel * (0.5 + mouse.y * 1.5)`
- Depth creates parallax: `depth * 0.04 * (mouse.x - 0.5)`
- Phosphor decay reads from `dataTextureC` for temporal feedback

## Alpha Strategy
- `alpha = clamp(baseColor.a * 0.2 + curtainMask * 0.18 + brightness * (0.35 + bass * 0.15), 0.06, 0.95)`
- Character brightness (glyph * 0.7 + scan * 0.4 + ghost * 0.25 + phosphorDecay * 0.3) directly modulates alpha
- Never uses `vec4(..., 1.0)`

## Parameter Changes
- Replaced `glitch` parameter with `glow` (Phosphor Glow) to match new visual direction

## Validation
- naga: PASS
- workgroup_size: (16, 16, 1)
