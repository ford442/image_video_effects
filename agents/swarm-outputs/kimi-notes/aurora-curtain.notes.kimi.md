# aurora-curtain — New Shader Notes

## Overview
Generative aurora borealis with layered curtains, audio color shifts, and twinkling stars.

## Algorithm
- 3-7 layered sine-wave curtains with different frequencies/phases
- Mouse X shifts wind direction
- Each layer has distinct hue (green base shifting with audio)
- Star field via hash threshold with twinkle animation
- Treble adds purple upper-atmosphere glow

## Wow Factor
- Ethereal flowing curtains of light that genuinely feel atmospheric
- Audio makes aurora shift colors in real-time

## Risks
- Generative — no image input
- Layer count up to 7 may be heavy (loop in shader)
- Color hue shift from audio may clash with expected green aurora
