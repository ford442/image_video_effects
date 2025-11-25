# WebGPU Fluid Simulation - AI Agent Instructions

This document provides structured guidance for AI code agents working on this codebase.

## Quick Reference

| Task | Files to Modify |
|------|-----------------|
| Add new shader effect | `public/shaders/*.wgsl`, `public/shader-list.json` |
| Modify UI controls | `src/components/Controls.tsx` |
| Change rendering logic | `src/renderer/Renderer.ts` |
| Add new render mode | `src/renderer/types.ts`, `Renderer.ts` |
| Update styles | `src/style.css` |

## Build Commands

```bash
npm install    # Install dependencies
npm start      # Development server at localhost:3000
npm run build  # Production build to build/
npm test       # Run tests
```

## Project Structure

```
src/
├── App.tsx                 # Main component, state management, AI model loading
├── index.tsx               # React entry point
├── style.css               # Global styles
├── components/
│   ├── Controls.tsx        # UI controls (mode selector, sliders, buttons)
│   └── WebGPUCanvas.tsx    # Canvas wrapper with mouse event handling
└── renderer/
    ├── Renderer.ts         # WebGPU rendering engine (main logic)
    └── types.ts            # TypeScript types (RenderMode, ShaderEntry)

public/
├── index.html              # HTML entry point
├── shader-list.json        # Shader registry configuration
└── shaders/                # WGSL compute and render shaders
    ├── liquid.wgsl         # Main interactive liquid effect
    ├── liquid-*.wgsl       # Liquid effect variants
    ├── plasma.wgsl         # Plasma ball effect
    ├── vortex.wgsl         # Vortex effect
    ├── galaxy.wgsl         # Galaxy render shader
    ├── imageVideo.wgsl     # Image/video render shader
    └── texture.wgsl        # Texture display render shader
```

## Architecture Overview

The simulation uses a **ping-pong texture system** where compute shaders read previous frame state and write new state.

### Rendering Pipeline

1. **Compute Pass**: Executes effect shader to update liquid state
2. **Render Pass**: Draws result to screen using `texture.wgsl`
3. **Depth Swap**: Ping-pong depth textures for next frame

### Key Components

#### Renderer (`src/renderer/Renderer.ts`)

The main WebGPU orchestrator:

- Manages GPU resources (textures, buffers, pipelines, bind groups)
- Loads shaders dynamically from `shader-list.json`
- Handles mouse ripple effects via `addRipplePoint()`
- Supports plasma ball physics via `firePlasma()`

**Key Methods:**
- `init()`: Initialize WebGPU, load resources, create pipelines
- `render()`: Execute compute and render passes
- `loadRandomImage()`: Fetch and load new image from Google Cloud Storage
- `updateDepthMap()`: Upload AI-generated depth data to GPU
- `getAvailableModes()`: Get list of available shader modes

#### Types (`src/renderer/types.ts`)

```typescript
type RenderMode = 'shader' | 'image' | 'video' | 'ripple' | string;

interface ShaderEntry {
  id: string;    // Unique identifier (e.g., "liquid-metal")
  name: string;  // Display name (e.g., "Liquid Metal")
  url: string;   // Shader path (e.g., "shaders/liquid-metal.wgsl")
}
```

## Adding a New Shader Effect

### Step 1: Create the Shader File

Create `public/shaders/my-effect.wgsl` with this required interface:

```wgsl
// Required bindings - DO NOT MODIFY binding numbers
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

// Required uniform structure
struct Uniforms {
  config: vec4<f32>,       // x=time, y=rippleCount, z=resolutionX, w=resolutionY
  zoom_config: vec4<f32>,  // x=time, y=farthestX, z=farthestY, w=unused
  zoom_params: vec4<f32>,  // x=fgSpeed, y=bgSpeed, z=parallaxStrength, w=fogDensity
  ripples: array<vec4<f32>, 50>,  // Per-ripple: x, y, startTime, unused
};

// Required entry point
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;
  
  // YOUR EFFECT LOGIC HERE
  
  // Sample and modify the image
  let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  
  // Write output (REQUIRED)
  textureStore(writeTexture, global_id.xy, color);
  
  // Update depth for next frame (REQUIRED for depth-aware effects)
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```

### Step 2: Register the Shader

Add entry to `public/shader-list.json`:

```json
{
  "id": "my-effect",
  "name": "My Effect",
  "url": "shaders/my-effect.wgsl"
}
```

### Step 3: Test

1. Run `npm start`
2. Open browser to localhost:3000
3. Select "My Effect" from the mode dropdown

## Common Shader Patterns

### Reading Ripple Data

```wgsl
let rippleCount = u32(u.config.y);
for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
  let ripple = u.ripples[i];
  let ripplePos = ripple.xy;
  let startTime = ripple.z;
  let elapsed = currentTime - startTime;
  // Use ripple data...
}
```

### Depth-Based Effects

```wgsl
let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
// depth: 0.0 = far (background), 1.0 = near (foreground)
let isForeground = depth > 0.5;
```

### UV Displacement

```wgsl
let displacement = vec2<f32>(sin(uv.y * 10.0 + time), cos(uv.x * 10.0 + time)) * 0.01;
let displacedUV = uv + displacement;
let color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
```

## Modifying the Renderer

### Adding a New Uniform

1. Update buffer size in `createResources()`:
```typescript
this.computeUniformBuffer = this.device.createBuffer({
  size: NEW_SIZE,  // Calculate new size
  usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
});
```

2. Update uniform write in `render()`:
```typescript
const uniformArray = new Float32Array(NEW_LENGTH);
uniformArray.set([/* new values */], OFFSET);
this.device.queue.writeBuffer(this.computeUniformBuffer, 0, uniformArray);
```

3. Update shader `Uniforms` struct to match

### Adding a New Texture Binding

1. Add texture creation in `createResources()`
2. Update bind group layout in `createPipelines()`
3. Add to bind group entries in `createBindGroups()`
4. Add matching binding in shader

## Code Style Guidelines

- **TypeScript**: Use strict typing, avoid `any` when possible
- **WGSL Shaders**: Use consistent indentation, comment complex algorithms
- **React**: Functional components with hooks
- **Naming**: camelCase for variables, PascalCase for components/classes

## Dependencies

| Package | Purpose |
|---------|---------|
| react, react-dom | UI framework |
| @webgpu/types | WebGPU TypeScript types |
| @xenova/transformers | AI depth estimation model |
| typescript | Type checking |
| react-scripts | Build tooling |

## Troubleshooting

### Shader Compilation Errors

Check browser DevTools console for WGSL compilation errors. Common issues:
- Missing semicolons
- Type mismatches (e.g., `f32` vs `i32`)
- Incorrect binding numbers

### WebGPU Not Available

Ensure browser supports WebGPU:
- Chrome 113+
- Edge 113+
- Firefox Nightly with `dom.webgpu.enabled` flag

### Texture Size Mismatch

Ensure all textures in bind group have compatible dimensions. The renderer creates textures matching canvas size.
