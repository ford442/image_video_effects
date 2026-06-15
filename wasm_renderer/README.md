# WASM WebGPU Renderer (C++)

A high-performance C++ WebGPU rendering backend using Emscripten and Dawn/emdawnwebgpu.
Provides an alternative to the JavaScript WebGPU renderer with potential performance benefits.

## Current Status

✅ **Core Implementation Complete** (compute + present pipeline)
- WebGPU device initialization
- Universal bind group layout (matches all 587+ shaders)
- Texture management (ping-pong, depth, data A/B/C)
- Uniform buffer management
- Shader loading and pipeline caching
- Ping-pong texture copying for feedback effects
- Surface/render pass integration (`PresentToSurface`, see `renderer.cpp`)
- Image loading from JS
- TypeScript integration

⚠️ **See [Current known reliability caveats](#current-known-reliability-caveats-june-2026)
below** — the compute + present pipeline above is implemented, and the June
2026 reliability pass (#817/#818/#819/#820/#822) has hardened the
init/format/limits handshake around it. **#821 (bridge sync) is still
partial** — read the caveats section before assuming the dev-copy
`wasm_renderer/wasm_bridge.js` matches the app-facing bridge.

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

## Error Visibility & Diagnostics (Phase 2)

The WASM renderer now provides detailed diagnostic information to help troubleshoot issues:

### Browser Console Diagnostics

**Check overall renderer status:**
```js
window.__rendererManager?.getDiagnostics()
```

**Output (example):**
```json
{
  "rendererType": "wasm",
  "metrics": { "fps": 60, "isWASM": true, ... },
  "wasm": {
    "initialized": true,
    "initAttempts": 1,
    "errorCount": 0,
    "lastErrorTime": null,
    "fps": 60,
    "hasModule": true
  }
}
```

### WASM Bridge Diagnostics

The `wasm_bridge.js` module tracks:
- Module initialization time
- Load error count and details
- Last error message
- Canvas resolution
- Whether the Emscripten `ccall` interface is available (indicates real binary vs. stub)

**Access via:**
```js
// Internal diagnostic API (development only)
// Check wasm_renderer/wasm_bridge.js getDiagnostics() function
```

### Error Types

The enhanced error handling reports:
- `wasm-unavailable` — WASM binary missing or not buildable
- `wasm-init` — Device creation or initialization failed
- `wasm-device-lost` — GPU device was lost (driver crash, tab backgrounded, etc.)

### Console Output Examples

#### Successful initialization:
```
🔧 WASM renderer explicitly requested via ?renderer=wasm
[WASM] Loading from: http://localhost:3000/wasm/pixelocity_wasm.js
[WASM] Canvas size: 2048x2048
[WASM] Creating module from factory...
[WASM] Calling initWasmRenderer( 2048 , 2048 )
[WASM] ✅ Initialization complete in 125ms
✅ Using C++ WASM renderer (forced via ?renderer=wasm)
```

#### Stub module detected:
```
[WASM] Loading from: http://localhost:3000/wasm/pixelocity_wasm.js
[WASM] PixelocityWASM found on window after script load (stub module?)
⚠️ WASM renderer requested but failed to initialize — falling back to TypeScript WebGPU
```

#### Build missing:
```
[WASM] Failed to load WASM script: 404 Not Found
⚠️ WASM renderer requested but failed to initialize — falling back to TypeScript WebGPU
```

### Runtime Switching for Testing

You can dynamically test the WASM path without rebuilding:

```js
// Switch to WASM (will fail gracefully if not built)
const success = await window.__rendererManager?.switchRenderer('wasm');
console.log('WASM switch result:', success);

// Get the active renderer type
window.__rendererManager?.getActiveRendererType();  // 'wasm' | 'webgpu' | 'js'

// Check for errors
const diagnostics = window.__rendererManager?.getDiagnostics();
if (diagnostics.wasm?.errorCount > 0) {
  console.log('WASM errors:', diagnostics.wasm.lastLoadError);
}
```

### Testing Checklist

See [`../WASM_TESTING.md`](../WASM_TESTING.md) for comprehensive testing procedures.

Quick smoke test:
1. Open `http://localhost:3000/?renderer=wasm`
2. Check console for `✅ Using C++ WASM renderer`
3. Run: `window.__rendererManager?.getDiagnostics()`
4. Verify `fps > 0` and `errorCount === 0`
5. Select a shader and verify it renders

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

## Current known reliability caveats (June 2026)

The compute + present pipeline described above is real and working
(`Render()` → `PresentToSurface()` in `renderer.cpp`). The June 2026 work
(tracked under [#799](https://github.com/ford442/image_video_effects/issues/799),
roadmap comment [here](https://github.com/ford442/image_video_effects/issues/799#issuecomment-4678258584))
hardened the init/format/limits handshake around it. **#818, #820, #817,
#819, and #822 have landed**; **#821 is partial**:

- **#818 — Format negotiation** ✅: surface/pipeline format is now negotiated
  via `getPreferredCanvasFormat()` instead of hardcoded `BGRA8Unorm`.
- **#820 — Fatal surface failure** ✅: surface-creation failure is now a fatal
  init error instead of leaving the renderer half-initialized.
- **#817 / #819 — Adapter & limits** ✅: adapter info/limits are now queried
  and logged, with explicit `requiredLimits`/validation at device creation.
- **#822 — Init error paths** ✅: `Initialize()` now has unified error paths
  with RAII cleanup (`Shutdown()`) on every failure, plus structured
  diagnostics (`getLastInitErrorStage()` / `getLastInitErrorMessage()`)
  surfaced to JS via `WASMRenderer.getDiagnostics()`.
- **#821 — Bridge sync** 🔶 **partial**: `src/wasm/wasm_bridge.js` (the copy
  actually imported by the app via `WASMRenderer.ts`) now exports the new
  #817/#822 diagnostics, but it still differs from the dev/reference copy
  `wasm_renderer/wasm_bridge.js` by ~190 lines (each has helpers/diagnostics
  the other lacks). Full reconciliation is still open and is the last item in
  this June 2026 reliability pass.

Current per-issue status is tracked in the
[C++ Solidification Tracking table](../WASM_RENDERER_GAP_ANALYSIS.md#c-solidification-tracking-2026-06)
in `WASM_RENDERER_GAP_ANALYSIS.md`. See also
[`STATUS.md`](STATUS.md#remaining-work--reliability-june-2026) for the
dependency-ordered PR sequence.

## Roadmap

- [x] WebGPU device initialization
- [x] Universal bind group layout
- [x] Texture resource management
- [x] Uniform buffer management
- [x] Shader loading and caching
- [x] Compute pipeline execution
- [x] Ping-pong texture copying
- [x] Surface/render pass to canvas
- [x] Image upload from JS
- [x] Video texture support
- [x] Multiple compute passes (multi-slot pipeline)
- [x] Audio input support
- [x] Depth map support
- [x] Frame capture / screenshot
- [x] Video recording
- [x] RAII resource management
- [x] Error handling and validation
- [ ] Bridge sync between `src/wasm/` and `wasm_renderer/` (#821, partial — app-facing copy has new diagnostics, ~190-line diff remains)
- [x] Surface/pipeline format negotiation via `getPreferredCanvasFormat()` (#818)
- [x] Fatal surface-creation failure handling (#820)
- [x] Adapter info/limits query + logging (#817)
- [x] Explicit `requiredLimits` + early validation (#819)
- [x] Unified init error paths + structured diagnostics (#822)
- [ ] Formal performance benchmarks vs JS renderer
- [ ] Full automated test suite
- [ ] Live-browser smoke test of June 2026 reliability fixes (`build.sh` doesn't run in this sandbox)

See [`STATUS.md`](STATUS.md) for the authoritative current-state document.

## License

Same as parent project
