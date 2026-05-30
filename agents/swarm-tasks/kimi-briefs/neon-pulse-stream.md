# KIMI BRIEF — neon-pulse-stream

## Creative Spark
Video luminance drives a fluid flow of neon trails, but the trails are now true 3D tubes with Fresnel rim lighting — they glow brightest at their edges and fade in the center. The advection field uses divergence-free curl noise so flow never pinches or explodes. Treble injects sparkle particles along high-luminance paths that decay over 10–15 frames.

This week we are pushing: **3D tube Fresnel lighting + divergence-free fluid advection + particle sparkle injection**. Do not produce flat 2D lines or simple Gaussian glow.

## Differentiate From
- `neon-strings` (image): physics string simulation — yours is fluid advection, not springs
- `neon-pulse-edge` (unclaimed): edge-only neon — yours paints the full luminance field
- `neon-flashlight` (image): radial beam — yours is directional flow following image brightness

## Wow Mandate
When the mouse moves quickly, the trail should feel like a glowing liquid being poured — it follows the motion with slight overshoot and then settles. Treble spikes should send visible sparkle "fireflies" racing down the brightest paths.

## Target
135 lines. Math density over commentary.
