# New Shader Plan: Cosmic-Clockwork Dyson-Sphere

## Overview
A hyper-intricate, colossal megastructure of interlocking golden gears, glowing plasma conduits, and rhythmic mechanical fractal shifts, enclosing a blinding quantum singularity that powers an ancient stellar clock.

## Features
- Infinite 3D mechanical fractal architecture built using stepped KIFS and folding operations to create gears and struts.
- Rhythmic, snapping rotations that sync directly to the beat and tempo of ambient audio.
- A brilliant, blooming central singularity emitting volumetric light rays through the rotating gaps.
- Intense metallic reflections, chromatic aberration, and subsurface plasma glow on the inner surfaces.
- A dynamic, multi-layered depth parallax, giving the sense of massive, overwhelming scale.

## Technical Implementation
- File: public/shaders/gen-cosmic-clockwork-dyson-sphere.wgsl
- Category: generative
- Tags: ["mechanical", "cosmic", "fractal", "audio-reactive", "volumetric"]
- Algorithm: Raymarching through a dynamic, multi-folded spatial domain. The SDF combines geometric primitives (cylinders, tori) with recursive KIFS folds to create interlocking gears. Rotation angles are driven by stepped time and audio intensity parameters to simulate mechanical ticking.

### Core Algorithm
- **Spatial Folding**: Use `abs()` and rotational transformations to tile space and create symmetrical, interlocking mechanical structures.
- **Stepped Rotation**: Instead of smooth time, use `floor(time)` and `smoothstep` to create snapping, clock-like gear rotations. Audio bass peaks instantly advance the rotation phase.
- **Volumetric Core**: The origin `(0,0,0)` houses a glowing sphere. Rays passing close to it accumulate energy, mapped to an intense bright-white/gold color palette using `plasmaBuffer`.
- **Metallic Shading**: Compute normals from the SDF and apply an environment-map approximation or a high-contrast matcap-style reflection for a shiny, golden-brass look.

### Mouse Interaction
- The mouse controls the primary camera orbit and the focal length. Clicking and dragging rotates the view around the central singularity, while proximity to the center introduces intense gravity-lensing distortion.

### Color Mapping / Shading
- The mechanical parts are shaded with rich brass, gold, and oxidized copper tones.
- The inner plasma and central singularity use the `plasmaBuffer` to bloom with blindingly bright, hot colors (whites, yellows, electric blues).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Cosmic-Clockwork Dyson-Sphere
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// ... (full skeleton with comments)
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Mechanical Complexity (0.5, 0.1, 1.0, 0.01)
- Clock Speed (0.5, 0.0, 2.0, 0.01)
- Plasma Intensity (0.8, 0.0, 2.0, 0.05)
- Gear Ratio (0.5, 0.1, 1.0, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
