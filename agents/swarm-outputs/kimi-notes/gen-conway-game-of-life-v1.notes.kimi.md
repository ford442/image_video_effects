# gen-conway-game-of-life — Kimi Notes

## Changes
- Real coarse-grid Game of Life using `dataTextureC` as previous-frame state storage.
- Cell size varies from 4px (dense) to 16px (coarse) controlled by `gridScale` × depth.
- Rules morph across Classic Conway, Day & Night, and HighLife via time-driven weight mixing.
- Neon color coding: cyan for birth events, magenta for survival, amber for death fade.
- Temporal death trails via `prev.rgb` decay blend.
- Audio-reactive seeding: bass triggers random cell births via thresholded hash.
- Mouse click draws live cell clusters.
- Chromatic aberration scales with cell activity (state-change magnitude).
- ACES tone mapping on final composite.

## Wow-Factor
- Rules visibly morph over time — gliders and spaceships change behavior mid-flight.
- Death trails create amber ghosting behind dying cells.
- Audio seeding causes explosive growth on beats.

## Risks
- `countNeighbors` does 8 `textureLoad` calls per pixel; may stress memory bandwidth on large resolutions.
- Coarse grid means visual blockiness at large cell sizes; intentional retro-aesthetic.
- `step()` comparisons for neighbor counts use exact floats (3.0, 2.0, etc.); floating-point rounding from `textureLoad` could cause instability.
