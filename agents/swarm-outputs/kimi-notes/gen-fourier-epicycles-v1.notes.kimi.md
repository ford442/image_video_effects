# gen-fourier-epicycles — New Shader Notes

## Overview
Fourier series drawn as rotating epicycle wheels. Multiple harmonic circles rotate at different frequencies, their combined trajectory traces complex curves with glowing temporal trails.

## Algorithm
- 3-12 epicycles with frequencies 1..n, each with radius rₙ = base/n * variation and phase φₙ
- Pen tip position computed as vector sum of all rotating arms
- For each pixel: distance to wheel rims, spokes, and pen tip accumulated as glow
- Chromatic separation per frequency band (low=red, high=blue)
- Temporal feedback via dataTextureC decayed blend for persistent trajectory trails

## Visual Details
- Metallic rim glow with HDR falloff
- Pen tip gets warm white glow + cool blue bloom
- ACES tone mapping on composite
- Vignette darkens edges

## Interactivity
- Bass drives rotation speed multiplier
- Mouse X modifies Fourier coefficients (shape distortion)
- Mouse click amplifies radius modulation
- Depth controls trail persistence weight

## Risks
- Generative — no image input for main effect
- Loop up to 12 epicycles per pixel (bounded, acceptable)
- Temporal feedback depends on dataTextureC initialization
