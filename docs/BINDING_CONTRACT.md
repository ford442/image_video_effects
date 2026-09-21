# Binding Contract — TypeScript + C++ WASM

Single source of truth for the Pixelocity compute bind group layout and device policy.

**Cross-references:**
- TypeScript layout: [`src/renderer/webgpu/pipeline.ts`](../src/renderer/webgpu/pipeline.ts) (`createComputeBindGroupLayout`)
- TypeScript resources: [`src/renderer/webgpu/resources.ts`](../src/renderer/webgpu/resources.ts) (`historyTex`, buffers)
- C++ layout: [`wasm_renderer/pipeline.cpp`](../wasm_renderer/pipeline.cpp) (`CreateBindGroupLayout`)
- Sim ring (group 1, opt-in): [`src/contracts/bind_group1.json`](../src/contracts/bind_group1.json) ↔ [`src/renderer/webgpu/simRing.ts`](../src/renderer/webgpu/simRing.ts) ↔ `GraphRunner.ts` buffer barriers
- Device limits: [`src/contracts/webgpu_limits.json`](../src/contracts/webgpu_limits.json) ↔ [`src/renderer/webgpuDevicePolicy.ts`](../src/renderer/webgpuDevicePolicy.ts) ↔ [`wasm_renderer/device.cpp`](../wasm_renderer/device.cpp)
- Optional features: [`src/contracts/webgpu_optional_features.json`](../src/contracts/webgpu_optional_features.json) ↔ [`collectOptionalDeviceFeatures`](../src/renderer/webgpu/device.ts) ↔ `device.cpp` `requiredFeatures[3]`
- WASM exports: [`src/contracts/wasm_exports.json`](../src/contracts/wasm_exports.json) (build.sh + CMake)
- WGSL authoring: [`agents/WGSL_BUILTINS_GENERATIVE.md`](../agents/WGSL_BUILTINS_GENERATIVE.md)
- Shader **upgrades** (ideas, not hygiene): [`docs/SHADER_UPGRADE_BATCH.md`](SHADER_UPGRADE_BATCH.md)
- Uniforms layout: [`src/contracts/uniforms_layout.json`](../src/contracts/uniforms_layout.json) ↔ [`src/renderer/UniformBuffer.ts`](../src/renderer/UniformBuffer.ts) ↔ [`wasm_renderer/renderer.h`](../wasm_renderer/renderer.h)
- CI sync checks: `npm run verify:device-policy`, `npm run verify:uniforms`
- Pre-FX analysis (not this bind group): [`docs/GPU_CHORES.md`](GPU_CHORES.md) — Tier 4b gpu-chores on the **same** `GPUDevice`
- Boot probe / hard-fail (WebGPU required, no WebGL fallback): [`docs/WEBGPU_BOOT_PROBE.md`](WEBGPU_BOOT_PROBE.md)

**One renderer `GPUDevice`:** the boot probe owns the sole `requestAdapter`/`requestDevice` for catalog rendering, gpu-chores, ShaderValidator, and ShaderScanner. Lazy depth (`@xenova/transformers`) prefers WASM/CPU while that device is live — Transformers may still allocate internally when `device:'webgpu'` is selected.

## Naming

| Term | Meaning |
|------|---------|
| **Core contract** | Bindings **0–12** (13 WGSL declarations) — required by all shaders |
| **Extension** | Binding **13** (`historyTexture` 2d-array) — opt-in temporal shaders (~11 shaders) |
| **Layout size** | **14** bind-group entries (0–13); `maxBindingsPerBindGroup` must be **≥ 14** |
| **Sim ring** | **Group 1** (`simState` / `simIndex` / `simParams`) — opt-in, only for shaders that declare `@group(1)` |

## Bind group layout (group 0)

| Binding | WGSL name | Type | Access |
|---------|-----------|------|--------|
| 0 | `readSampler` | sampler | filtering |
| 1 | `readTexture` | texture_2d\<f32\> | sample |
| 2 | `writeTexture` | texture_storage rgba32float (ultra) / rgba16float (balanced+) | write |
| 3 | `uniforms` | uniform `Uniforms` | read |
| 4 | `readDepthTexture` | texture_2d\<f32\> | sample |
| 5 | `nearestSampler` | sampler | non-filtering |
| 6 | `writeDepthTexture` | texture_storage r32float | write |
| 7 | `dataTextureA` | texture_storage rgba32float (ultra) / rgba16float (balanced+) | write (primary feedback state) |
| 8 | `dataTextureB` | texture_storage rgba32float (ultra) / rgba16float (balanced+) | write (secondary / detail) |
| 9 | `dataTextureC` | texture_2d\<f32\> | sample (previous frame) |

### Feedback copy order (host)

After each chained slot (and after parallel slots as a group), when any enabled shader
samples `dataTextureC`, the host copies storage → sample:

1. **`dataB → dataC`** (if the slot wrote B)
2. **`dataA → dataC`** (if the slot wrote A) — **last**, so A wins when both are written

Shaders that store sim state in A and aux/debug in B therefore read correct state next frame.
Do **not** reverse this order. (Audit 2026-07-21: prior A-then-B order clobbered BZ / liquid-touch / acid-lissajous.)
| 10 | `extraBuffer` | storage array\<f32\> | read_write |
| 11 | `comparisonSampler` | sampler_comparison | compare |
| 12 | `plasmaBuffer` | storage read-only | read |
| 13 | `historyTexture` | texture_2d_array\<f32\> | sample (**opt-in**) |

## Uniforms struct (binding 3)

**Authoritative.** Engine truth lives in [`src/contracts/uniforms_layout.json`](../src/contracts/uniforms_layout.json), mirrored by
[`src/renderer/UniformBuffer.ts`](../src/renderer/UniformBuffer.ts) (`UNIFORM_OFFSETS`) + [`src/renderer/webgpu/frame.ts`](../src/renderer/webgpu/frame.ts) (`writeUniforms`)
and [`wasm_renderer/renderer.h`](../wasm_renderer/renderer.h) + [`wasm_renderer/frame.cpp`](../wasm_renderer/frame.cpp) (`UpdateUniformBuffer`).
Drift is a CI failure: `npm run verify:uniforms`.

```wgsl
struct Uniforms {
  config: vec4<f32>,       // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,  // .xyzw = user params p1..p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};
```

Total size **848 bytes** (212 floats) — matches `UNIFORM_BUFFER_LAYOUT.TOTAL_SIZE` and `maxUniformBufferBindingSize`.

| Field | Byte offset | Meaning | Range / units |
|-------|-------------|---------|---------------|
| `config.x` | 0 | **time** | Seconds since renderer start; monotonic, never resets |
| `config.y` | 4 | **rippleCount** | Number of active ripples, `0..50` as f32 |
| `config.z` | 8 | **resolutionWidth** | Render-target width in pixels (post scaling) |
| `config.w` | 12 | **resolutionHeight** | Render-target height in pixels (post scaling) |
| `zoom_config.x` | 16 | **time** | Same value as `config.x` |
| `zoom_config.y` | 20 | **mouseX** | Canvas UV `0..1`, 0 = left |
| `zoom_config.z` | 24 | **mouseY** | Canvas UV `0..1`, **0 = top** |
| `zoom_config.w` | 28 | **mouseDown** | `1.0` pressed / `0.0` released — test with `> 0.5` |
| `zoom_params.x` | 32 | **p1** | User slider 1 (range per shader JSON `controls`) |
| `zoom_params.y` | 36 | **p2** | User slider 2 |
| `zoom_params.z` | 40 | **p3** | User slider 3 |
| `zoom_params.w` | 44 | **p4** | User slider 4 |
| `ripples[i].x` | 48 + 16·i | ripple UV x | `0..1` |
| `ripples[i].y` | 52 + 16·i | ripple UV y | `0..1`, 0 = top |
| `ripples[i].z` | 56 + 16·i | **startTime** | Seconds, same clock as `config.x` — `age = u.config.x - r.z` |
| `ripples[i].w` | 60 + 16·i | **padding** | Always `0.0` — reserved, *not* a strength value |

### Do-not-reintroduce list

- **`config.y` is `rippleCount`, not delta time.** No per-frame `dt` is uploaded on either backend; drive
  motion from absolute `config.x`. Guard ripple loops with `min(u32(u.config.y), 50u)`.
- **`config.y/z/w` is not audio.** Audio comes from `plasmaBuffer[0].xyz` (bass/mids/treble) and the FFT bins
  in `extraBuffer[5..132]`. Reading audio out of `config` is the recurring dead-audio bug (batches 15–19).
- **`config.y` is not a click count.** Legacy briefs called it `MouseClickCount` / `Generic1`; those were
  already wrong when written. Use `zoom_config.w` for mouse-down state.
- **Mouse Y is top-down** (fixed 2026-07-19). Do not add a `1.0 - y` flip.
- **Ripple slots past `rippleCount` are fully zeroed** — a zero `startTime` means "empty", not "created at t=0".

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

- **Depth:** 8 layers (`HISTORY_DEPTH`) is the **maximum**. Runtime may allocate 8, 4, or 1 after a `historyTex` VRAM probe (#1204). Bind-group `arrayLayerCount` must match the allocated texture. At 1 layer the ring copy is skipped (fail-soft graph history).
- **VRAM:** Default working size is **1024**. 2048² × 8 × rgba32float is ~512 MiB — Pascal/Chrome D3D12 often OOMs, so 2048 is an upgrade only after a discrete + `maxBufferSize >= 1 GiB` + non-Pascal gate and a full-pool allocate. On `GPUOutOfMemoryError` stay at 1024 and **do not retry 2048** this tab. JS→WASM must `device.destroy()` and **await** `device.lost` before the next `requestDevice`.
- **Catalog metadata:** `requiresHistoryRing: true` in shader JSON for temporal effects
- **CPU:** `historyHead` written to `extraBuffer[4]` when any enabled shader uses binding 13
- **GPU:** after each frame, copy presented color into `historyTexture[historyHead]`, then `historyHead = (historyHead + 1) % 8`
- Shaders that sample `@binding(13) var historyTexture` must declare the binding; others omit it
- Copy is gated by static analysis (`analyzeShaderBindings` / C++ `AnalyzeShaderBindings`) — skipped when no shader references binding 13

## Sim ring (group 1, opt-in)

Group 0 is at the contract ceiling. Indexable state that is not a texture (walkers, photon pools, neighbour tables, spatial hashes) lives in a second bind group. Contract: [`src/contracts/bind_group1.json`](../src/contracts/bind_group1.json).

```wgsl
struct SimParams { stateCount: u32, indexCount: u32, frame: u32, truncated: u32 };
@group(1) @binding(0) var<storage, read_write> simState: array<vec4<f32>>;  // particles / photons / walkers
@group(1) @binding(1) var<storage, read>       simIndex: array<u32>;        // snapshot / neighbours / hash
@group(1) @binding(2) var<uniform>             simParams: SimParams;
```

- **Opt-in:** a shader is on the ring iff its WGSL declares `@group(1)` (comments ignored). Its JSON must set `"simRing": true` and vice versa — `verify:device-policy` checks both directions.
- **Zero cost for everyone else:** `createComputeBindGroupLayout` keeps a **single-group** pipeline layout. Only group-1 shaders compile against `createSimRingPipelineLayout` (`[group0, group1]`), and only their dispatches call `setBindGroup(1, …)`. The ring buffers are allocated the first time a group-1 shader compiles.
- **simIndex is read-only in WGSL.** The host fills it with `copyBufferToBuffer(simState → simIndex)` — the buffer mirror of the `dataA → dataC` handoff. GraphRunner inserts the copy before any node listing `simIndex` in `bufferReads` when `simState` was written since the last publish (including **between repeats**), plus one trailing publish so the next frame starts from a snapshot.
- **Graph node fields:** `bufferReads` / `bufferWrites` (`simState`, `simIndex`; only `simState` is writable) and `dispatch: "simState"` for one invocation per live particle (`ceil(stateCount / wg.x) × 1`, `@workgroup_size(64, 1, 1)` — the only 1D `main` size the bindgroup checker accepts, and only in group-1 shaders).
- **VRAM:** default 65 536 × 16 B `simState` + 262 144 × 4 B `simIndex` + 16 B params ≈ **2 MiB** (under 2 % of the 2048² × 8 history ring that OOMs Pascal). Ladder 65 536 → 32 768 → 16 384 → 4 096 particles under an out-of-memory scope; each failure latches `px_simring_oom_cap` in `sessionStorage` and the fat size is never retried this tab. `simParams.truncated = 1` and `GraphRunReport.simRing.truncated` report a shrunk ring.
- **extraBuffer:** ring shaders must not write `extraBuffer[0..132]` — that is exactly what the ring replaces.
- **WASM:** C++ is feature-frozen until #1080. `pipeline.cpp` keeps `bindGroupLayoutCount = 1` (group 1 unbound); the bridge (`shader.ts` `declaresSimRing`) refuses `@group(1)` shaders before `LoadShader`, so the module never builds an invalid pipeline or aborts. Flagship: `dla-crystals`.

### Runtime format tiers (#1008)

WGSL sources remain authored as **rgba32float** canonical. At pipeline compile the host rewrites bindings 2/7/8 for non-ultra tiers. See [`docs/FORMAT_TIERS.md`](FORMAT_TIERS.md).

## Device policy

Both backends validate adapter limits before device creation and request explicit `requiredLimits`.

### Limits table (must match TS ↔ C++)

| Limit | Required | Notes |
|-------|----------|-------|
| `maxTextureDimension2D` | **8192** | Comfortable floor (`webgpu_limits.json`). Never canvas max(w,h), maxBufferSize, pixel count, or a mis-ordered init pointer. |
| `maxBindGroups` | 2 | group 0 + opt-in group-1 sim ring |
| `maxBindingsPerBindGroup` | 14 | 14-entry layout (0–13) |
| `maxSampledTexturesPerShaderStage` | 3 | readTexture, dataTextureC, historyTexture |
| `maxSamplersPerShaderStage` | 3 | filtering, non-filtering, comparison |
| `maxStorageTexturesPerShaderStage` | 4 | write, depth write, data A/B |
| `maxStorageBuffersPerShaderStage` | 4 | extraBuffer, plasmaBuffer + group-1 simState, simIndex (was 2) |
| `maxUniformBuffersPerShaderStage` | 2 | Uniforms + group-1 simParams (was 1) |
| `maxUniformBufferBindingSize` | sizeof(Uniforms) | TS: `UNIFORM_BUFFER_LAYOUT.TOTAL_SIZE` |
| `maxComputeWorkgroupSizeX` | 16 | Standard workgroup |
| `maxComputeWorkgroupSizeY` | 16 | Standard workgroup |
| `maxComputeInvocationsPerWorkgroup` | 256 | Deep-workgroup shaders need ≥ 1024 at runtime |

### Canonical dispatch

The engine's standard 2D compute dispatch is **16×16×1**. When a shader's `@workgroup_size` cannot be parsed, both TypeScript (`parseWorkgroupSize`) and C++ WASM (`ParseWorkgroupSize`) fall back to **16×16** — see [`src/contracts/workgroup_dispatch.json`](../src/contracts/workgroup_dispatch.json). The same contract's `emptyPlaceholder` is **r32float**, **4 bytes/row** for the 1×1 unused-slot texture (TS `emptyTex` / C++ `emptyTexture_`). CI enforces both via `npm run verify:device-policy`.

Documented exceptions in that contract:

- **1D helper kernels** — `@workgroup_size(64, 1, 1)` or `(256, 1, 1)` on non-`main` entry points (e.g. `update_boids` before `main`)
- **Deep-workgroup shaders** — `(16, 16, 4)` with `requiresDeepWorkgroup: true`
- **Sim-ring particle kernels** — `(64, 1, 1)` on `main`, only in shaders that declare `@group(1)` (`simRingParticleSizes`)
- **`src/gpuChores/`** — 8×8 downsample kernels are exempt (not catalog FX)

### Symbol cross-reference

| Concern | TypeScript | C++ WASM |
|---------|------------|----------|
| Adapter ladder | `requestAdapterWithFallback` / `ADAPTER_ATTEMPT_LADDER` | `ADAPTER_ATTEMPT_LADDER` in `device.cpp` |
| Limit validation | `assertAdapterMeetsContract` | `CheckLimit` table in `device.cpp` |
| Device limits | `buildRequiredLimits` | `requiredLimits` on `wgpuAdapterRequestDevice` |
| Feature logging | `logAdapterFeatures` | adapter feature `printf` block |

### Optional features

See [DEVICE_FEATURES.md](./DEVICE_FEATURES.md) for canvas configure and timestamp-honesty details.

| Feature | TypeScript | C++ WASM | Purpose |
|---------|------------|----------|---------|
| `float32-filterable` | Requested when adapter supports | Logged only | rgba32float texture sampling on bindings 1/9/13 |
| `timestamp-query` | Requested when adapter supports; ring-buffered readback in `WebGPUTiming.ts` / `frame.ts` | Requested when available | GPU timing — `available`/`gpu-timestamp` only after valid readback (`hasRealGpuTimings`) |
| `subgroups` | Requested when available (for WGSL `enable subgroups` shaders) | N/A | **Not used** — `-sg.wgsl` file variants were removed 2026-07-26 |

### WASM surface notes

- `compatibleSurface=nullptr` on adapter request is intentional — surface is created separately via `JS_CreateSurfaceFromCanvas` after device creation.
- Canvas format: `navigator.gpu.getPreferredCanvasFormat()` + `alphaMode: opaque` + explicit `usage: GPUTextureUsage.RENDER_ATTACHMENT` on both TS (`buildCanvasConfigureOptions`) and WASM (`JS_CreateSurfaceFromCanvas`) paths (#818).

## Parity checklist

- [x] TS layout entries 0–13
- [x] C++ layout entries 0–13 (Foundation Wave 2)
- [x] `maxBindingsPerBindGroup: 14` in TS + C++
- [x] `historyHead` in `extraBuffer[4]` on both paths
- [x] History/dataTex copies gated by shader binding usage (TS + C++)
- [x] Group-1 sim ring on TS (single-group default layout unchanged)
- [ ] Group-1 sim ring on C++ — documented unbound; bridge refuses `@group(1)` shaders until the #1080-gated port
