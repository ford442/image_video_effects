# symbiotic-light-propagation-networks — Kimi Notes

## Changes
- Chromatic light wavelength splitting: R and B light travel at different speeds through the network (G is reference).
- Audio-driven seeding rates: `bass` boosts mouse seed strength, `mids` modulate growth rate.
- Temporal network persistence: `dataTextureC` accumulated light bleeds into current frame for glowing trails.
- `dataTextureA` stores species/light state; `writeDepthTexture` outputs density + light combined.
- Bass-driven glow pulses near mouse position.

## Wow-Factor
- RGB light transport at different speeds creates chromatic aberration in the network — edges shimmer with prismatic separation.
- Symbiotic glow pulses in time with bass drops.

## Risks
- Light transport requires 3 directional samples (R/G/B at different offsets) = 6 extra fetches per pixel.
- Accumulated light can blow out highlights; `clamp` is conservative but may look dim; Claude may want tonemapping.
