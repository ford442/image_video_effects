# neural-mandala — New Generative Shader Notes

## Overview
Concentric geometric ring network with nodes and connecting lines that pulse with audio.

## Algorithm
- 4-12 concentric rings with per-ring pulse animation
- Nodes placed on each ring with animated rotation
- Lines connect nodes to next ring's corresponding node
- Color cycles per ring based on hue = ringIndex * 0.08 + time
- Bass drives node size and pulse amplitude

## Wow Factor
- Mesmerizing geometric mandala that literally breathes with the music
- Connection lines create hypnotic web patterns

## Risks
- Nested loops: outer ringCount (up to 12) * inner nodeCount (up to ~28) = up to 336 iterations per pixel
- May be heavy on low-end GPUs
- No anti-aliasing on thin connection lines
