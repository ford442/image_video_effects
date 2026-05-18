# Testing the C++ WASM Renderer

This document describes how to force the C++ Emscripten WASM renderer and verify
that it works end-to-end.

---

## Prerequisites

1. **Build the WASM module** (requires [Emscripten SDK](https://emscripten.org)):

   ```bash
   cd wasm_renderer
   ./build.sh
   # This produces public/wasm/pixelocity_wasm.{js,wasm}
   ```

   The build script also copies `wasm_bridge.js` into `public/wasm/`.
   If you skip this step the WASM renderer will fail to initialise and the app
   falls back to the TypeScript WebGPU renderer automatically.

2. Start the development server:

   ```bash
   npm start
   ```

---

## Forcing the WASM Renderer via URL Query Parameter

Append `?renderer=wasm` to the app URL:

```
http://localhost:3000/?renderer=wasm
```

`RendererManager.init()` reads this parameter and tries the WASM renderer **first**
before falling back to TypeScript WebGPU.  You will see one of the following
messages in the browser DevTools console:

| Message | Meaning |
|---------|---------|
| `✅ Using C++ WASM renderer (forced via ?renderer=wasm)` | WASM initialised successfully |
| `⚠️ WASM renderer requested but failed to initialise — falling back to TypeScript WebGPU` | WASM binary missing or broken; app uses JS WebGPU instead |

Other accepted values:

| Query param | Effect |
|-------------|--------|
| `?renderer=webgpu` | Force TypeScript WebGPU (default when omitted) |
| `?renderer=js` | Force Canvas 2D fallback (no shader effects) |

---

## Runtime Switching via the Browser Console

Once the app has loaded you can switch the active renderer at any time from the
DevTools console:

```js
// Switch to WASM renderer
window.__rendererManager?.switchRenderer('wasm');

// Switch back to the TypeScript WebGPU renderer
window.__rendererManager?.switchRenderer('webgpu');

// Query the currently active renderer type
window.__rendererManager?.getActiveRendererType(); // 'webgpu' | 'wasm' | 'js'
```

> **Note:** `window.__rendererManager` is exposed by `WebGPUCanvas.tsx` in
> development mode.  It is `undefined` in production builds.

---

## UI Toggle (Live Studio Tab)

The **Live Studio** tab (`?tab=live-studio`) contains a `RendererToggle` component
that switches between `JSRenderer` (Canvas 2D) and `WASMRenderer` directly — useful
for testing the WASM path in isolation with HLS stream input.

---

## Verification Checklist

When the WASM renderer is active (`?renderer=wasm`), verify the following:

### Core
- [ ] Console shows `✅ Using C++ WASM renderer`
- [ ] Canvas renders the default shader without errors

### Shader loading
- [ ] Select a shader from the dropdown — it compiles and renders
- [ ] Select a second shader on Slot 1 — multi-slot chained pipeline works
- [ ] Select a third shader on Slot 2 — all three slots render in sequence

### Audio reactivity
- [ ] Enable audio input; bass/mid/treble values animate the shader

### Depth maps
- [ ] Load the DPT depth model; depth-aware shaders respond to depth data

### Input sources
- [ ] Image input renders correctly through the shader pipeline
- [ ] Video input renders frames through the shader pipeline
- [ ] Webcam input works

### Mouse / ripples
- [ ] Mouse position updates shader uniforms (mouse-driven shaders)
- [ ] Click on canvas adds a ripple effect

### Resize & capture
- [ ] Resizing the browser window does not crash the renderer
- [ ] Screenshot / recording works

---

## Known Limitations (May 2026)

- The WASM binary is **not committed** to the repository. You must build it locally
  with Emscripten before testing.
- There are no automated integration tests for the WASM path yet.
- Performance benchmarks vs the TypeScript WebGPU renderer have not been formally
  measured.

---

## Reporting Issues

If the WASM renderer behaves differently from the TypeScript WebGPU renderer,
open an issue and include:

1. Browser + version
2. The exact URL used (including query params)
3. The DevTools console output
4. Steps to reproduce
