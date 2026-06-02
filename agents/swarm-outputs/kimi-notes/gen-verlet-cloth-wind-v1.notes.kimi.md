# gen-verlet-cloth-wind — New Shader Notes

## Overview
Verlet integration cloth simulation with wind forces, silk/fabric shading, anisotropic specular highlights, subsurface scattering, and audio-reactive gusts.

## Algorithm
- 64×64 cloth grid stored in dataTextureC/dataTextureA for temporal feedback
- Verlet-style integration: velocity += gravity + wind + Laplacian spring force
- Top row is pinned; all other nodes are free
- Wind force uses two octaves of FBM noise, modulated by bass
- Mouse down pulls nearby vertices toward cursor
- First-frame initialization to flat rest state
- Bilinear interpolation of height field for smooth rendering
- Fabric BRDF: diffuse lerp + anisotropic specular + SSS backlighting
- ACES tone mapping + weave grain + vignette

## Wow Factor
- Fabric genuinely ripples and waves like silk in a breeze
- Audio bass creates dramatic wind gusts that whip the cloth
- Mouse interaction lets users grab and pull the fabric

## Risks
- Generative — no image input
- 64×64 physics grid means limited cloth resolution
- One-frame lag between physics and render (uses previous frame dataTextureC)
- Laplacian smoothing approximates constraints rather than true distance constraints
