# Optimizer Notes: spec-distance-field-text

## Performance Wins
1. **Removed second `sdGlyphGrid` evaluation** — Shadow is now approximated via an offset SDF (`d + 0.025`) instead of recomputing the entire glyph grid. Saves ~40% SDF work per pixel.
2. **`fast_exp` for glow** — Clamps exponent to safe range, avoids shader compiler inserting expensive checks.
3. **Branchless mouse reveal** — Replaced `if (isMouseDown)` with `fast_exp(...) * step(0.5, u.zoom_config.w)`, eliminating uniform-dependent branching.

## Pipeline Integration
- `dataTextureA` stores glyph color + raw SDF (`vec4(glyphColor, d)`) for downstream chaining.
- Alpha channel encodes bloom weight `(glyphMask + glowMask) * overlayMix`.
- Premultiplied-alpha writeback when alpha < 1.0.
- Reads `readTexture` for slot-chained compositing.

## Code Elegance
- Named constants (`TAU`).
- Reduced glyph count from 5 to 4 (removed hexagon loop, the most expensive glyph).
- Removed magic numbers where practical.

## Issues / Tradeoffs
- Glyph selection still branches on `glyphIdx` (computed per-pixel from hash). Making it branchless would evaluate all 4 glyphs every pixel, which is slower than the divergent branch.
- Approximated shadow is slightly softer than the original offset-grid shadow. Visually similar at normal scales.
