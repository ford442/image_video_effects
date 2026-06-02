# generative-psy-swirls — Kimi Notes

## Changes Made
- Fixed missing `<f32>` type args on `vec2`/`vec3`/`vec4` constructors throughout.
- Added temporal swirl layer accumulation via `dataTextureC` blend.
- Added chromatic hue separation per layer (R/G/B layers offset by bass/mids/treble).
- Added audio-driven twist modulation (`twist *= (1 + bass * 0.3)`).

## Wow Factor
- Fixed WGSL compilation errors — now valid WebGPU code.
- Chromatic layers create rainbow vortex depth.
- Temporal accumulation makes trails persist for organic flow.

## Risks for Claude Polish
- `layeredSwirlLayer` called 3x per layer (R/G/B) = 3*layers calls; expensive at high layer count.
- Audio twist may cause sudden rotation jumps at high bass.
- Ripple loop uses `u.ripples` which may be empty; check `rippleCount` guard.
