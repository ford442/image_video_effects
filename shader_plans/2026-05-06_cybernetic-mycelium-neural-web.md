# New Shader Plan: Cybernetic-Mycelium Neural-Web

## Overview
A hyper-organic, glowing network of bio-mechanical mycelial threads that endlessly branch, mutate, and pulse with neon-quantum data streams, synchronizing their growth cycles to ambient audio rhythms.

## Features
- Procedural, infinite branching algorithm mimicking natural mycelium growth mapped onto a 3D structural lattice.
- Luminous data-pulses traveling along the web, illuminating intersection nodes with intense bursts of light.
- Audio-reactive growth rates and pulse intensities, causing violent geometric blooming on heavy bass.
- Subsurface scattering and organic displacement, giving the threads a tactile, fleshy-yet-synthetic appearance.
- Real-time decay and rebirth cycles where unused threads dissolve into glowing particulate dust.

## Technical Implementation
- File: public/shaders/gen-cybernetic-mycelium-neural-web.wgsl
- Category: generative
- Tags: ["organic", "quantum", "mechanical", "audio-reactive", "fractal"]
- Algorithm: A multi-pass compute architecture combining 3D KIFS fractals for the structural lattice with a biologically-inspired particle branching system (similar to slime mold/Physarum) that traverses the structural distances, driven by curl noise and audio data.

### Core Algorithm
- **Structural Lattice**: Evaluated via a continuously mutating 3D KIFS fractal, establishing 'nutrient hotspots'.
- **Mycelial Branching**: Agent-based simulation in a ping-pong buffer where agents deposit 'chemical trails' on a 2D map, but their steering is biased towards the 3D lattice hotspots projected into 2D space.
- **Data Pulses**: High-speed secondary agents that travel strictly along the highest-density trails left by the mycelium, acting as glowing electrical signals.
- **Audio Modulation**: Bass frequencies dramatically increase the mutation rate of the KIFS fractal and multiply the growth speed of the mycelial agents.

### Mouse Interaction
- The mouse acts as a primary 'nutrient source' or 'infection point'. Dragging the mouse creates a massive hotspot that draws all mycelial agents towards it, instantly spawning a concentrated, hyper-dense web structure.

### Color Mapping / Shading
- The base threads are rendered in deep, fleshy bio-mechanical tones (dark purples and metallic greys).
- Data pulses and trail densities are mapped via `plasmaBuffer` to intense, blooming neon greens and cyans, simulating bioluminescence.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Cybernetic-Mycelium Neural-Web
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// Additional bindings for agent buffers and trail maps

struct Agent {
    pos: vec2<f32>,
    angle: f32,
    state: i32, // 0: mycelium, 1: data pulse
}

// ... Uniforms, params ...

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) coords: vec3<u32>) {
    // 1. Boundary Check
    if (coords.x >= u32(u.config.x) || coords.y >= u32(u.config.y)) { return; }

    // 2. Evaluate KIFS fractal to find nutrient hotspots
    // 3. Update agent positions based on trail density and hotspots
    // 4. Deposit trails and data pulses
    // 5. Apply audio-reactive decay and color mapping
    // 6. Write to output texture
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Growth Rate (0.5, 0.0, 1.0, 0.01)
- Pulse Intensity (0.8, 0.0, 2.0, 0.05)
- Decay Speed (0.2, 0.01, 1.0, 0.01)
- Network Complexity (0.6, 0.1, 1.0, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
