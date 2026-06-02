# pixel-reveal v2 — Upgrade Notes

## Overview
Upgraded from ~84 lines to **138 lines**. Added pixel sorting with threshold-based reveal, temporal decay, scanline bands, and film grain.

## Algorithmist Changes
- Pixel sorting threshold: only pixels above luminance threshold are revealed
- Temporal noise accumulation via `fract(noise + time * decayRate * 0.5)`
- Decay only affects non-mouse-painted regions
- Depth-driven pixel block size (`depthBlock = mix(0.5, 1.5, depth)`)

## Visualist Changes
- Glitch chromatic separation on reveal edges (edge-detected R/G/B offsets)
- Scanline bands on hidden regions using `sin(uv.y * resolution.y * 0.7)`
- Film grain via high-frequency hash noise
- ACES tone mapping on final output
- Hidden regions tinted with dark scanline aesthetic

## Interactivist Changes
- Bass drives reveal threshold oscillation (`threshold = 0.3 + bass * 0.25 + sin(time * 3.0) * 0.1`)
- Mouse paints reveal mask (inverted when mouseDown)
- Depth controls pixel size perspective
- Treble adds UV jitter for glitch movement

## Alpha Strategy
`alpha = clamp((1.0 - paintedMask) * (1.0 - temporalDecay * 0.7) * depth + combinedReveal * 0.2, 0.05, 1.0)`
- Semantic: reveal_mask × (1.0 - temporal_decay) × depth
- Never hardcoded to 1.0

## Validation
- naga: ✅ PASSED
- workgroup_size: (16, 16, 1)
- Bindings: 13 exact canonical
