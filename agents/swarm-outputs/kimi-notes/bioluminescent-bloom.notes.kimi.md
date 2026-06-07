# bioluminescent-bloom — New Generative Shader Notes

## Overview
Deep-sea creature with glowing tendrils and pulsing dot patterns.

## Algorithm
- 3-8 parametric tendrils from bottom center
- Tendrils use sine-wave displacement for organic wiggle
- Pulsing nodes sampled along each tendril length
- Scattered bioluminescent dots across entire screen
- Dot twinkle via sine phase animation

## Wow Factor
- Looks like footage from deep-sea documentaries
- Tendrils wave and pulse hypnotically

## Risks
- Tendril segment loop: 20 segments * up to 8 tendrils = 160 iterations
- Bottom-heavy composition (all tendrils emanate from bottom)
- Dots may be too sparse at low density
