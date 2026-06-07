# gen_reaction_diffusion — Claude Optimization (2026-06-07)

## Bottlenecks Identified
- Line ~162: `acesToneMap(finalColor * 1.1)` applied raw — no luminance clamp before ACES, hue shifts on bright wavefronts
- No IGN dither → visible banding in smooth gradient regions near zero-activity background
- Features list missing `aces-tone-map` despite shader using it

## Optimizations Applied
- Added `huePreserveClamp(col, 2.0)` before ACES → preserves hue on FitzHugh orange-white wavefronts at peak luminance
- Added IGN dither (`± 0.5/255`) after tone map → eliminates 8-bit banding in smooth recovery zones
- Updated header features list to include `aces-tone-map, hue-preserve-clamp, ign-dither`
- Updated `Upgraded:` date to 2026-06-07

## Visual / Transcendence Notes
- Dual-mode architecture (Gray-Scott / FitzHugh-Nagumo blend) was already solid multi-pass: reads state from dataTextureC, writes newState to dataTextureA — correct ping-pong pattern
- Wavefront highlights now stay saturated orange instead of washing to white at high bass

## Remaining Risks
- At 4K the 9-sample Laplacian (8 neighbors + center) runs ~9 texture loads per thread; acceptable but worth profiling on integrated GPU
- FitzHugh mode with high Stimulus can produce unbounded `uState` before the `clamp(-2.4, 2.4)` — numerically stable but watch for aliasing at extreme params

## JSON Changes
- Added `aces-tone-map`, `hue-preserve-clamp`, `ign-dither` to features array
