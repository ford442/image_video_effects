# WebGPU Fluid Simulation Agents

This project simulates interactive, fluid-like behavior on an image using WebGPU.

## Architecture

The simulation is built around a "ping-pong" texture system where compute shaders read the previous frame's state and write the new state.

### 1. The Renderer (`src/renderer/Renderer.ts`)

This is the main orchestrator, written in TypeScript.

*   **Role**: Manages all WebGPU resources (textures, buffers, pipelines).
*   **Dynamic Loading**: It loads available shaders from `public/shader-list.json`. This allows adding new effects by simply adding a `.wgsl` file and updating the JSON list.
*   **Rendering**: It executes a compute pass (to update the liquid state) followed by a render pass (to draw the result to the screen).

### 2. Compute Shaders (`public/shaders/liquid-*.wgsl`)

These are single-pass compute shaders that handle both the physics simulation (ripples, flow) and the visual distortion.

*   **Input**: Reads the previous frame's color and depth textures, and receives user input (mouse position, time) via a Uniform Buffer.
*   **Output**: Writes the distorted image to a storage texture (`writeTexture`) and updates the depth map (`writeDepthTexture`) for the next frame.
*   **Standard Interface**: All compute shaders share a standardized `Uniforms` structure to ensuring compatibility with the Renderer.

### 3. Shader Configuration (`public/shader-list.json`)

Defines the list of available shaders in the application.

*   **Format**: JSON array of objects with `id`, `name`, and `url`.
*   **Remote Loading**: Supports loading shaders from local paths (e.g., `shaders/liquid.wgsl`) or absolute URLs.
