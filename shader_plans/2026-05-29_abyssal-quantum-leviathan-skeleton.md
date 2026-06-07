# New Shader Plan: Abyssal Quantum-Leviathan Skeleton

## Overview
A majestic, slow-drifting skeletal structure of an ancient cosmic leviathan, formed from luminous quantum bone and ethereal plasma marrow, adrift in a volumetric deep-abyss ocean of light.

## Features
- Colossal, undulating ribcage geometry constructed using complex SDF fractals and sine-wave deformations.
- Glowing quantum marrow that pulsates violently within the bones in synchronization with audio frequencies.
- Fluid aether-currents that weave through the skeletal structure, visualized by multi-layered volumetric noise.
- Mouse interaction creates gravitational vortexes that locally distort the rib structure and pull the aether-currents.
- Volumetric deep-sea scattering with prismatic chromatic aberration along the edges of the bone structures.
- A cinematic, slow-drifting camera perspective that slowly orbits the leviathan.

## Technical Implementation
- File: public/shaders/gen-abyssal-quantum-leviathan-skeleton.wgsl
- Category: generative
- Tags: ["organic", "quantum", "cosmic", "underwater", "volumetric"]
- Algorithm: Raymarching complex skeletal SDFs with volumetric density accumulation for the aether-currents.

### Core Algorithm
Raymarching a combined SDF representing the leviathan skeleton. The ribs are generated using domain repetition along a curved spine path. The bone structure is distorted using smooth minimums and sine-wave displacement to give it an organic, drifting feel. The aether-currents are rendered via volumetric raymarching accumulated along the ray, driven by 3D simplex noise flowing along the spine axis.

### Mouse Interaction
The mouse position (u.zoom_config.y, u.zoom_config.z) is mapped to a 3D coordinate in world space. This point acts as a gravity well, applying a radial displacement to the skeletal SDF and twisting the domain of the 3D noise used for the aether-currents.

### Color Mapping / Shading
Deep oceanic blues and teals for the volumetric background, transitioning into bright, glowing cyan and bioluminescent purple for the bone marrow. The bones use a subsurface scattering approximation by sampling the SDF inside the surface, mixed with a rim-light Fresnel effect and metallic reflections from ambient "starlight".

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Abyssal Quantum-Leviathan Skeleton
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Bone Density, y=Marrow Glow, z=Current Turbulence, w=Audio Reactivity
    ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
```

## Parameters (for UI sliders)

Bone Density (0.5, 0.1, 1.0, 0.01)
Marrow Glow (0.8, 0.0, 2.0, 0.01)
Current Turbulence (0.6, 0.0, 1.5, 0.01)
Audio Reactivity (1.0, 0.0, 2.0, 0.01)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
