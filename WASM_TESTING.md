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

   The build script also copies `wasm_bridge.js` into `public/wasm/` and
   `src/wasm/`. If you skip this step the WASM renderer will fail to initialise
   and the app falls back to the TypeScript WebGPU renderer automatically.

---

2. **Start the development server:**

   ```bash
   npm start
   ```

---

## Current known reliability caveats (July 2026)

The C++ renderer has a **real compute + present pipeline** (`Render()` →
`PresentToSurface()`). Init/format/limits (#817–#822 ✅) and July integration
work (#886–#889 ✅) are in tree.

**Support tier:** **B — experimental opt-in.** TypeScript WebGPU is the production default.

Read next:

- [`WASM_BACKEND_POLICY.md`](./WASM_BACKEND_POLICY.md) — Tier B policy
- [`WASM_RENDERER_GAP_ANALYSIS.md`](./WASM_RENDERER_GAP_ANALYSIS.md) — gaps + July 2026 status
- [`wasm_renderer/STATUS.md`](./wasm_renderer/STATUS.md) — implementation snapshot
- [`WASM_PROMOTION_TRACKING.md`](./WASM_PROMOTION_TRACKING.md) — promotion gates ([#890](https://github.com/ford442/image_video_effects/issues/890))

**Still open:** promotion evidence (bench JSON, multi-GPU parity, 4-week CI green streak), edge-GPU manual verification, automated visual pixel-diff.

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

## Diagnostic API

### Get Overall Renderer Status

```js
const diagnostics = window.__rendererManager?.getDiagnostics();
console.log(diagnostics);
```

**Output example (WASM active):**
```json
{
  "rendererType": "wasm",
  "metrics": {
    "fps": 60,
    "frameTime": 16.67,
    "agentCount": 50000,
    "isWASM": true
  },
  "timestamp": "2026-05-23T16:04:33Z",
  "wasm": {
    "initialized": true,
    "initAttempts": 1,
    "errorCount": 0,
    "lastErrorTime": null,
    "fps": 60,
    "hasModule": true,
    "failedStage": 8,
    "failedStageName": "Ready",
    "lastInitError": "",
    "lastLoadError": null,
    "adapterInfo": "vendor=... | surfaceFormat=rgba8unorm"
  }
}
```

### Check WASM Bridge Diagnostics

```js
// Get low-level WASM bridge status
const bridgeDiag = window.__rendererManager?.currentRenderer?.getDiagnostics?.();
console.log(bridgeDiag);
```

**Output example:**
```json
{
  "initialized": true,
  "initAttempts": 1,
  "errorCount": 0,
  "lastErrorTime": null,
  "fps": 59.8,
  "hasModule": true,
  "failedStage": 8,
  "failedStageName": "Ready",
  "lastInitError": "",
  "lastLoadError": null,
  "initTime": "245ms",
  "adapterInfo": "..."
}
```

On init failure, check `failedStageName` (e.g. `"Adapter"`, `"Surface"`) and
`lastLoadError` / `lastInitError` for the C++ reason — no more generic Dawn guesses.

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
- [ ] `getDiagnostics()` shows `"rendererType": "wasm"` and `initialized: true`
- [ ] Canvas renders the default shader without errors
- [ ] FPS is > 0 and stable

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

### Error resilience
- [ ] Switch to WebGPU and back without errors
- [ ] Load multiple shaders in sequence without hanging
- [ ] Handle network timeouts gracefully

---

## Automated Smoke Test

For a quick check, run this in the browser console:

```js
async function wasmQuickTest() {
  const rm = window.__rendererManager;
  console.log('🧪 WASM Quick Test');
  console.log('Current renderer:', rm?.getActiveRendererType?.());
  console.log('Diagnostics:', rm?.getDiagnostics?.());
  
  if (rm?.getActiveRendererType?.() === 'wasm') {
    console.log('✅ WASM is active');
  } else {
    console.log('❌ WASM is not active');
  }
}

wasmQuickTest();
```

For comprehensive testing, see [WASM_SMOKE_TEST.md](./WASM_SMOKE_TEST.md).

---

## Automated Playwright Tests (CI/E2E)

### Running WASM E2E Tests Locally

To run the automated WASM renderer tests on your machine:

1. **Build the WASM module:**

   ```bash
   npm run wasm:build
   ```

2. **Build the production app:**

   ```bash
   npm run build
   ```

3. **Run the WASM Playwright tests:**

   ```bash
   npx playwright test tests/wasm-renderer.smoke.spec.ts --project=chromium
   ```

4. **View test results:**

   ```bash
   npx playwright show-report
   ```

### What the Tests Validate

See [`WASM_TEST_SUITE.md`](./WASM_TEST_SUITE.md) for the full command matrix. Summary:

| Spec | Purpose |
|------|---------|
| `tests/wasm-renderer.smoke.spec.ts` | `?renderer=wasm&testMode=1`, 5-shader matrix, multi-slot, FPS/canvas health |
| `tests/renderer-parity.spec.ts` | WASM vs WebGPU luminance parity (`WASM_GPU_TESTS=1`) |
| `tests/wasm-benchmark.spec.ts` | FPS/frame-time bench → `test-results/wasm-benchmark-report.json` |
| `tests/layerChain.smoke.spec.ts` | Multi-slot stack smoke |

**Soft mode (CI default):** tolerates JS fallback when no WebGPU adapter.  
**Strict mode:** `WASM_GPU_TESTS=1` requires active `wasm` backend.

### CI Integration

The `.github/workflows/ci.yml` `test-wasm-e2e` job:

- **Depends on:** `wasm` + `test` jobs
- **Runs:** `test:wasm:e2e` (soft) then `test:wasm:gpu` (strict; skips without adapter)
- **Artifacts:** Playwright report, benchmark JSON when produced
- **Manual GPU run:** `wasm-gpu-manual` workflow dispatch → `test:wasm:full`

Promotion evidence: [`WASM_PROMOTION_TRACKING.md`](./WASM_PROMOTION_TRACKING.md)

### Performance Metrics

The test logs frame-time diagnostics for tracking:

```
=== WASM Renderer Metrics ===
Renderer: wasm
FPS: 58.3
Init Time: 245ms
Has Module: true
==============================
```

These metrics can be used to detect performance regressions.

---

## Known Limitations (July 2026)

- WASM is **Tier B experimental** — not production default ([`WASM_BACKEND_POLICY.md`](./WASM_BACKEND_POLICY.md)).
- `build.sh` fails when `emcc` is missing unless `SKIP_WASM_BUILD=1` — see [`wasm_renderer/ARTIFACTS.md`](./wasm_renderer/ARTIFACTS.md).
- Playwright GPU tests skip on headless CI without a WebGPU adapter; use `WASM_GPU_TESTS=1` on a GPU machine.
- Promotion requires attached benchmark JSON — see [`WASM_PROMOTION_TRACKING.md`](./WASM_PROMOTION_TRACKING.md).
- WASM `getGPUTimings()` reports wall-clock ms only (no GPU timestamp queries).

---

## Reporting Issues

If the WASM renderer behaves differently from the TypeScript WebGPU renderer,
open an issue and include:

1. Browser + version
2. The exact URL used (including query params)
3. The DevTools console output (especially `getDiagnostics()` result)
4. Steps to reproduce
5. Whether the same shader works in the TypeScript WebGPU renderer (`?renderer=webgpu`)
