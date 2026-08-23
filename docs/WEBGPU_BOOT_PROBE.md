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
