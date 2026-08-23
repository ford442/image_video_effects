# gpu-chores (Tier 4b) — shared analysis / pre-FX

Everyday **pre-FX** work (luminance histogram, reduce, LUT classify, downsample) lives here so auto-params, exposure, and thumbs do not each invent device + bind-group + fallback plumbing.

Domain visual effects (god-rays, multipass psychedelia, simulation, the 1000+ catalog WGSL modules) stay **app-local**. That is **Tier 4a**. This kit does not swallow them.

| Tier | What | Where |
|------|------|--------|
| **4a** | Domain FX compute | `public/shaders/*.wgsl`, GraphRunner, slot dispatch |
| **4b** | gpu-chores analysis / pre-FX | [`src/gpuChores/`](../src/gpuChores/) |

Parent rollout: Pixelocity is Tier A of a cross-app chores layer (siblings: Chromashift extract source, clip_stacker, flac_player, mod-player, web_sequencer).

## Ops

| Op | Role |
|----|------|
| `luma_histogram_bt709` | 256-bin atomic histogram (BT.709 luma; Chromashift-shaped) |
| `reduce_f32` | min / max / mean luma (auto-uniforms) |
| `lut_u8_map` | 8-band luma classification LUT |
| `downsample_2d` | 64×64 preview / mip-like thumbs |
| `auto_exposure` | gain toward middle grey **applied to the preview**, not catalog FX |

WGSL for chores is **inline** in [`src/gpuChores/shaders.ts`](../src/gpuChores/shaders.ts). Do **not** register these in `shader_definitions/` or they will appear in the picker.

Workgroups: `@workgroup_size(64)` 1D reduce; `@workgroup_size(8, 8)` 2D image.

## Device policy

- **Single device:** `GpuChoresHost.attach(rendererDevice)` only. No `requestAdapter()` / `requestDevice()`.
- **Boot probe gate:** chores run only when `window.webgpuProbe.ok === true` (adopt probed device). Probe failure = idle — no silent CPU pre-FX feeding catalog FX.
- **Shader tools:** `ShaderValidator` and `ShaderScanner` adopt the same boot-probe `GPUDevice` via the adopted-device registry — never `requestAdapter()` / `requestDevice()`.
- **Depth estimation:** while the canvas WebGPU renderer is live, prefer WASM/CPU for `@xenova/transformers` depth (it may allocate its own `GPUDevice` when `device:'webgpu'`).
- **No dual-hot WebGL + WebGPU** on the same working set. WebGL2 FBO kernels are later, not required here.
- Backend order: **WebGPU (adopted) → existing WASM/C++ analysis (none yet) → TS** (`?no_gpu_compute` only when probe succeeded).
- Kill switch: `?no_gpu_compute` (also `=1` / `=true`). Forces TS.
- Readback is the 256-bin histogram + 16-byte reduce (~1 KiB), not a full-frame pixel dump.

ShaderValidator / ShaderScanner compile-check WGSL on the **same adopted renderer device** (not a second device). Depth estimation prefers WASM/CPU while the canvas renderer is active — see `src/services/depthEstimation/loader.ts`.

## Live pre-FX path

After `encodeInputCopy`, the frame loop runs chores on `readTex`:

1. Histogram + reduce (every 8 frames) + downsample + LUT classify.
2. Auto-exposure EV/gain from the histogram **normalizes the 64×64 preview** (`getPreviewTexture()` / CPU `getPreviewRgba()`).
3. Catalog shaders are unchanged. `extraBuffer` / FFT slots are not used.

When GPU compute is unavailable, image loads ingest a CPU snapshot (`ingestOffscreen` / `ingestRgba`) and the same goldens produce auto-uniforms.

## Breadcrumbs

Dev Tools shows `gpuComputeAvailable`, backend, last op, reason, and auto-exposure EV. Source: `WebGPURenderer.getGpuChoresBreadcrumbs()`.

## Tests

```bash
npx react-scripts test --watchAll=false --ci src/gpuChores/gpuChores.test.ts src/renderer/rendererDiagnostics.test.ts
```

CPU goldens are the parity SoT on this headless VM (no GPU adapter). GPU pipelines compile only on a real WebGPU device.
