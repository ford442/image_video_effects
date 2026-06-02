# gen-minimal-surface-soap-iridescence — Kimi Notes

## Changes
- Chromatic film thickness: R/G/B use different optical path lengths, creating rainbow edge separation.
- Temporal surface memory: `dataTextureC` blend captures morph trail between catenoid and helicoid states.
- Audio-reactive caustic enhancement: `treble` boosts HDR caustic highlights.
- Depth output from `rz` perspective projection for downstream compositing.

## Wow-Factor
- Soap film that splits white light into prismatic fringes as it morphs — physically inspired thin-film optics.
- Temporal memory makes the Bonnet rotation feel like a continuous material transformation.

## Risks
- `cosh`/`sinh` are moderately expensive transcendental functions; 4 per pixel.
- Chromatic triple evaluation of `hsv2rgb` is 3× the ALU; acceptable but not free.
