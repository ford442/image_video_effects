# lenia — Kimi Notes

## Changes Made
- Added audio reactivity: bass drives growth rate, mids radius, treble threshold.
- Added chromatic species colors: R/G/B channels evolve at different thresholds.
- Added temporal accumulation with audio-driven blend factor.
- Added mouse interaction: click injects warm life near cursor.
- Expanded neighborhood radius based on audio.
- Fixed params to meaningful names (radius, growthRate, accumulation, threshold).

## Wow Factor
- Three chromatic species create rainbow cellular patterns.
- Audio modulates growth dynamics for reactive life simulation.
- Mouse injection lets user seed new life forms.

## Risks for Claude Polish
- Neighborhood loop uses dynamic `neighRadius`; verify performance at high radius.
- `blendFactor` division by near-zero `totalAlpha` handled by `select`.
- Color formula uses `sin(finalValue * 3.14)` which may not be visible at low values.
