# New Shader Plan: Cymatic Plasma-Mandalas

## Overview
A hyper-intricate, unfolding kaleidoscope of glowing liquid geometry that dances and weaves complex, sacred-geometry-inspired mandalas in direct response to audio frequencies.

## Features
- **Cymatic Mandalas:** Procedural 2D patterns simulating cymatic resonance, forming complex intersecting mandalas and geometric lattice structures.
- **Liquid Plasma Bleed:** Edges of the geometric shapes feature a viscous, glowing plasma bleed that interacts with neighboring shapes.
- **Audio-Driven Folding:** The entire structure recursively folds and morphs based on beat detection and audio intensity (`u.config.y`).
- **Chromatic Aberration:** Intense, dynamic chromatic aberration along the edges of the plasma, simulating a holographic lens distortion.
- **Mouse Interference:** The mouse acts as a localized perturbation field, disrupting the perfect symmetry of the mandalas into chaotic liquid splatters.

## Technical Implementation
- File: public/shaders/gen-cymatic-plasma-mandalas.wgsl
- Category: generative
- Tags: ["mandala", "cymatics", "plasma", "kaleidoscope", "audio-reactive", "liquid"]
- Algorithm: 2D polar coordinate manipulation with domain folding, recursive SDF shapes, and fluid simulation overlays.

### Core Algorithm
The base structure uses polar coordinates (`atan2`, `length`) to create symmetrical domain repetition (kaleidoscope effect). Within this folded domain, multiple rotating polygon SDFs are layered. A cymatic wave function (using `sin` and `cos` over radius and angle) modulates the edges.

### Mouse Interaction
The mouse applies a localized swirl distortion to the UV space before the domain folding step. The distance to the mouse determines the strength of the swirl and a fluid-like displacement noise, temporarily destroying the symmetry.

### Color Mapping / Shading
A high-contrast, bioluminescent neon palette (electric blues, hot pinks, gold) mapped to the SDF distances. The plasma bleed uses an exponential falloff (`exp(-dist * density)`) with overlapping RGB channels offset slightly for chromatic aberration.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Cymatic Plasma-Mandalas
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// --- POLAR REPETITION & FOLDING ---
// fold()
// ...

// --- SHAPE SDFS ---
// sdPolygon(), sdCircle()
// ...

// --- COLOR AND EFFECTS ---
// getPalette(), applyChromaticAberration()
// ...

// --- MAIN LOOP ---
// uv transformation, audio integration
// ...
```

Parameters (for UI sliders)

Symmetry Order (6.0, 3.0, 12.0, 1.0)
Plasma Density (2.0, 0.5, 5.0, 0.1)
Cymatic Frequency (10.0, 1.0, 30.0, 0.5)
Swirl Chaos (1.0, 0.0, 3.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager