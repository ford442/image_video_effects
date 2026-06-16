# WASM Renderer Smoke Test Guide

This document provides manual verification steps to test that the C++ WASM renderer is working correctly.

## Prerequisites

1. **Build the WASM module** (requires [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html)):

   ```bash
   cd wasm_renderer
   ./build.sh
   ```

   This produces:
   - `public/wasm/pixelocity_wasm.js` — Emscripten JavaScript glue code
   - `public/wasm/pixelocity_wasm.wasm` — WebGPU binary
   - `public/wasm/wasm_bridge.js` — Bridge interface

   **Note:** If `emcc` is not available, the build will fail with:
   ```
   ❌ Error: emcc not found. Install the Emscripten SDK...
   ```

2. **Start the development server:**

   ```bash
   npm start
   ```

   This starts the app on http://localhost:3000 (or the next available port).

---

## Current known reliability caveats (June 2026)

Presentation **exists** — `Render()` calls `PresentToSurface()` (`renderer.cpp:1725`).
The June 2026 C++ batch ([#799](https://github.com/ford442/image_video_effects/issues/799),
[roadmap](https://github.com/ford442/image_video_effects/issues/799#issuecomment-4678258584))
hardened init/format/limits ([#817](https://github.com/ford442/image_video_effects/issues/817)–[#822](https://github.com/ford442/image_video_effects/issues/822) ✅).

When smoke tests **fail**, check structured diagnostics:

```js
const d = window.__rendererManager?.getDiagnostics()?.wasm;
console.log(d?.failedStageName, d?.lastInitError, d?.lastLoadError, d?.adapterInfo);
```

See [`WASM_RENDERER_GAP_ANALYSIS.md`](./WASM_RENDERER_GAP_ANALYSIS.md) for the
full tracking table and remaining integration gaps.

---

## Test 1: Force WASM Renderer at Startup

**Objective:** Verify that the WASM renderer initializes when explicitly requested.

**Steps:**

1. Open http://localhost:3000/?renderer=wasm in your browser
2. Open DevTools console (`F12` or `Ctrl+Shift+I`)
3. Look for one of these messages:

   | Message | Status |
   |---------|--------|
   | ✅ Using C++ WASM renderer (forced via ?renderer=wasm) | **PASS** — WASM initialized successfully |
   | ⚠️ WASM renderer requested but failed to initialise — falling back to TypeScript WebGPU | **FAIL** — WASM unavailable or broken |

4. If **FAIL**, check the console logs for detailed error messages:

   ```
   [WASM] Loading from: http://localhost:3000/wasm/pixelocity_wasm.js
   [WASM] Canvas size: 2048x2048
   [WASM] Creating module from factory...
   [WASM] ✅ Initialization complete in XXXms
   ```

---

## Test 2: Check Renderer Diagnostics

**Objective:** Verify that diagnostic information is available and accurate.

**Steps:**

1. Open the browser console (if not already open)
2. Run this command:

   ```js
   window.__rendererManager?.getDiagnostics()
   ```

3. You should see output like:

   ```json
   {
     "rendererType": "wasm",
     "metrics": {
       "fps": 60,
       "frameTime": 16.67,
       "agentCount": 50000,
       "isWASM": true
     },
     "timestamp": "2026-05-23T16:04:33.070Z",
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

4. **Verify:**
   - `rendererType` should be `"wasm"`
   - `isWASM` should be `true`
   - `initialized` should be `true`
   - `errorCount` should be `0` (or low)
   - `fps` should be > 0

---

## Test 3: Switch Between Renderers

**Objective:** Verify that runtime renderer switching works without crashing.

**Steps:**

1. In the console, run:

   ```js
   // Check current renderer
   window.__rendererManager?.getActiveRendererType();  // Should output 'wasm'

   // Switch to TypeScript WebGPU
   window.__rendererManager?.switchRenderer('webgpu');
   ```

2. Wait a moment for the switch to complete
3. Check the console — should see:
   ```
   ✅ Using TypeScript WebGPU renderer
   ```

4. Verify the canvas is still rendering (not frozen or black)
5. Switch back:

   ```js
   window.__rendererManager?.switchRenderer('wasm');
   ```

6. Console should show:
   ```
   ✅ Using C++ WASM renderer
   ```

7. Canvas should resume rendering

---

## Test 4: Shader Loading

**Objective:** Verify that shaders load and compile in the WASM path.

**Steps:**

1. With the WASM renderer active, open the **Shader Browser**
2. Select a category (e.g., "Generative")
3. Click on a shader (e.g., "Perlin Noise")
4. **Expected:** The canvas updates with the new shader effect
5. **Console should show:**
   ```
   [Shader] Loading: generative/perlin-noise
   ```

6. **If the shader doesn't appear:**
   - Check console for errors like:
     ```
     [WASM] Renderer not initialized
     Failed to load shader
     ```
   - This indicates the WASM renderer failed or shader loading is not yet implemented

---

## Test 5: Mouse Interaction

**Objective:** Verify that mouse events are passed to the WASM renderer.

**Steps:**

1. Select a mouse-driven shader (e.g., "Liquid Ripple" from `interactive-mouse` category)
2. Move your mouse over the canvas
3. Click on the canvas
4. **Expected:** Visual changes based on mouse position/clicks
5. **If no effect:**
   - Check console for mouse event errors
   - Verify the shader actually uses mouse coordinates in its uniforms

---

## Test 6: Error Handling & Fallback

**Objective:** Verify that WASM failures degrade gracefully.

**Steps:**

1. Temporarily simulate WASM failure by running:

   ```js
   // Destroy the WASM renderer
   window.__rendererManager?.currentRenderer?.destroy();
   ```

2. Try to use the app (switch shaders, move mouse)
3. **Expected:** No crashes, app remains responsive
4. In console, run:

   ```js
   // Try to switch to WASM (should fail gracefully)
   const success = await window.__rendererManager?.switchRenderer('wasm');
   console.log('Switch result:', success);
   ```

5. If `success === false`, app should auto-fall back to WebGPU

---

## Automated Smoke Test (Browser Console)

Run this script in the browser console to perform all tests programmatically:

```js
async function wasmSmokeTest() {
  const rm = window.__rendererManager;
  if (!rm) {
    console.error('❌ RendererManager not exposed (not in dev mode?)');
    return;
  }

  console.log('🧪 Running WASM smoke tests...');

  // Test 1: Check initial state
  const diagnostics = rm.getDiagnostics();
  console.log('📊 Diagnostics:', diagnostics);
  
  if (diagnostics.rendererType === 'wasm') {
    console.log('✅ Test 1 PASS: WASM renderer is active');
  } else {
    console.log('❌ Test 1 FAIL: Expected WASM, got', diagnostics.rendererType);
  }

  // Test 2: Switch to WebGPU
  const webgpuSuccess = await rm.switchRenderer('webgpu');
  const webgpuType = rm.getActiveRendererType();
  if (webgpuSuccess && webgpuType === 'webgpu') {
    console.log('✅ Test 2 PASS: Switched to WebGPU');
  } else {
    console.log('❌ Test 2 FAIL: Could not switch to WebGPU');
  }

  // Test 3: Switch back to WASM
  const wasmSuccess = await rm.switchRenderer('wasm');
  const wasmType = rm.getActiveRendererType();
  if (wasmSuccess && wasmType === 'wasm') {
    console.log('✅ Test 3 PASS: Switched back to WASM');
  } else {
    console.log('❌ Test 3 FAIL: Could not switch back to WASM');
  }

  // Test 4: Check FPS
  const fps = rm.currentRenderer?.getFPS?.();
  if (fps && fps > 0) {
    console.log(`✅ Test 4 PASS: Renderer FPS is ${fps.toFixed(1)}`);
  } else {
    console.log(`❌ Test 4 FAIL: FPS not available or zero`);
  }

  console.log('🎉 Smoke test complete!');
}

// Run it
wasmSmokeTest().catch(err => console.error('Test error:', err));
```

---

## Troubleshooting

### Problem: "PixelocityWASM not found on window"

**Cause:** The `pixelocity_wasm.js` file is missing or is a stub.

**Solution:**
1. Verify Emscripten SDK is installed:
   ```bash
   emcc --version
   ```
2. Build the WASM renderer:
   ```bash
   cd wasm_renderer
   ./build.sh
   ```
3. Check that files exist:
   ```bash
   ls -lh public/wasm/
   # Should show pixelocity_wasm.js (50+ KB) and pixelocity_wasm.wasm (79 KB)
   ```

### Problem: "Failed to get WebGPU device"

**Cause:** WebGPU device creation failed in the C++ code (GPU not supported, device lost, etc.).

**Solution:**
1. Check browser support: https://caniuse.com/webgpu
2. Ensure you're using Chrome 113+, Edge 113+, or Firefox Nightly
3. Check if WebGPU is available:
   ```js
   console.log('WebGPU available:', !!navigator.gpu);
   ```
4. Try the TypeScript WebGPU renderer:
   ```js
   window.__rendererManager?.switchRenderer('webgpu');
   ```

### Problem: Renderer switches to Canvas2D instead of WASM

**Cause:** WASM initialization failed, app fell back to Canvas2D fallback.

**Check logs:**
```js
// Get detailed error information
window.__rendererManager?.currentRenderer?.getDiagnostics?.();
```

Look for `lastLoadError`, `lastInitError`, `failedStageName`, or `lastErrorTime` in the output.

---

## Next Steps

Once the WASM smoke tests pass:

1. **Performance Testing:** Compare frame time and FPS between WASM and TypeScript renderers
2. **Feature Testing:** Verify all shader effects work in the WASM path (multi-slot, depth, audio, etc.)
3. **Stress Testing:** Load complex shaders, rapid parameter changes, high mouse interaction rates

---

## Reporting Issues

If WASM smoke tests fail, please collect:

1. **Browser and version:**
   ```js
   navigator.userAgent
   ```

2. **WebGPU availability:**
   ```js
   !!navigator.gpu
   ```

3. **Full console output** during initialization

4. **Diagnostic dump:**
   ```js
   window.__rendererManager?.getDiagnostics()
   ```

5. **Steps to reproduce** the failure

File an issue with the label `wasm` and attach this information.
