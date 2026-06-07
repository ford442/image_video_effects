# Optimizer Notes: gen-quasicrystal

## Performance Wins
1. **Branchless `metallicColor`** — Replaced 3-way `if/else` ladder with `step` + `mix` chain. Same visual result, no warp divergence.
2. **Anti-moiré frequency clamping** — At high `patternDensity` (>8), wave frequency is smoothly reduced from 10.0 to 6.0. Kills shimmer when zoomed out without `fwidth` (unavailable in compute).
3. **Removed unused `rhombusPattern`** — Dead code elimination saved ~15 lines and one redundant `quasicrystal` call.

## Pipeline Integration
- `dataTextureA` stores full premultiplied RGBA for slot chaining.
- `dataTextureB` stores raw color + isolated bloom mask (`vec4(col, bloom)`) for post-process targeting.
- Alpha encodes luma-based bloom weight + coverage.
- HDR-ready: metallic highlights can exceed 1.0 when audio reactivity (`bass`) is high.

## Code Elegance
- Named constants (`PI`, `TAU`).
- Eliminated magic `6.28318` → `TAU`.
- Compact gem palette array.
- Single shared `invN` in quasicrystal loop.

## Issues / Tradeoffs
- No true `fwidth`-based LOD anti-moiré because compute shaders lack derivative builtins. The density-driven frequency clamp is a practical approximation.
- `quasicrystal` loop count depends on `symmetry` uniform, but since it's uniform across all pixels, loop divergence is not an issue.
