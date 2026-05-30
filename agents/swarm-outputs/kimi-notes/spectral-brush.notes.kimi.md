# spectral-brush — Kimi Batch B Notes

## What I Changed
- Replaced simple hue-shift spectral colors with physical blackbody radiation curve (`blackbody` function: 1000K–12000K mapping).
- Added `huePreserveClamp` + ACES tone mapping on the final output for HDR-safe color handling.
- Bass now creates a bloom radius around active strokes that scales with `bass_env`.
- Depth makes background strokes more diffuse (lower `innerRadius`) while foreground stays crisp and hot.
- Added IGN dithering to prevent banding on the smooth blackbody gradient.
- Temporal feedback now cools over time: older strokes shift down the blackbody curve (white-hot → red → dark).

## What I'm Proud Of
Painting slowly feels like dragging a hot iron across a surface — the center is white-hot, edges cool to red, and previous strokes slowly cool and darken over time. Bass makes the current stroke bloom like a welding arc.

## What Might Need a Human Eye
- The blackbody approximation is a compact curve-fit, not a full Planck integral. It looks correct in the visible range but may diverge at extreme temperatures.
- ACES tone mapping can desaturate very hot colors — verify the "welding arc" look is still vivid enough.
- `depthDiffusion` reduces `innerRadius` for background strokes — this can make the brush feel "slippery" at depth extremes.
