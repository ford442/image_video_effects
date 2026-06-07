# New Shader Plan: Liquid-Crystal Hive-Mind

## Overview
A vast, breathing network of hexagonal bio-synthetic cells containing turbulent, iridescent liquid crystals that synchronize and glow with a pulsing collective consciousness.

## Features
- **Hexagonal Cellular Matrix:** Infinite, raymarched honeycomb structure serving as containment for fluid dynamic processes.
- **Turbulent Fluid Cores:** Each cell contains a swirling, liquid-crystal substance driven by 3D curl noise and fractional brownian motion.
- **Hive Synchronization:** Audio input (`u.config.y`) causes neighboring cells to align their fluid patterns and pulse with unified bioluminescent energy.
- **Chromatic Iridescence:** The liquid crystal shifts through vibrant spectrums based on viewing angle and internal turbulence.
- **Cursor Disruption:** The mouse acts as a foreign agent, breaking synchronization, shattering nearby cells, and causing the fluid to violently boil outward.
- **Subsurface Depth:** Deep volumetric rendering creates the illusion of looking into infinite layers of glowing, viscous liquid.

## Technical Implementation
- File: public/shaders/gen-liquid-crystal-hive-mind.wgsl
- Category: generative
- Tags: ["cellular", "liquid-crystal", "fluid-dynamics", "honeycomb", "audio-reactive"]
- Algorithm: Raymarching combined with domain repetition on a hexagonal grid (`sdHexPrism`), utilizing 3D curl noise for internal fluid simulation.

### Core Algorithm
Space is folded using hexagonal domain repetition to create the infinite honeycomb lattice. The walls of the cells are defined by a hollowed `sdHexPrism`. Inside each prism, a dense, raymarched volume is sampled using a combination of FBM and 3D curl noise to simulate swirling liquid crystals. The animation speed of the noise is driven by the global time and modulated by `u.config.y` for audio-reactive turbulence.

### Mouse Interaction
The mouse projection in 3D space (`u.mouse`) creates a spherical disruption field. Within this radius, the hexagonal domain repetition is violently offset (shattering effect), and the curl noise amplitude inside the cells is exponentially increased, simulating a boiling, chaotic fluid reaction to the "foreign" cursor.

### Color Mapping / Shading
The cellular walls use a dark, glossy, non-metallic material with sharp specular highlights. The internal fluid uses a volumetric accumulation approach, mapping the noise density to a complex cosine color palette (`palette(t, a, b, c, d)`). The fluid exhibits iridescence by modulating the color palette input based on the dot product of the ray direction and the calculated fluid normal.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Liquid-Crystal Hive-Mind
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// SDF Primitives
// sdHexPrism (Honeycomb cells)
// opRepHex (Hexagonal Domain Repetition)

// Helpers
// rot2D (2D Rotation Matrix)
// curlNoise3D (Turbulent fluid simulation)
// palette (Iridescent color mapping)

// Map Function
// - Folds space into a hexagonal grid.
// - Calculates distances to cell walls and internal fluid volumes.
// - Applies mouse disruption field to shatter walls and boil fluid.
// - Returns vec2(distance, material_id).

// Shading & Volumetrics
// - Computes surface normals for cell walls.
// - Raymarches through the fluid volume, accumulating color and density.
// - Applies iridescent coloring and audio-reactive glow (u.config.y).

// Compute Shader Entry Point
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // 1. Ray setup based on UVs and camera
    // 2. Primary raymarching loop (cell walls)
    // 3. Secondary volumetric loop (liquid crystal)
    // 4. Color accumulation and post-processing
    // 5. writeTexture update
}
```

## Parameters (for UI sliders)

- Cell Density (1.0, 0.5, 3.0, 0.1)
- Fluid Turbulence (2.5, 0.0, 5.0, 0.1)
- Synchronization Pulse (1.0, 0.0, 3.0, 0.1)
- Disruption Radius (0.5, 0.1, 2.0, 0.05)

## Integration Steps

- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
