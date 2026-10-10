# Render worker (#1314)

The TS WebGPU renderer runs **off the main thread** by default. React, pointer
events, sliders, the shader gallery and audio analysis stay on the page; the
renderer, its only `GPUDevice`, the frame loop, Tier C graphs, gpu-chores and
the timestamp profiler live in a dedicated worker that owns the canvas through
`transferControlToOffscreen()`.

| URL | Where the TS backend renders |
|-----|------------------------------|
| *(default)* / `?renderer=webgpu` | Render worker when the browser supports it (Worker + OffscreenCanvas + canvas transfer + WebGPU, then WebGPU confirmed inside the worker); otherwise the page |
| `?renderer=worker` | Render worker (no automatic fallback to the page after the worker took the canvas, except the one retry below) |
| `?renderer=main` | The page (escape hatch; deterministic pixel diffs; ShaderValidator-style tooling) |
| `?renderer=wasm` / `?renderer=js` | Unchanged; never in the worker |

## Pieces

- `src/renderer/worker/protocol.ts` — typed messages: `RenderCommand` (fire-and-forget), `RenderRpc` (request/reply with `requestId`), `RenderEvent` (worker → page). The `*_TYPES` lists are checked against the unions at compile time and against the host's handler tables in `renderWorker.test.ts`.
- `src/renderer/worker/renderWorkerHost.ts` — worker side. Runs the boot probe on the transferred canvas, owns `WebGPURenderer`, applies commands, answers RPCs, posts a state snapshot ~4×/s, forwards `reportError` and uncaptured GPU errors.
- `src/renderer/worker/render.worker.ts` — the worker entry (chunk `render-worker`, lazy; `scripts/check-bundle-size.mjs` keeps it out of `main.js`). Relative fetches resolve against the app root.
- `src/renderer/worker/WorkerWebGPUBackend.ts` — page side. Same surface as `WebGPURenderer` (`WebGPUBackendApi`), so `RendererManager`, hooks and `App` are unchanged.

## Data flow

- **Input.** Mouse, mouse-down, slot params, audio bands + FFT bins and ripples are coalesced into **one `frameInput` message per page animation frame**. Ripple start times are stamped by the worker's clock.
- **Video.** A `VideoFramePump` (WebCodecs, `requestVideoFrameCallback`) on the page's single hidden `<video>` produces `VideoFrame`s that are **transferred** to the worker. The worker keeps the newest (drop-oldest, depth 2), imports it as an external texture inside the frame's single submit, and closes it after submit. File, webcam, HLS and Bilibili all play through that element.
- **Images.** Decoded on the page and transferred as `ImageBitmap`s.
- **Getters.** Synchronous getters (`getFPS`, `getGPUTimings`, pass timings, frame stats, video stats, node scales, …) read the latest snapshot; slot state and params come from an optimistic local shadow.
- **Capture.** The page cannot read a transferred canvas. `refreshFrameImage` / screenshots / `__pixelocity__.captureCanvasStats` use the `captureFrame` RPC: the worker takes a `VideoFrame` of the next presented frame **in the same task as its submit** (no COPY_SRC needed) and returns a PNG.
- **Recording.** GPU encode (WebCodecs) uses a `worker` frame source: each tick asks the worker for the next presented frame (`grabVideoFrame`) and encodes the transferred `VideoFrame` on the page. MediaRecorder still records `canvas.captureStream()` of the placeholder canvas.
- **Thumbnails.** The `captureThumbnail` RPC (gpu-chores downsample of the presented texture).
- **Dev tools.** `ShaderScanner` compiles through `utils/shaderCompileService.ts`: the page device, or the worker's device over the `compileCheck` RPC.

## Backend switches

A canvas is bound to its first context type, and a transferred canvas belongs to the worker for good. `WebGPUCanvas` therefore offers `acquireFreshCanvas()` (a keyed remount of `<canvas>`), and `RendererManager.switchRenderer` starts on a fresh canvas whenever the backend **type** changes or the current canvas was transferred. Worker → Canvas2D → WebGPU → WASM → WebGPU is covered by `tests/engine2.swiftshader.spec.ts`.

## Device loss

A runtime `GPUDevice` loss is recovered without a page reload. The flow is the same on the page and in the worker.

1. **Detect.** `attachDeviceLostHandler` (`webgpu/device.ts`) ignores every `'destroyed'` loss without touching the context: only the owner destroys, and its teardown already unconfigured. On a real loss it reports `device-lost` with `recoverable: true`. `WebGPURenderer` stops its frame loop, detaches gpu-chores and calls its fatal handler once with `DeviceLossInfo`.
2. **Worker.** The host posts a final snapshot (`initialized: false`), then a `deviceLost` event, and stops its snapshot timer. After that it drops commands, renderer RPCs return empty results (`compileCheck` rejects with `render device lost`), and only `dispose` reaches the lost renderer. A second `init` in the same worker is refused. The page proxy (`WorkerWebGPUBackend`) stops sending input and video frames. A late snapshot cannot set `initialized` back to true, and once the client is shut down every event from the old worker is ignored.
3. **Recover.** The lost backend has already cleared the device registry (`deviceRegistry.ts`). `DeviceRecoveryController` (`deviceRecovery.ts`) moves `lost → recovering` and runs one automatic attempt. The attempt is `switchRenderer('webgpu', { restoreOnFailure: false })`:
   - The dead backend is released. In worker mode that means `dispose` + terminate, then a fresh `<canvas>` and a **new worker**.
   - The new backend's `init` reruns the boot probe, then publishes its device (a new registry generation).
   - The lost backend's own slot state is replayed (shader per slot, enabled, chained/parallel), with each shader loaded from the URL it was originally loaded from. Slot params come from the host's `getSessionState()`, and the manager's last input source is reused. So is the CPU-side still (read *before* the release) or else the last image URL. The `<video>` element re-attaches on the next page frame.
4. **Fail.** If the attempt fails, the state goes to `failed`. `WebGPUCanvas` shows `WebGpuProbeFailureOverlay` with the new probe diagnostics and a **Retry** button (`recoverFromDeviceLoss()`). A second loss within 30 s of a recovery skips the automatic attempt and goes straight to `failed`.

Not replayed: depth map, source auto-exposure, node scales, ripples. Quality, resolution scale and pass budgets come back through the manager's performance policy, as on any backend switch.

A worker **crash** recovers the same way (#1395). An `error` event on the Worker after the handshake marks the client dead: pending RPCs reject and sends are dropped. `renderWorkerClient` then notifies `onDied`. `WorkerWebGPUBackend` stops like a loss (`initialized = false`, registry cleared, compile service unregistered) and fires the fatal handler once with `kind: 'worker-died'`. `RendererManager` hands that to the same `DeviceRecoveryController`, so the new worker replays the page-side slot shadow. Nothing is asked of the dead worker. `messageerror` is not treated as a crash.

Status is reported in `getDiagnostics().deviceRecovery` and `__pixelocity__.getDeviceRecoveryStatus()`. `getDiagnostics().liveGpuDevices` (page + current worker) is back to 1 after a recovery. Test-mode hooks:
- `__pixelocity__.simulateDeviceLoss()` destroys the live device and reports it as a loss (`reason: 'simulated'`).
- `__pixelocity__.simulateWorkerCrash()` (worker mode) throws an uncaught error in the worker.

`tests/engine2-device-loss.swiftshader.spec.ts` runs the loss in both threads, the worker crash, and a failed attempt followed by Retry.

## Not in the worker

- `?renderer=wasm` (C++ / emdawnwebgpu; frozen, see `WASM_BACKEND_POLICY.md`) and `?renderer=js`.
- Depth estimation (transformers) stays on the page. `RendererManager.isGpuDeviceActive()` reports the worker's device through the registry (and stays true while a lost one is rebuilt), so it keeps using the CPU/WASM backend instead of creating a second `GPUDevice`.

## Cross-origin isolation and the SharedArrayBuffer ring

Production (`build.sh` → `.htaccess`), `npm start` (`craco.config.js` devServer) and `scripts/serve-isolated.mjs` send:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless
```

`credentialless` rather than `require-corp` keeps no-cors cross-origin images (gallery thumbnails on storage.noahcohn.com, test.1ink.us, Shadertoy) loading without CORP headers on those hosts. `storage_manager` also sends `Cross-Origin-Resource-Policy: cross-origin` for pages that use `require-corp`.

When both the page and the worker report `crossOriginIsolated`, input bypasses messages. `src/renderer/worker/inputRing.ts` is a 4 KiB `SharedArrayBuffer` with one writer (the page) and one reader (the worker's frame loop, drained right before each frame is encoded):

- **State block** (mouse, mouse-down, audio, 128 FFT bins, 6 × slot params) behind a seqlock. A torn read retries 3× and otherwise keeps last frame's input; dirty slots are retried next frame.
- **Slot params** carry a dirty bitmask (`Atomics.or` / `Atomics.exchange`), so only changed slots are applied.
- **Ripples** use an SPSC ring of 64. When full, new ripples are dropped. A clear generation discards ripples queued before the clear.

Otherwise (Safari, which ignores `credentialless`; hosts without the headers) input is coalesced into one `frameInput` message per animation frame. Diagnostics report `inputChannel: 'sab' | 'postMessage'` and `crossOriginIsolated`.

Side effects of isolation:
- `window.open('?mode=remote')` is same-origin, so it keeps its opener.
- There are no iframes.
- Media already loads with CORS.
- ONNX Runtime (depth model, CLIP search) is pinned to `numThreads = 1` so isolation does not silently switch it to the threaded wasm build.

## Testing

- Jest: `src/renderer/worker/renderWorker.test.ts` (protocol contract, host ↔ client over an in-memory port with a fake renderer, proxy coalescing and getters, device loss and stale worker messages). Recovery sequencing: `src/renderer/deviceRecovery.test.ts`, `src/__tests__/RendererManager.test.ts`.
- Real (software) device: `npm run test:engine2` (`swiftshader` Playwright project). The core tests run with `?renderer=main` and with `?renderer=worker`. `npm run test:engine2:isolated` runs the same suite cross-origin isolated (SAB channel). `tests/engine2-isolation.swiftshader.spec.ts` checks the SAB path end to end. `npm run test:engine2:smoke` runs the renderer smoke + layer-chain specs on SwiftShader in both modes (`PX_RENDER_THREAD=main|worker`).
- Real-GPU gate (not runnable on the Cloud VM): main-thread idle trace during a 6-slot 1080p stack, 4K30 HLS throughput, hardware pixel diffs.
