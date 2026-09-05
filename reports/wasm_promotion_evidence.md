# WASM / Pascal real-GPU promotion evidence

**Date:** 2026-09-05  
**Scope:** Six runtime bugs diagnosed and fixed 2026-08-30/31 on Pascal + Chrome/Win10 (`test.1ink.us`). This pass adds **un-regressable gates only**. It does not re-fix the bugs and it does **not** promote `go.1ink.us /pixelocity/`.

**Honesty rule:** This Cloud VM has **no GPU adapter**. Nothing below is GPU-CONFIRMED from this session. Headless Jest, `tsc`, wasm import-table parse, and source scans are not hardware confirmation.

Sources: `memory/2026-08-30.md`, `memory/2026-08-31.md`, and the tree as of this write.

---

## 1. gpu-chores 1D flatten → `DispatchWorkgroups(65536, 1, 1)`

| | |
|---|---|
| **Root cause** | Flattened `ceil(srcW * srcH / 64)` at 2048² is 65536 workgroups on X with Y defaulting to 1. WebGPU `maxComputeWorkgroupsPerDimension` is 65535. Uncaptured `GPUValidationError` every frame (steady black blink). Probe can still succeed. |
| **Fix location** | `src/gpuChores/shaders.ts` `@workgroup_size(8, 8)` 2D kernel; `GpuChoresHost` 2D `workgroups2d` + `assertDispatchWithinLimits` on histogram, reduce, apply-gain, LUT, downsample. |
| **Automated guard** | `src/contracts/wasm_runtime_invariants.json` `maxComputeWorkgroupsPerDimension`; `verify:wasm-invariants` (five `dispatchWorkgroupsSafe` sites); `gpuChores.test.ts` 4K / 2048² / oversized; `dispatchLimits.test.ts` throws on 65536. |
| **Hardware** | **GPU-PENDING** |

## 2. `wgpuSurfacePresent` aborts the emdawn browser stub

| | |
|---|---|
| **Root cause** | `PresentToSurface()` called `wgpuSurfacePresent`. Stub aborts: use requestAnimationFrame via html5.h. JS rAF already drives `updateUniforms` → `Render()`. |
| **Fix location** | `wasm_renderer/device.cpp` — acquire, blit, submit, return. Comment only; no present call. Artifacts rebuilt emcc 6.0.3 (committed). |
| **Automated guard** | C++ call scan (comments stripped); `scripts/wasm_import_table.js` fails if `wgpuSurfacePresent` / `_wgpuSurfacePresent` appears in `public/wasm/pixelocity_wasm.wasm` imports. |
| **Hardware** | **GPU-PENDING** |

## 3. Sampler `maxAnisotropy` 0 → Invalid Sampler

| | |
|---|---|
| **Root cause** | `WGPUSamplerDescriptor samplerDesc = {}` leaves `maxAnisotropy` at 0. Dawn requires ≥ 1 for filtering, non-filtering, **and** comparison samplers. Bind groups using them were rejected. |
| **Fix location** | `wasm_renderer/resources.cpp` — `samplerDesc.maxAnisotropy = 1` once before the three `wgpuDeviceCreateSampler` calls. |
| **Automated guard** | Assignment must exist and precede all three create calls (`requiredSamplerDefaults` in the contract). |
| **Hardware** | **GPU-PENDING** |

## 4. historyTex 2048² × 8 OOM (#1204)

| | |
|---|---|
| **Root cause** | Pascal/Chrome D3D12 `GPUOutOfMemoryError` on `historyTex` ~256–512 MiB. Retrying 2048 or switching to WASM without awaiting `device.lost` OOMs again. |
| **Fix location** | `historyTexProbe.ts` ladder 2048×8 → 1024×8 → 1024×4 → 1024×1; `vramBudget.ts` `px_history_oom_cap`; C++ fail-soft (source only — not rebuilt here). |
| **Automated guard** | Contract `historyTexLadder` matched to TS constants + `HISTORY_PROBE_RUNGS` (4 rungs). |
| **Hardware** | **GPU-PENDING** |

## 5. BGL RGBA32Float vs shader RGBA16Float (#1205)

| | |
|---|---|
| **Root cause** | WASM pipeline layout stayed RGBA32Float while LoadShader rewrote WGSL to RGBA16Float → invalid pipeline submitted every frame. |
| **Fix location** | WASM prefers `rgba16float` after a yes storage probe; `RewriteWgslStorageFormats` at LoadShader. Catalog WGSL stays `rgba32float`. |
| **Automated guard** | `storageFormatRewrite` checks TS rewrite module, C++ rewrite + Rgba16Float probe path. |
| **Hardware** | **GPU-PENDING** |

## 6. JS→WASM switch drops the photo (#1206)

| | |
|---|---|
| **Root cause** | Exclusive switch destroys the JS device that owned the uploaded photo. `setInputSource` is a mode flag; WASM never received pixels. |
| **Fix location** | `rebindMediaAfterBackendSwitch` after successful switch; then `resyncShaderStack`. |
| **Automated guard** | Source presence + `RendererManager` call; Playwright `JS→WASM switch rebinds input` **skips** when `webgpuProbe.ok !== true` (no false pass). |
| **Hardware** | **GPU-PENDING** |

---

## Promote decision

| Host | Status |
|------|--------|
| `test.1ink.us /pixelocity/` | Debug/deploy target for the original session — **not confirmed from this VM** |
| `go.1ink.us /pixelocity/` | **HOLD** — do not promote on headless evidence |

Do not close #1200 / #1204 / #1205 / #1206 from this work.
