# gen-metaball-soft-body — New Shader Notes

## Overview
Metaballs defined by implicit field functions that merge and split organically. Centers animated via coupled harmonic oscillators with mouse attraction, producing glossy liquid-metal surfaces.

## Algorithm
- Field function f(x,y) = Σ rᵢ² / ((x-xᵢ)² + (y-yᵢ)²) summed over 3-6 balls
- Centers orbit with independent frequencies + secondary wobble terms
- Mouse attraction displaces centers toward cursor when clicked
- Gradient computed via offset sampling for surface normals
- Surface threshold implicitly at f ≈ 1 via masking

## Visual Details
- Glossy liquid-metal base with adjustable hue shift
- Fresnel reflections brighter at grazing angles
- Phong specular highlight from upper-right light
- Subsurface scattering warmth in deep merge regions
- Chromatic caustics from gradient magnitude
- ACES tone mapping

## Interactivity
- Bass drives metaball pulsation (radius expansion)
- Mouse attracts/repels centers toward cursor
- Depth controls surface opacity and depth output
- Parameters: ball count, roughness, metal hue, caustic strength

## Risks
- Generative — no image input for main effect
- Field evaluated 3 times per pixel (center + dx + dy) = up to 18 loop iterations
- Normal approximation via forward difference is acceptable for this style
