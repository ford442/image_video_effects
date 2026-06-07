# luma-velocity-melt — Kimi Batch E Notes

## Changes Made
- Added chromatic drip: R drips slower (0.9x), B drips faster (1.1x) than G
- Added curl-noise turbulence to melt flow for organic drips
- Added audio heat pulse: bass creates bright orange flash on hot pixels
- Added depth viscosity: near objects melt slower, far objects melt faster
- `dataTextureC` persistence for melt trail accumulation

## Wow Factor
- Melting now looks like dripping paint with realistic chromatic separation
- Audio heat pulses create lava-like bright spots on bright regions

## Risks
- Curl turbulence may destabilize the melt direction unpredictably
- Heat pulse intensity (bass * 0.15) could oversaturate on heavy bass tracks
