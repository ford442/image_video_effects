# Device Features & Canvas Configuration

Cross-reference for optional WebGPU features and canvas setup parity between the TypeScript renderer (`src/renderer/webgpu/device.ts`) and the C++ WASM path (`wasm_renderer/device.cpp`). See also the bind-group layout in [BINDING_CONTRACT.md](./BINDING_CONTRACT.md).

## Boot probe

Before the production renderer starts, `runWebGpuBootProbe()` walks the adapter ladder, configures the swapchain, and compiles a minimal compute pipeline. Results are published to **`window.webgpuProbe`** (serializable JSON: attempts, `userAgentBrands`, `failedStage`). Failed probe → blocking canvas UI; no automatic Canvas2D fallback. See [`src/renderer/webgpuBootProbe.ts`](../src/renderer/webgpuBootProbe.ts).

## Optional features

| Feature | TypeScript | C++ WASM | Purpose |
|---------|------------|----------|---------|
| `float32-filterable` | Requested when adapter supports | Requested when adapter supports | rgba32float texture sampling on bindings 1/9/13 |
| `timestamp-query` | Requested when adapter supports (always-on) | Requested when available | GPU frame timing via `WebGPUTiming.ts` / `timing.cpp` |
| `subgroups` | Requested when available | Requested when adapter + emdawn headers support | WGSL `enable subgroups` shaders |
| `chromium-experimental-subgroups` | Fallback when `subgroups` absent | Fallback when headers define the enum | Chromium pre-standard subgroup path |

Feature collection lives in `collectOptionalDeviceFeatures()` — order is `float32-filterable` → `timestamp-query` → subgroup variant. C++ `requiredFeatures[3]` uses the same order (`src/contracts/webgpu_optional_features.json`, enforced by `verify:device-policy`).

### Timestamp honesty (#1007 / #1030)

`getGPUTimings().available === true` and `timingSource === 'gpu-timestamp'` only after a successful async readback sets `hasRealGpuTimings`. Feature presence alone is insufficient; wall-clock fallback applies until real GPU durations are decoded.

## Canvas configure contract

Source of truth: [`src/contracts/canvas_configure.json`](../src/contracts/canvas_configure.json). `npm run verify:device-policy` asserts that `buildCanvasConfigureOptions()` (TS), the `ctx.configure` in `JS_CreateSurfaceFromCanvas`, and `ConfigureSurface()` (C++) all match it — `alphaMode`, `usage`, preferred format, `presentModeWasm = fifo`, explicit width/height, and that `ConfigureSurface()` is still called after surface import.

| Key | Default (v1) | Owner |
|-----|--------------|-------|
| `alphaMode` | `opaque` | TS + JS configure + C++ |
| `usage` | `RENDER_ATTACHMENT` | TS + JS configure + C++ |
| `format` | `getPreferredCanvasFormat()` | TS + JS configure (C++ mirrors via `JS_GetPreferredCanvasFormat`) |
| `presentModeWasm` | `fifo` | C++ `ConfigureSurface()` only — TS never sets a presentMode |
| `colorSpace` | `srgb` (browser default, not written) | opt-in only, TS-first |
| `toneMapping` | `standard` (browser default, not written) | opt-in only, TS-first |

Both paths negotiate the swapchain via the browser's preferred format:

```typescript
context.configure({
  device,
  format: navigator.gpu.getPreferredCanvasFormat(), // typically bgra8unorm or rgba8unorm
  alphaMode: 'opaque',
  usage: GPUTextureUsage.RENDER_ATTACHMENT,
});
```

WASM equivalent: `JS_CreateSurfaceFromCanvas` in `device.cpp` (same `alphaMode`, `usage`, and `getPreferredCanvasFormat()`).

That JS `ctx.configure` is **not** the only configure. Immediately after `importJsSurface`, C++ `ConfigureSurface()` runs a second configure with `presentMode = Fifo` and the canvas width/height. Both are required: the JS pass matches TypeScript and lets emdawn import the surface; the C++ pass sizes the swapchain. Do not delete the C++ call as a “simplification” — present can stay black.

### Present pipeline

Internal compute targets **rgba32float** (or policy-selected internal format). The final blit pass copies to the canvas swapchain texture obtained from `context.getCurrentTexture()`. The canvas format is **not** rgba32float — it is whatever `getPreferredCanvasFormat()` returns.

Diagnostics: `adapterSummary` includes `surfaceFormat=<format>` and `features=[...]` after device creation for TS/WASM parity reports.

gpu-chores (Tier 4b) **adopt** this device — they never call `requestDevice()`. See [GPU_CHORES.md](GPU_CHORES.md).

### Opt-in: `COPY_SRC` swapchain

After the default configure, `runWebGpuBootProbe()` calls `probeCanvasCopySrc()`: it configures `RENDER_ATTACHMENT | COPY_SRC` inside a `validation` error scope (and checks `getConfiguration().usage` where available), records the result, then **restores the render-only configure**. The flag is published as:

- `window.webgpuProbe.canvasCopySrc: boolean`
- `WebGpuProbeHandoff.canvasCopySrc` (plus `canvasColorOptIns` so callers can rebuild the exact live config)
- `adapterSummary … | canvas: copySrc=yes|no colorSpace=…`

Rejection is fail-soft — it never fails the ladder rung. `encodePresent` (TS) and `PresentToSurface` (C++) remain blit-to-swapchain. Capture code (WebCodecs / lossless PNG) reconfigures with `buildCanvasConfigureOptions(device, format, { ...canvasColorOptIns, copySrc: true })` only when the flag is true; it does not create a second device. C++ `COPY_SRC` is a parity follow-up (WASM feature freeze until #1080).

### Opt-in: Display P3 / extended tone mapping (default off)

- `?display_p3=1` requests `colorSpace: 'display-p3'`. It is **never** requested at boot by default (Pascal-era GPUs, cheap panels, screenshot mismatch).
- `toneMapping: { mode: 'extended' }` is only tried behind the same opt-in **and** when `matchMedia('(dynamic-range: high)')` matches. Format stays `getPreferredCanvasFormat()`.
- Ladder: p3+extended → p3+standard → default srgb. A configure throw, a validation-scope error, or a `getConfiguration()` readback that doesn't match counts as rejected.
- Applied values: `window.webgpuProbe.canvasColorSpace` / `canvasToneMapping`.
- TS-first; the WASM path stays srgb/standard. A Controls → Render quality → **Display P3** toggle is a follow-up (needs a live reconfigure).

## Deferred

- **C++ canvas parity:** `COPY_SRC` / `colorSpace` on `JS_CreateSurfaceFromCanvas` + `ConfigureSurface()` — after #1080.
- **Controls toggle** for Display P3 (URL opt-in only today).
