# WASM WebGPU Renderer

A high-performance C++ WebGPU rendering backend using Emscripten and Dawn/emdawnwebgpu.
Provides an alternative to the JavaScript WebGPU renderer with potential performance benefits.

## Features

- **Compute Shader Rendering**: Full support for WGSL compute shaders
- **Ping-Pong Textures**: Automatic read/write texture swapping for feedback effects
- **Uniform Buffer Management**: Efficient uniform updates
- **JS Bridge**: Easy integration with existing React/TypeScript code
- **Toggle Support**: Switch between JS and WASM renderers at runtime

## Project Structure

```
wasm_renderer/
├── CMakeLists.txt          # Build configuration
├── README.md               # This file
└── src/
    ├── renderer.h          # Main renderer header
    ├── renderer.cpp        # Renderer implementation
    ├── main_test.cpp       # Entry point & JS bindings
    └── wasm_bridge.js      # JavaScript bridge
```

## Prerequisites

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

## Building

### Quick Build

```bash
cd wasm_renderer
mkdir -p build && cd build
emcmake cmake .. -DCMAKE_BUILD_TYPE=Release
emmake make -j$(nproc)
```

### Output

Build artifacts in `build/pkg/`:
- `wasm_renderer_test.js` - Emscripten-generated JS glue
- `wasm_renderer_test.wasm` - Compiled WASM binary
- `wasm_bridge.js` - JavaScript bridge (copied from src/)

## Usage

### 1. Load the WASM Module

```javascript
import { initWasmRenderer } from './wasm_renderer/pkg/wasm_bridge.js';

const renderer = await initWasmRenderer('canvas');
```

### 2. Load a Shader

```javascript
const wgslCode = `
  @group(0) @binding(3) var<uniform> u: Uniforms;
  
  @compute @workgroup_size(8, 8)
  fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // Your shader code here
  }
`;

renderer.loadShader(wgslCode);
```

### 3. Start Rendering

```javascript
renderer.start();

// Update uniforms dynamically
renderer.updateUniforms({
  time: performance.now() / 1000,
  mouse: [x, y, clickX, clickY]
});
```

### 4. React Integration

```tsx
import { useRenderer } from '../components/shaders/RendererContext';

function MyComponent() {
  const { currentRenderer, switchRenderer } = useRenderer();
  
  return (
    <button onClick={() => switchRenderer('cpp-wasm')}>
      Switch to WASM Renderer
    </button>
  );
}
```

## API Reference

### WasmRendererBridge

| Method | Description |
|--------|-------------|
| `initialize(canvasId)` | Initialize WebGPU and create renderer |
| `loadShader(wgslCode)` | Compile and load a WGSL shader |
| `updateUniforms(uniforms)` | Update uniform values |
| `start()` | Begin render loop |
| `stop()` | Stop render loop |
| `render()` | Render single frame |
| `shutdown()` | Cleanup and release resources |
| `getFPS()` | Get current FPS |

### Uniforms Structure

```cpp
struct Uniforms {
  vec2 resolution;    // Canvas size
  float time;         // Time in seconds
  vec4 mouse;         // Mouse position (x, y, clickX, clickY)
  int frame;          // Frame counter
};
```

## Performance Considerations

- **Initialization**: WASM renderer has higher startup cost
- **Shader Compilation**: WGSL compilation happens in C++ (potentially faster)
- **Uniform Updates**: Direct memory access (no JS overhead)
- **Texture Operations**: Native WebGPU from C++

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

- [ ] Multiple compute passes
- [ ] Render pass support (vertex/fragment shaders)
- [ ] Texture upload/download
- [ ] Audio input support
- [ ] Parallel shader compilation

## License

Same as parent project
