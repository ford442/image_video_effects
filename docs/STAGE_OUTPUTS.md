# Stage outputs: projector windows and corner pin

First slice of the "leave the tab" plan: **output graph (Part A) + four-corner pin (the
corner-pin part of Part B)**. A stage is a second browser window, fullscreen on a
projector or LED wall, showing the program picture with a per-output corner pin,
colour trim and calibration test patterns. It renders from the **same `GPUDevice`**
as the control window: no second device, no readback.

```
 control window                                      stage window (?mode=stage&output=stage-1)
 ┌──────────────────────────────┐   postMessage      ┌────────────────────────────┐
 │ 📽 Stage panel               │ ◄── hello ───────── │ <canvas> (no React)        │
 │  StageController             │ ── request-canvas ►│ transferControlToOffscreen │
 │                              │ ◄── canvas ──────── │  (OffscreenCanvas moved)   │
 │  RendererManager             │ ◄── resize / key ── │ F: fullscreen · keys       │
 │   └ attachOutput(canvas) ────┼──► render worker (or the page) owns the device   │
 └──────────────────────────────┘      frame: …slots → blitReadTex → main present  │
                                              → one corner-pin pass per output ───►┘
```

## Using it

1. Header → **📽 Stage** → **Open stage window**. With the Window Management API
   (Chromium, permission prompt) **Find displays** lists the screens and the window
   opens on the one you pick. Without it, drag the window to the projector.
2. In the stage window press **F** (or double-click) for fullscreen.
3. Drag the four corners in the panel, or calibrate from the stage itself:
   **1–4 / Tab** select a corner, **arrows** move it one output pixel (**Shift** ×10,
   **Alt** ×¼), **T** cycles test patterns (grid, crosshatch, bars, white), **O** toggles
   the outline. **Identify** flashes the output's name on its stage.
4. Gain / gamma / black level trim each output. Calibrations can be saved by name and
   loaded into any output.

The last config of each output id is saved (`localStorage`, `pixelocity.stageOutputs.v1`)
and restored when a stage with that id opens again, so a calibration survives a reload.
Named calibrations live under `pixelocity.outputCalibrations.v1`.

## Pieces

| File | Role |
|---|---|
| `src/output/homography.ts` | Square → quad projective map (Heckbert), inverse, convexity check |
| `src/output/outputConfig.ts` | `OutputConfig` (corners, test pattern, outline, colour), sanitiser, uniform packing |
| `public/shaders/_output/corner_pin.wgsl` | Present pass per output: inverse pin, manual bilinear (rgba32float is unfilterable), patterns in program space, colour, sRGB encode |
| `src/renderer/webgpu/outputs.ts` | `OutputPresenter`: one `GPUCanvasContext` per output on the renderer's device, one pipeline per swapchain format, cached bind group, dirty-only uniform writes |
| `src/renderer/WebGPURenderer.ts` | `attachOutput / detachOutput / setOutputConfig / setOutputSize / getOutputStatus`; frame hook `encodeOutputs` |
| `src/renderer/worker/protocol.ts` | `attachOutput` RPC (transfers the canvas), `detachOutput` / `setOutputConfig` / `setOutputSize` commands, `snapshot.outputs` |
| `src/output/stageProtocol.ts` | Control ↔ stage window messages and their parsers |
| `src/output/stagePage.ts` | The stage window (mounted by `index.tsx` for `?mode=stage`) |
| `src/output/stageController.ts` | Opens / places stages, attaches canvases, forwards edits, re-attaches after backend switches |
| `src/components/output/StageOutputPanel.tsx` | Calibration UI (lazy chunk `stage-outputs`) |

## Frame plan

The program is rendered once. After the main canvas present, `frame.ts` calls
`state.encodeOutputs(encoder)`: every attached output acquires its own swapchain texture
and runs one full-screen pass that reads `blitReadTex` (the texture the main blit reads).
It is in the frame's single encoder and single submit. Direct present (#1512) is off while
any output is attached (`directPresentBlocker` → `'outputs'`), because then the slot writes
the swapchain and `blitReadTex` is not the final picture.

Outputs are SDR sRGB, `alphaMode: 'opaque'`, in `navigator.gpu.getPreferredCanvasFormat()`.
The control window's Display P3 / HDR negotiation is unaffected.

## Lifecycle

- **Attach.** The stage sends `hello`; the controller answers `request-canvas`; the stage
  makes a fresh `<canvas>` at its device-pixel size, transfers it and sends `canvas`; the
  controller calls `attachOutput` on the current backend (worker: the canvas is
  transferred again, into the worker).
- **Backend switch / device-loss recovery.** A transferred canvas belongs to the thread it
  went to, and a recovered worker is a new thread. `RendererManager.onBackendReady` fires
  after every successful switch (after the session replay); the controller asks every open
  stage for a fresh canvas. The calibration lives in the control window, so it comes back
  unchanged.
- **Close.** The stage sends `bye` on `pagehide`; the controller also polls `win.closed`.
  Either detaches the output (unconfigure).

## Verified

- Unit: homography round-trips, uniform layout vs. the WGSL struct, naga validation of
  `corner_pin.wgsl`, presenter (passes per output, caching, detach, caps), worker protocol
  (attach RPC transfers the canvas, commands reach the renderer), controller (attach,
  resize, keys, bye, re-attach, popup blocked, foreign origin ignored), stage page.
- SwiftShader (`tests/stage-output.swiftshader.spec.ts`, `npm run test:engine2`, also
  under `PX_ISOLATED=1`): a real popup's canvas crosses windows, is configured on the
  render worker's device (and on the page's with `?renderer=main`) and presents every
  frame; calibration keys from the stage reach the renderer; closing the stage detaches
  it; after a simulated device loss the stage re-attaches to the new device with its
  calibration and one live device. Compositor screenshots of WebGPU canvases are blank on
  SwiftShader, so this checks the renderer's output status, not pixels.

## Not yet (follow-ups from the plan)

- **Pixel goldens of the warp** on a real GPU (the swiftshader harness cannot read an
  output canvas back; an output `captureFrame` RPC would close that).
- **Per-output pacing.** Every output presents with the renderer's frame loop, which
  follows the main canvas. The plan's "stage is the pacing master" needs the worker loop
  driven by the stage's `requestAnimationFrame`.
- **Low-res control preview as an output**, mesh warp, edge blending, masks, slot →
  surface routing, live thumbnails in the calibration UI.
- **Project-file persistence** (`src/contracts/project_file.json`) of the output layout;
  today it is `localStorage`.
- **Window Management fullscreen from the control window** (`requestFullscreen({ screen })`
  needs a gesture in the stage); the stage is placed on the chosen display and F there
  makes it fullscreen.
- WebRTC / WHIP out (Part C), the audio worklet and beat clock (Part D) and the timeline
  (Part E) are separate slices.
