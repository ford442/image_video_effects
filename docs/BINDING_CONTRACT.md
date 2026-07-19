# Binding Contract — TypeScript + C++ WASM

Single source of truth for the Pixelocity compute bind group layout and device policy.

**Cross-references:**
- TypeScript layout: [`src/renderer/webgpu/pipeline.ts`](../src/renderer/webgpu/pipeline.ts) (`createComputeBindGroupLayout`)
- TypeScript resources: [`src/renderer/webgpu/resources.ts`](../src/renderer/webgpu/resources.ts) (`historyTex`, buffers)
- C++ layout: [`wasm_renderer/pipeline.cpp`](../wasm_renderer/pipeline.cpp) (`CreateBindGroupLayout`)
- Device limits: [`contracts/webgpu_limits.json`](../contracts/webgpu_limits.json) ↔ [`src/renderer/webgpuDevicePolicy.ts`](../src/renderer/webgpuDevicePolicy.ts) ↔ [`wasm_renderer/device.cpp`](../wasm_renderer/device.cpp)
- WGSL authoring: [`agents/WGSL_BUILTINS_GENERATIVE.md`](../agents/WGSL_BUILTINS_GENERATIVE.md)
- CI sync check: `npm run verify:device-policy`

## Naming

| Term | Meaning |
|------|---------|
| **Core contract** | Bindings **0–12** (13 WGSL declarations) — required by all shaders |
| **Extension** | Binding **13** (`historyTexture` 2d-array) — opt-in temporal shaders (~11 shaders) |
| **Layout size** | **14** bind-group entries (0–13); `maxBindingsPerBindGroup` must be **≥ 14** |

## Bind group layout (group 0)

| Binding | WGSL name | Type | Access |
|---------|-----------|------|--------|
| 0 | `readSampler` | sampler | filtering |
| 1 | `readTexture` | texture_2d\<f32\> | sample |
| 2 | `writeTexture` | texture_storage rgba32float | write |
| 3 | `uniforms` | uniform `Uniforms` | read |
| 4 | `readDepthTexture` | texture_2d\<f32\> | sample |
| 5 | `nearestSampler` | sampler | non-filtering |
| 6 | `writeDepthTexture` | texture_storage r32float | write |
| 7 | `dataTextureA` | texture_storage rgba32float | write |
| 8 | `dataTextureB` | texture_storage rgba32float | write |
| 9 | `dataTextureC` | texture_2d\<f32\> | sample (previous frame) |
| 10 | `extraBuffer` | storage array\<f32\> | read_write |
| 11 | `comparisonSampler` | sampler_comparison | compare |
| 12 | `plasmaBuffer` | storage read-only | read |
| 13 | `historyTexture` | texture_2d_array\<f32\> | sample (**opt-in**) |

## extraBuffer packing (binding 10)

| Index | Field |
|-------|-------|
| 0 | bass (0–1) |
| 1 | mid (0–1) |
| 2 | treble (0–1) |
| 3 | reserved |
| 4 | **historyHead** — ring write pointer (u32 as f32); written only when history ring is active |
| 5..132 | FFT bins (128), normalized 0–1 |

## History ring (binding 13)

- **Depth:** 8 layers (`HISTORY_DEPTH`)
- **Catalog metadata:** `requiresHistoryRing: true` in shader JSON for temporal effects
- **CPU:** `historyHead` written to `extraBuffer[4]` when any enabled shader uses binding 13
- **GPU:** after each frame, copy presented color into `historyTexture[historyHead]`, then `historyHead = (historyHead + 1) % 8`
- Shaders that sample `@binding(13) var historyTexture` must declare the binding; others omit it
- Copy is gated by static analysis (`analyzeShaderBindings` / C++ `AnalyzeShaderBindings`) — skipped when no shader references binding 13

## Device policy

Both backends validate adapter limits before device creation and request explicit `requiredLimits`.

### Limits table (must match TS ↔ C++)

| Limit | Required | Notes |
|-------|----------|-------|
| `maxTextureDimension2D` | canvas max(w, h) | Scales with canvas |
| `maxBindingsPerBindGroup` | 14 | 14-entry layout (0–13) |
| `maxSampledTexturesPerShaderStage` | 3 | readTexture, dataTextureC, historyTexture |
| `maxSamplersPerShaderStage` | 3 | filtering, non-filtering, comparison |
| `maxStorageTexturesPerShaderStage` | 4 | write, depth write, data A/B |
| `maxStorageBuffersPerShaderStage` | 2 | extraBuffer, plasmaBuffer |
| `maxUniformBuffersPerShaderStage` | 1 | Uniforms |
| `maxUniformBufferBindingSize` | sizeof(Uniforms) | TS: `UNIFORM_BUFFER_LAYOUT.TOTAL_SIZE` |
| `maxComputeWorkgroupSizeX` | 16 | Standard workgroup |
| `maxComputeWorkgroupSizeY` | 16 | Standard workgroup |
| `maxComputeInvocationsPerWorkgroup` | 256 | Deep-workgroup shaders need ≥ 1024 at runtime |

### Symbol cross-reference

| Concern | TypeScript | C++ WASM |
|---------|------------|----------|
| Adapter ladder | `requestAdapterWithFallback` / `ADAPTER_ATTEMPT_LADDER` | `ADAPTER_ATTEMPT_LADDER` in `device.cpp` |
| Limit validation | `assertAdapterMeetsContract` | `CheckLimit` table in `device.cpp` |
| Device limits | `buildRequiredLimits` | `requiredLimits` on `wgpuAdapterRequestDevice` |
| Feature logging | `logAdapterFeatures` | adapter feature `printf` block |

### Optional features

| Feature | TypeScript | C++ WASM | Purpose |
|---------|------------|----------|---------|
| `float32-filterable` | Requested when adapter supports | Logged only | rgba32float texture sampling on bindings 1/9/13 |
| `timestamp-query` | Not requested | Requested when available | GPU timing in WASM path |
| `subgroups` | Requested when available | N/A | `-sg.wgsl` variants |

### WASM surface notes

- `compatibleSurface=nullptr` on adapter request is intentional — surface is created separately via `JS_CreateSurfaceFromCanvas` after device creation.
- Canvas format: preferred format + `alphaMode: opaque` (#818 path).

## Parity checklist

- [x] TS layout entries 0–13
- [x] C++ layout entries 0–13 (Foundation Wave 2)
- [x] `maxBindingsPerBindGroup: 14` in TS + C++
- [x] `historyHead` in `extraBuffer[4]` on both paths
- [x] History/dataTex copies gated by shader binding usage (TS + C++)
