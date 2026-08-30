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
| `downsample_2d` | 64×64 preview / mip-like thumbs (also thumbnail capture dest size) |
| `auto_exposure` | EV/gain toward middle grey from the histogram |
| `apply_gain_2d` | optional full-res RGB gain onto catalog `readTex` (toggle **off** by default) |

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
- Readback is the 256-bin histogram + 16-byte reduce (~1 KiB) plus an optional 64×64 rgba8 classify map for Dev Tools — not a full-frame pixel dump.

ShaderValidator / ShaderScanner compile-check WGSL on the **same adopted renderer device** (not a second device). Depth estimation prefers WASM/CPU while the canvas renderer is active — see `src/services/depthEstimation/loader.ts`.

## Live pre-FX path

After `encodeInputCopy`, the frame loop runs chores on **raw** `readTex` (so preview is not double-gained):

1. Histogram + reduce (every 8 frames) + downsample + LUT classify.
2. Preview path: EV/gain from the histogram still normalizes the 64×64 preview (`getPreviewTexture()` / CPU `getPreviewRgba()`).
3. **Opt-in source normalize** (Controls → Auto exposure (source), default **off**, `localStorage` `px_source_auto_exposure`): `apply_gain_2d` writes `writeTex` then copies back to `readTex` so catalog shaders sample a mid-grey source. Persistence is host-side only — **not** `extraBuffer`. FFT `[5..132]` and audio `[0..2]` are untouched. Do not stash EV in `[139]` (shader-owned safe zone).
4. Skip source gain when `?no_gpu_compute`, probe failure, WASM backend, or any enabled slot is FP32-pinned (`FP32_REQUIRED_SHADER_IDS` / Jacobi/RD graphs). Preview hist/EV breadcrumbs may still update.
5. Until the first histogram `mapAsync` lands (period 8 frames plus readback), `exposureGain` is identity (`1`). Opt-in source gain is a no-op visually for those frames; that is expected.

When GPU compute is unavailable, image loads ingest a CPU snapshot (`ingestOffscreen` / `ingestRgba`) and the same goldens produce auto-uniforms. CPU analysis does **not** rewrite the catalog source.

WASM: chores stay idle. Do not port `apply_gain_2d` to `frame.cpp` until #1080.

## Dev Tools

Dev Tools shows `gpuComputeAvailable`, backend, last op, reason, auto-exposure EV, and `sourceGain: on|off|skipped-physics`. Optional **LUT classify preview** is a false-color 8-band debug view (`lut_u8_map`), not a picker category.

## Tests

```bash
npx react-scripts test --watchAll=false --ci src/gpuChores/gpuChores.test.ts src/renderer/rendererDiagnostics.test.ts src/services/sourceAutoExposure.test.ts src/components/controls/panels/RenderQualityPanel.test.tsx src/components/controls/panels/AdvancedDebugPanel.test.tsx
```

CPU goldens are the parity SoT on this headless VM (no GPU adapter). GPU pipelines compile only on a real WebGPU device.
