# gen-lichen-reaction-diffusion — Claude Optimization (2026-06-07)

## Bottlenecks Identified
- **Critical bug**: `dataTextureA` never written. Lines 113/189 read `prev.rgb`/`prevVal` from `dataTextureC` for both the temporal growth-persistence blend (`temporal = prev.rgb * persistence`) and the `growth_activity = abs(pattern_density - prevVal)` alpha driver — but `dataTextureC` was always zero since nothing wrote `dataTextureA`. Both the persistence trail and activity-driven alpha were dead code.

## Optimizations Applied
- Added `textureStore(dataTextureA, pixel, vec4<f32>(color, pattern_density))` at the end of `main` — completes the ping-pong so `prev.rgb` and `prevVal` (luma of prev) now reflect real prior-frame data
- Added `Upgraded:` date

## Visual / Transcendence Notes
- `growth_activity` (the alpha driver) will now respond to actual frame-to-frame pattern change rather than a constant `pattern_density - 0`, making lichen edges/growth fronts visually pop with proper alpha modulation
- The persistence trail (`color = max(color, temporal * 0.35)`) will now create the intended slow organic bloom-and-fade

## Remaining Risks
- Verify alpha doesn't spike on the first few frames while the feedback loop "warms up" from zero — `growth_activity` will initially be large since `prevVal` starts at 0

## JSON Changes
- None (features unchanged; this activates the shader's existing temporal-feedback intent)
