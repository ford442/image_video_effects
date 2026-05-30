# KIMI BRIEF — spectral-brush

## Creative Spark
A temporal spectral painting tool where mouse strokes paint with physical blackbody radiation colors (deep red → orange → white → blue-white based on "temperature" parameter). Temporal feedback uses `hue_preserve_clamp` + ACES tone mapping so previous strokes evolve rather than just fade. Bass creates bloom around active strokes; depth makes background strokes diffuse like watercolor while foreground strokes stay crisp and hot.

This week we are pushing: **physical blackbody color + ACES tone-mapped temporal feedback + bass bloom + depth diffusion**. Do not produce generic rainbow gradients or simple HSV cycling.

## Differentiate From
- `digital-mold` (image): organic growth spread — yours is deliberate painting with physics-based color
- `charcoal-rub` (image): smeared charcoal — yours is luminous, spectral, and hot
- `spectral-brush` (current): basic spectral fade — yours is now physically grounded and HDR

## Wow Mandate
Painting slowly with the mouse should leave a trail that genuinely feels like dragging a hot iron across a surface — the center is white-hot, edges cool to red, and previous strokes slowly cool and darken over time. Bass should make the current stroke bloom like a welding arc.

## Target
135 lines. Math density over commentary.
