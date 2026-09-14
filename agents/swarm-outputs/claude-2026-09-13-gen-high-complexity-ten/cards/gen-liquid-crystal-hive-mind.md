# Idea Card — gen-liquid-crystal-hive-mind

```
SHADER: gen-liquid-crystal-hive-mind
IDENTITY: a top-down raymarched honeycomb of dark glossy hex-prism walls, each cell filled with curl-noise turbulent iridescent liquid crystal accumulated volumetrically; pointer disrupts/rotates cells, clicks inject chemotactic fronts into a persistent hive-pulse state.
KEEP VERBATIM: opRepHex + hollow sdHexPrism walls, per-cell height pulse with Sync Pulse phase alignment, curlNoise/fbm fluid glow, 80-step wall/fluid march, IQ fluid palette (pre-existing, not new), wall diffuse/spec/rim shading, vignette, click fronts, membrane/alpha/depth formulas, chroma shift + huePreserveClamp + ACES, composite over input, slider roles (x Cell Density, y Fluid Turbulence, z Sync Pulse, w Disruption Radius).
EXISTING IDEAS: none named (June hygiene pass only).
ADD:
  1. Crossed-polariser birefringence — map() exposes the local nematic director angle (from the curl flow it already computes); the fluid accumulation adds Michel-Lévy interference colour, sin²(2θ) extinction times a per-wavelength retardance fringe driven by turbulence and march depth. Native: this is literally liquid crystal; birefringent director textures are how LC looks under polarised light.
  2. Hive relay wave — a cell-quantised signal ring spreads outward from the pointer's hex cell, lighting whole cells in sequence (hex-id distance, paced by Sync Pulse, bass-lifted); it brightens the cell fluid and wall rims and feeds the persistent hive-pulse state. Native: the "hive-mind" synchronises cell-to-cell; it extends the existing Sync Pulse / hivePulse mechanism rather than overlaying ripples.
FORBID: springs, new ripple systems, replacing the IQ palette with another palette, extraBuffer state, dataTextureB, changing the A packing.
A PACKING: raw sim state (unchanged): A.r/g/b = bass/mids/treble envelopes, A.a = hive pulse; C read with exact textureLoad at coord. Not tone-mapped.
```
