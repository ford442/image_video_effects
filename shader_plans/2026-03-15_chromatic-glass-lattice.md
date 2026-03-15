# New Shader Plan: Chromatic Glass Lattice

## Overview
A crystalline, infinite lattice of dispersing glass that refracts background light into separating RGB spectrums, shattered dynamically by sound frequencies.

## Features
- **Infinite Glass Lattice:** Raymarched geometric structures resembling a complex crystal matrix.
- **Chromatic Dispersion:** Light refracting through the lattice separates into distinct red, green, and blue channels, creating a rainbow effect.
- **Audio-Reactive Shattering:** Sound frequencies (`u.config.y`) cause the glass structure to vibrate, fracture, and dynamically reassemble.
- **Volumetric Caustics:** Light passing through the crystal casts intricate, moving light patterns on internal surfaces.
- **Reflective Facets:** The surface of the glass reflects the environment and internal light sources with sharp, precise angles.
- **Mouse Fracture Point:** The cursor acts as a point of impact, locally shattering the lattice and sending shockwaves of color outward.
- **Sub-surface Glow:** Deep within the structure, a pulsating core emits light that slowly filters through the layers of glass.

## Technical Implementation
- File: public/shaders/gen-chromatic-glass-lattice.wgsl
- Category: generative
- Tags: ["glass", "crystal", "refraction", "chromatic-aberration", "audio-reactive"]
- Algorithm: Raymarching with heavily modified domain repetition, utilizing multiple ray bounces for refraction and chromatic separation.

### Core Algorithm
The scene uses raymarching through a space populated by domain-repeated (`opRep`) geometric primitives (boxes and octahedrons) that are intersected and subtracted to form a complex lattice. The primary feature is simulated refraction: when a ray hits the surface, it is bent according to Snell's law, and the raymarching continues inside the medium.

### Mouse Interaction
The `u.mouse` coordinates are mapped to a 3D point. When the raymarching position nears this point, a 3D Voronoi-based displacement is applied to the SDF, simulating a localized fracturing of the glass structure that spreads outward based on an inverse-square distance falloff.

### Color Mapping / Shading
The shading heavily relies on chromatic aberration. Instead of a single ray per pixel, the shader calculates three separate refraction paths (one for each color channel RGB) with slightly different indices of refraction. This creates a realistic dispersion effect. The base material is highly transparent with strong Fresnel reflections on the outer facets.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Chromatic Glass Lattice
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// SDF Primitives
// sdBox
// sdOctahedron
// opRep (Domain Repetition)

// Helpers
// rot2D (2D Rotation Matrix)
// voronoi3D (for shattering)

// Map Function
// - Applies domain repetition for the lattice structure.
// - Intersects primitives to create crystalline shapes.
// - Applies Voronoi-based displacement near u.mouse to simulate fracturing.
// - Returns vec2(distance, material_id).

// Refraction & Shading
// - Computes normals.
// - Calculates multiple ray paths for R, G, B channels with different indices of refraction.
// - Modulates refraction and reflection based on u.config.y (audio pulse).

// Compute Shader Entry Point
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // 1. Ray setup and camera matrix
    // 2. Multi-pass raymarching for chromatic refraction
    // 3. Shading and color accumulation
    // 4. Volumetric caustics application
    // 5. writeTexture update
}
```

## Parameters (for UI sliders)

- Refraction Index (1.5, 1.0, 3.0, 0.1)
- Chromatic Spread (0.05, 0.0, 0.2, 0.01)
- Lattice Density (2.0, 0.5, 5.0, 0.1)
- Shatter Force (1.0, 0.0, 5.0, 0.1)

## Integration Steps

- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
