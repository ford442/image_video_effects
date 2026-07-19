# Binding Contract — TypeScript + C++ WASM

Single source of truth for the Pixelocity compute bind group layout.

**Cross-references:**
- TypeScript layout: [`src/renderer/webgpu/WebGPUResourceManager.ts`](../src/renderer/webgpu/WebGPUResourceManager.ts) (`createComputeBindGroupLayout`)
- C++ layout: [`wasm_renderer/pipeline.cpp`](../wasm_renderer/pipeline.cpp) (`CreateBindGroupLayout`)
- Device limits: [`src/renderer/webgpuDevicePolicy.ts`](../src/renderer/webgpuDevicePolicy.ts) ↔ [`wasm_renderer/device.cpp`](../wasm_renderer/device.cpp)
- WGSL authoring: [`agents/WGSL_BUILTINS_GENERATIVE.md`](../agents/WGSL_BUILTINS_GENERATIVE.md)

## Naming

| Term | Meaning |
|------|---------|
| **Core contract** | Bindings **0–12** (13 entries) — required by all shaders |
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
| 4 | **historyHead** — ring write pointer (u32 as f32) |
| 5..132 | FFT bins (128), normalized 0–1 |

## History ring (binding 13)

- **Depth:** 8 layers (`HISTORY_DEPTH`)
- **CPU:** `historyHead` written to `extraBuffer[4]` each frame
- **GPU:** after each frame, copy presented color into `historyTexture[historyHead]`, then `historyHead = (historyHead + 1) % 8`
- Shaders that sample `@binding(13) var historyTexture` must declare the binding; others omit it

## Parity checklist

- [x] TS layout entries 0–13
- [x] C++ layout entries 0–13 (Foundation Wave 2)
- [x] `maxBindingsPerBindGroup: 14` in TS + C++
- [x] `historyHead` in `extraBuffer[4]` on both paths
