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

## Deferred

- **Wide gamut:** `colorSpace: 'display-p3'` — separate ticket; not requested at device init today.
