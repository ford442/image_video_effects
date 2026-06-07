# New Shader Plan: Abyssal Chrono-Coral

## Overview
A hyper-dimensional, endlessly growing bioluminescent reef suspended in a cosmic void, where time-dilation forces crystalline coral branches to blossom and shatter in sync with quantum audio frequencies.

## Features
- Infinite, raymarched organic fractal structures resembling alien coral.
- Bioluminescent, audio-reactive nodes pulsing at the branch tips.
- Time-dilation zones where growth speeds up or reverses based on the mouse's gravity well.
- Subsurface scattering and glowing chromatic aberration effects.
- Dynamic camera drifting through the endless cosmic reef.
- Ambient starlight and fluid volumetric fog that reacts to low-frequency hums.

## Technical Implementation
- File: public/shaders/gen-abyssal-chrono-coral.wgsl
- Category: generative
- Tags: ["organic", "fractal", "bioluminescence", "raymarching", "audio-reactive"]
- Algorithm: Raymarching with domain repetition, domain warping, and KIFS for fractal coral generation, combined with volumetric accumulation for the glowing underwater/cosmic fog effect.

### Core Algorithm
The environment uses a volumetric raymarching approach. The central structure is an infinite, repeating domain driven by smooth-minimum blended KIFS (Kaleidoscopic Iterated Function Systems) fractals. This creates branching coral-like structures. Domain warping via 3D FBM noise is applied to make the branches twist and sway organically. Audio frequencies (`u.config.y`) drive the thickness of the branches and the intensity of the bioluminescent nodes.

### Mouse Interaction
The mouse acts as a time-dilation anomaly. When clicked or dragged, a localized spherical gravity well forms around the mouse coordinate mapped to 3D space. Inside this well, the localized time variable (`u.config.x`) speeds up drastically, causing the fractal coral to rapidly grow and bloom, while outside the well, time flows at a normal pace.

### Color Mapping / Shading
The shading model utilizes complex subsurface scattering approximation to give the coral a translucent, fleshy-yet-crystalline appearance. A strong color gradient transitions from deep abyssal blues to blinding neon cyan/magenta at the tips, mapping to the SDF distance. Volumetric fog accumulates along the ray, colored by ambient starlight and glowing chromatic dispersion at the edges of the coral.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Abyssal Chrono-Coral
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
// ... (full skeleton with comments)
```

## Parameters (for UI sliders)

| Name | Default | Min | Max | Step |
|---|---|---|---|---|
| Coral Density | 0.5 | 0.1 | 1.0 | 0.01 |
| Branch Complexity | 4.0 | 1.0 | 8.0 | 1.0 |
| Bioluminescence Glow | 1.0 | 0.0 | 3.0 | 0.1 |
| Time Dilation Field | 0.2 | 0.0 | 1.0 | 0.01 |

## Integration Steps

1. Create shader file `public/shaders/gen-abyssal-chrono-coral.wgsl`
2. Create JSON definition `shader_definitions/generative/gen-abyssal-chrono-coral.json`
3. Run `node scripts/generate_shader_lists.js`
4. Upload via storage_manager
