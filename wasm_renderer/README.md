# WASM WebGPU Renderer (C++)

A high-performance C++ WebGPU rendering backend using Emscripten and Dawn/emdawnwebgpu.
Provides an alternative to the JavaScript WebGPU renderer with potential performance benefits.

## Current Status

✅ **Core Implementation Complete**
- WebGPU device initialization
- Universal bind group layout (matches all 587+ shaders)
- Texture management (ping-pong, depth, data A/B/C)
- Uniform buffer management
- Shader loading and pipeline caching
- Ping-pong texture copying for feedback effects

🚧 **In Progress**
- Surface/render pass integration
- Image loading from JS
- TypeScript integration

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    JavaScript/TypeScript                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  wasm_bridge.js                                     │   │
│  │  - initWasmRenderer()                               │   │
│  │  - loadShader(id, wgslCode)                         │   │
│  │  - updateUniforms({time, mouse, ...})               │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                  │
│                           ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Emscripten JS Glue (pixelocity_wasm.js)            │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      C++ WASM Module                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  main.cpp                                           │   │
│  │  - EMSCRIPTEN_KEEPALIVE exports                     │   │
│  │  - render loop                                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                  │
│                           ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  renderer.h/cpp                                     │   │
│  │  - WebGPURenderer class                             │   │
│  │  - Device/Resource management                       │   │
│  │  - Compute pipeline execution                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                  │
│                           ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  WebGPU (emdawnwebgpu)                              │   │
│  │  - WGPUDevice, WGPUQueue                            │   │
│  │  - Textures, Buffers, Pipelines                     │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Shader Bindings Reference

All 587+ shaders use this universal bind group layout:

| Binding | Type | Usage |
|---------|------|-------|
| 0 | sampler | Filtering sampler (linear) |
| 1 | texture_2d<f32> | readTexture (input image) |
| 2 | storage_texture | writeTexture (output) |
| 3 | uniform | Uniforms struct |
| 4 | texture_2d<f32> | readDepthTexture |
| 5 | sampler | Non-filtering sampler (nearest) |
| 6 | storage_texture | writeDepthTexture |
| 7 | storage_texture | dataTextureA |
| 8 | storage_texture | dataTextureB |
| 9 | texture_2d<f32> | dataTextureC |
| 10 | storage | extraBuffer (256 floats) |
| 11 | sampler_comparison | comparisonSampler |
| 12 | storage (read-only) | plasmaBuffer |

## Uniforms Structure

```wgsl
struct Uniforms {
  config: vec4<f32>,       // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,  // time, mouseX, mouseY, mouseDown
  zoom_params: vec4<f32>,  // param1, param2, param3, param4
  ripples: array<vec4<f32>, 50>,  // x, y, startTime, unused
};
```

## Build Instructions

### Prerequisites

1. **Emscripten SDK** (emsdk)
   ```bash
   # Install if not already available
   git clone https://github.com/emscripten-core/emsdk.git
   cd emsdk
   ./emsdk install latest
   ./emsdk activate latest
   source ./emsdk_env.sh
   ```

2. **CMake** (3.20+)

### Build

```bash
cd wasm_renderer
./build.sh
```

Or manually:

```bash
cd wasm_renderer
mkdir -p build && cd build
emcmake cmake .. -DCMAKE_BUILD_TYPE=Release
emmake make -j$(nproc)

# Copy outputs
mkdir -p ../../public/wasm
cp pixelocity_wasm.js pixelocity_wasm.wasm ../../public/wasm/
cp ../wasm_bridge.js ../../public/wasm/
```

### Output Files

- `public/wasm/pixelocity_wasm.js` - Emscripten-generated JS glue
- `public/wasm/pixelocity_wasm.wasm` - Compiled WASM binary
- `public/wasm/wasm_bridge.js` - JavaScript bridge for TS integration

## JavaScript API

```javascript
import wasmRenderer from './wasm/wasm_bridge.js';

// Initialize
const canvas = document.getElementById('canvas');
await wasmRenderer.initWasmRenderer(canvas);

// Load a shader
const response = await fetch('shaders/liquid.wgsl');
const wgslCode = await response.text();
await wasmRenderer.loadShader('liquid', wgslCode);

// Set as active
wasmRenderer.setActiveShader('liquid');

// Update uniforms (called each frame)
wasmRenderer.updateUniforms({
  time: performance.now() / 1000,
  mouseX: 0.5,
  mouseY: 0.5,
  mouseDown: false,
  zoomParams: [0.5, 0.5, 0.5, 0.5]
});

// Add ripple effect
wasmRenderer.addRipple(0.5, 0.5);

// Get FPS
console.log('FPS:', wasmRenderer.getFPS());
```

## TypeScript Integration

```typescript
import wasmRenderer, { WasmRenderer } from './wasm/wasm_bridge';

// Type-safe usage
const renderer: WasmRenderer = wasmRenderer;
await renderer.initWasmRenderer(canvas);
```

## Differences from JS Renderer

| Feature | JS Renderer | WASM Renderer |
|---------|-------------|---------------|
| Shader compilation | Chrome's WebGPU | Dawn/emdawnwebgpu |
| Uniform updates | JS → GPUBuffer | C++ memory → GPUBuffer |
| Ping-pong textures | JS-managed | C++-managed |
| Texture copies | JS API | C++ API |
| Render loop | requestAnimationFrame | emscripten_set_main_loop |

## Performance Considerations

- **Initialization**: WASM has higher startup cost (module download + compilation)
- **Shader compilation**: May be faster in C++ (Dawn compiler)
- **Uniform updates**: Direct memory writes (no JS→WASM boundary crossing)
- **Texture operations**: Native C++ WebGPU calls

## Troubleshooting

### "WebGPU not available"
- Ensure browser supports WebGPU (Chrome 113+, Edge 113+)
- Check `chrome://gpu` for WebGPU status

### "Failed to create WebGPU device"
- May require secure context (HTTPS or localhost)
- Check browser console for detailed error

### Build errors
- Ensure Emscripten environment is sourced: `source /opt/emsdk/emsdk_env.sh`
- Verify CMake version: `cmake --version` (need 3.20+)

## Roadmap

- [x] WebGPU device initialization
- [x] Universal bind group layout
- [x] Texture resource management
- [x] Uniform buffer management
- [x] Shader loading and caching
- [x] Compute pipeline execution
- [x] Ping-pong texture copying
- [ ] Surface/render pass to canvas
- [ ] Image upload from JS
- [ ] Video texture support
- [ ] Multiple compute passes
- [ ] Render pass support (vertex/fragment shaders)
- [ ] Audio input support

## License

Same as parent project
