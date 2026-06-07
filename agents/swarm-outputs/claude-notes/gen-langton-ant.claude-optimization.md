# gen-langton-ant — Claude Optimization (2026-06-07)

## Bottlenecks Identified
- **Critical bug** (same family as Conway): `dataTextureA` never written. The shader instead encoded ant position/direction as `vec4<f32>(x/128, y/128, dir/4, 1.0)` directly into `writeTexture` — the **visible output texture** — at 3 tracker pixels `(a*cellSize, 0)`, then read it back from `dataTextureC` next frame.
- This produced two compounding bugs:
  1. Three pixels in the top-left region displayed raw encoded float values (a visible magenta/dark speck artifact) instead of rendered heat-map color
  2. Reading ant state from `dataTextureC` only works if the renderer copies `writeTexture` → `dataTextureC`, which contradicts the standard ping-pong (`dataTextureA` → `dataTextureC`) used by every other multi-pass shader in the library — meaning ant tracking was likely reading stale/incorrect state

## Optimizations Applied
- Restructured the per-ant loop to compute `antEncoded` and an `isAntPixel` flag instead of an early `textureStore + return`
- Final `textureStore(dataTextureA, pixel, select(cellStateOut, antEncoded, isAntPixel))` — packs cell flip-state(.r)/heat(.g)/ant-presence(.b) everywhere, with ant position/direction encoding overriding only at the 3 tracker pixels
- The 3 tracker pixels now also render a proper heat-map color to `writeTexture` (no more raw-float visual glitch)
- Added `Upgraded:` date

## Visual / Transcendence Notes
- The ant trail heat-map should now correctly persist and evolve frame-to-frame via the proper `dataTextureA → dataTextureC` ping-pong
- Removing the visible-texture corruption means the top-left corner of the canvas no longer shows 3 anomalous pixels

## Remaining Risks
- This is a behavioral fix — if the renderer was *actually* copying `writeTexture` → `dataTextureC` for this shader specifically (non-standard), the ant simulation's frame-to-frame continuity changes. Watch for "ant resets to seed position" regressions; the `prev.a < 0.5` seed-fallback path handles this gracefully either way.

## JSON Changes
- None (features unchanged; this was a correctness fix, not a capability addition)
