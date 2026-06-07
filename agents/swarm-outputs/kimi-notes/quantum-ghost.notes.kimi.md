# quantum-ghost — New Shader Notes

## Overview
Quantum interference ghosting effect. Image duplicated with offset creating fringe patterns.

## Algorithm
- Main image sampled at UV
- Ghost image sampled at UV + offset (from mouse direction)
- Temporal ghost accumulated via dataTextureC
- Cosine fringe pattern modulated by dot product with offset direction
- Chromatic separation on ghost (R/B at different offsets)
- Depth attenuation: near objects ghost less

## Wow Factor
- Genuine interference fringe patterns between real and ghost images
- Temporal persistence creates eerie multiple-exposure effect

## Risks
- 4 texture samples per pixel (main + ghost + chromatic R/B)
- Temporal accumulation may saturate to solid color over time
- Fringe frequency may alias at high values
