# film-gate-weave v2 Upgrade Notes

## Algorithmist Perspective
- Accurate 35mm film gate weave: frame-based timing at 24fps with sub-frame interpolation
- Perforation hole registration jitter computed per 4-perf strip
- Gate flutter from intermittent motion using `smoothstep` on `gateFlutter`
- Film scratch generation with temporal persistence via `dataTextureC` feedback
- Splice tape artifacts appear at random vertical positions

## Visualist Perspective
- Film grain with dye cloud structure: 3-octave hash noise (`dyeCloudGrain`)
- Gate hair accumulation: horizontal hair artifacts
- Splice tape artifacts: yellowish horizontal bands
- ACES tone mapping on final composite
- Chromatic aberration from lens breathing scales with weave amount and sub-frame phase
- Sepia warmth from mids

## Interactivist Perspective
- Bass drives weave amplitude (gate flutter magnitude)
- Mouse scrubs film position horizontally when clicked
- Depth controls grain size (finer grain in focus = deeper depth)
- Treble boosts high-frequency grain, bass adds chromatic flicker to blue channel

## Alpha Strategy
Alpha = `film_weave_confidence * grain_density * depth`
- Weave confidence inversely proportional to weave displacement
- Grain density from grain, dust, scratch, and hair contributions
- Depth as perspective modulator

## Lines
Upgraded from 90 lines to ~149 lines.

## Naga Status
PASSED — validation successful.
