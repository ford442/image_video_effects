# gen-langton-ant — Kimi Notes

## Changes
- Three real Langton's Ants simulated on a 128×128 toroidal grid using `dataTextureC` for persistent state.
- Ant state (x, y, dir) encoded into pixel (0,0), (cellSize,0), (2×cellSize,0) of `writeTexture`.
- Each frame, every thread checks if its cell was the ant’s previous position; if so, it flips cell state and boosts heat.
- Thread at ant pixel additionally computes next ant position via true Langton rules (turn based on cell color, then move).
- Heat-map palette: blue → cyan → yellow → red → white based on accumulated flip heat.
- Temporal decay via `prev.g` blend; bass increases flip boost intensity.
- Mouse click repositions ant 1 to the cell under the cursor.
- Depth scales the viewport UV for zoom in/out without changing grid resolution.
- Chromatic aberration scales with highway edge proximity (heat gradient approximation).
- ACES tone mapping on final composite.

## Wow-Factor
- True Langton's Ant rules produce the famous chaotic-then-highway emergence.
- Three ants create intersecting highways with beautiful heat-map overlap.
- Persistent heat accumulation makes the grid feel like a living history.

## Risks
- Ant state stored in visible pixels (0,0), (16,0), (32,0) — three cells show corrupted color instead of grid color.
- Corruption is visually negligible (3 cells of 16,384) but noticeable if user zooms to corner.
- 3 ants × 3 `textureLoad` calls each for position checking = 9 extra loads per pixel.
- Highway emergence takes ~10,000 steps per ant (~55 seconds at 60 fps with 3 ants).
- Could frustrate users expecting immediate highways; consider adding emergent hint lines or faster initial seeding.
