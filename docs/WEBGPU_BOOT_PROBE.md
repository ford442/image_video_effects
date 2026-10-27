# WebGPU boot probe

**WebGPU is required this phase.** There is **no WebGL / WebGL2 fallback** and **no automatic Canvas2D recovery** when the adapter/device ladder fails. A silent empty canvas is treated as a product bug; failure is a hard-fail with a diagnostic overlay and a machine-readable breadcrumb.

## Why

Chrome and Edge can disagree on adapter/device support on the same host. Without a structured probe, “black canvas” is indistinguishable from a broken shader. The boot probe turns that into JSON + a canvas-slot overlay.

## Flow

1. Default boot (`WebGPUCanvas`, not `?renderer=js` / `?renderer=wasm`) runs `runWebGpuBootProbe` before `RendererManager.init`.
2. Every ladder rung is recorded; success also smoke-tests canvas configure + a tiny compute pipeline.
3. Result is published to `window.webgpuProbe` (serializable slice only — no GPU handles).
4. On failure: blocking overlay in the **canvas slot only** (gallery/storage stay usable); renderer does not start.
5. On success: live handles are handed off once (`webGpuHandoff`) so `requestDevice` is not called twice.

**Render worker (#1314, default where supported).** The TS backend renders in a dedicated worker on a transferred `OffscreenCanvas`. A `GPUDevice` cannot be transferred, and a canvas that already has a context cannot be transferred either, so in that mode **the probe runs inside the worker** on the `OffscreenCanvas`. It uses the same ladder, the same stages, and color opt-ins resolved by the page. The worker posts the serializable result back; the page publishes it to `window.webgpuProbe` (with `renderThread: 'worker'`) and still owns the overlay. If the worker cannot start, or has no WebGPU, before it takes the canvas, the page renders instead and runs the probe as above. If it fails after taking the canvas, one retry happens on the page with a fresh `<canvas>`. `?renderer=main` skips the worker. See [`RENDER_WORKER.md`](./RENDER_WORKER.md).

**Runtime device loss.** A `GPUDevice` lost after boot (driver reset, GPU process crash) is the only other time the probe runs. `RendererManager` rebuilds the TS backend through its normal webgpu → webgpu switch: it releases the dead backend, and the new backend's `init` runs this same probe and ladder (in the worker on a fresh canvas, or on the page). One attempt runs automatically. If it fails, the overlay shows the new probe result with a **Retry** button. There is no fallback to Canvas2D or WASM, and no `requestAdapter`/`requestDevice` outside the probe. See [Device loss in `RENDER_WORKER.md`](./RENDER_WORKER.md#device-loss).

`?renderer=wasm` (emdawnwebgpu) is still WebGPU ownership. If WASM init fails, the same hard-fail surface applies via `publishWasmProbeFailure` — no soft fall-through to TS WebGPU or Canvas2D.

`?renderer=js` is an **explicit debug opt-in** for Canvas2D (no shaders). It is not used as recovery after a WebGPU probe failure.

## Ladder

Mirrors C++ `ADAPTER_ATTEMPT_LADDER` / `src/renderer/webgpuDevicePolicy.ts`:

1. HighPerformance  
2. Undefined preference  
3. LowPower  
4. Undefined + `forceFallbackAdapter`

Per attempt stages: `requestAdapter` → `contract` → `requestDevice` → `getContext` → `configure` → `probePipeline`.

## `window.webgpuProbe` shape

Typed in `src/types/webgpuProbe.d.ts` / `WebGpuProbeSerializable`:

| Field | Meaning |
|-------|---------|
| `ok` | Probe succeeded |
| `finishedAt` | ISO timestamp |
| `userAgent` | Full UA string |
| `userAgentBrands` | From `navigator.userAgentData.brands` (Chrome vs Edge legibility) |
| `attempts[]` | Full log: label, powerPreference, forceFallbackAdapter, adapterPresent, adapterInfo, limits summaries, error, failedStage |
| `failedStage` / `lastError` | Top-level failure summary |
| `adapterSummary` / `adapterAttemptLabel` | Success (or partial) adapter identity |
| `backend` | `'webgpu'` or `'wasm'` |

GPU handles live only on the internal handoff object and are **stripped** before publish.

## Code map

| Piece | Path |
|-------|------|
| Probe | `src/renderer/webgpuBootProbe.ts` |
| Ladder policy | `src/renderer/webgpuDevicePolicy.ts` |
| Device seam | `src/renderer/webgpu/device.ts` |
| Backend switch / handoff | `src/renderer/backendLifecycle.ts` |
| Facade (no auto JS fallback) | `src/renderer/RendererManager.ts` |
| Overlay | `src/components/WebGpuProbeFailureOverlay.tsx` |
| Mount (canvas slot) | `src/components/WebGPUCanvas.tsx` |

## Related

- Device/bind-group contract: [BINDING_CONTRACT.md](./BINDING_CONTRACT.md)
- Optional features / surface: [DEVICE_FEATURES.md](./DEVICE_FEATURES.md)
- Tier 4b chores adopt the same `GPUDevice`: [GPU_CHORES.md](./GPU_CHORES.md)
