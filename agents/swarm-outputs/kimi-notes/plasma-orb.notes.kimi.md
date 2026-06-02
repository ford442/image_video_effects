# plasma-orb — New Shader Notes

## Overview
Generative electric plasma orb with arcs, core glow, and audio reactivity.

## Algorithm
- 5 concentric arc rings using sine superposition + hash noise
- Arc intensity modulated by radial smoothstep
- Core white-hot center with blue glow halo
- Mouse proximity brightens nearby arcs
- Audio drives arc intensity (bass) and chaos (treble)

## Wow Factor
- Lightning-like arcs dance inside a glass sphere
- Audio makes the orb explode with energy on bass drops

## Risks
- Generative shader — does not use readTexture (may show black if chained after image shader)
- Hash noise for arc chaos may create flickering
- No temporal feedback — arcs jump discontinuously
