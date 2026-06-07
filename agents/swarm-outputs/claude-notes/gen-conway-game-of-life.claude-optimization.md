# gen-conway-game-of-life — Claude Optimization (2026-06-07)

## Bottlenecks Identified
- **Critical bug**: `dataTextureA` never written — CA state had no persistent storage in the correct ping-pong slot. The shader stored `newState` in `writeDepthTexture` instead, meaning the depth buffer was carrying CA state across frames and the simulation was fragile/undefined behavior dependent on renderer internals.
- No generation counter — all living cells looked identical regardless of age
- `prev.rgb` used for fade color but `prev` was read from `dataTextureC` which (with the bug) never received color data
- No huePreserveClamp, no IGN dither, missing `aces-tone-map` in features

## Optimizations Applied
- **Bug fix**: Added `textureStore(dataTextureA, pixel, vec4<f32>(newState, generation, activity, alpha))` — state now correctly stored in ping-pong slot `.r=alive, .g=generation, .b=activity`
- Added generation counter: reads `prev.g` (previous generation from dataTextureC.g), increments when alive, resets to 0 on death, normalised to [0,1] in 1/255 steps
- Age tint: older surviving cells shift toward warm amber — birth events remain cyan-green, deaths orange, long survivors slowly amber. Tint applied only to `survival` channel to avoid desaturating transient events
- Fixed `writeDepthTexture` to write actual visual depth `mix(0.3, 1.0, newState * (0.5 + generation * 0.5))` — older cells appear deeper
- Added `huePreserveClamp` + IGN dither after ACES
- Updated features and `Upgraded:` date

## Visual / Transcendence Notes
- Generation counter makes colony structure readable at a glance: newborn cyan → adolescent magenta → elder amber creates a visual archaeology of the automaton's history
- The bug fix means the CA will now actually evolve correctly across frames instead of potentially reading stale/random state

## Remaining Risks
- `countNeighbors` does 8 `textureLoad` calls per thread — at 4K with small cellSize (4px) this is 4M threads × 8 loads = 32M texture ops per frame; CPU-side could throttle cellSize minimum
- Generation counter normalises in 1/255 increments — cells surviving >255 frames saturate to `generation=1.0` (full amber); this is aesthetic not a bug

## JSON Changes
- Added `aces-tone-map`, `generation-counter`, `hue-preserve-clamp`, `ign-dither` to features array
