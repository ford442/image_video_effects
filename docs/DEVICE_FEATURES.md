# Device Features & Canvas Configuration

Cross-reference for optional WebGPU features and canvas setup parity between the TypeScript renderer (`src/renderer/webgpu/device.ts`) and the C++ WASM path (`wasm_renderer/device.cpp`). See also the bind-group layout in [BINDING_CONTRACT.md](./BINDING_CONTRACT.md).

## Boot probe

Before the production renderer starts, `runWebGpuBootProbe()` walks the adapter ladder, configures the swapchain, and compiles a minimal compute pipeline. Results are published to **`window.webgpuProbe`** (serializable JSON: attempts, `userAgentBrands`, `failedStage`). Failed probe → blocking canvas UI; no automatic Canvas2D fallback. See [`src/renderer/webgpuBootProbe.ts`](../src/renderer/webgpuBootProbe.ts).

## Optional features

| Feature | TypeScript | C++ WASM | Purpose |
|---------|------------|----------|---------|
| `float32-filterable` | Requested when adapter supports | Requested when adapter supports | rgba32float texture sampling on bindings 1/9/13 |
| `timestamp-query` | Requested when adapter supports (always-on) | Requested when available | GPU frame timing via `WebGPUTiming.ts` / `timing.cpp` |
| `subgroups` | Requested when available | Requested when adapter + emdawn headers support | WGSL `enable subgroups` shaders |
| `chromium-experimental-subgroups` | Fallback when `subgroups` absent | Fallback when headers define the enum | Chromium pre-standard subgroup path |

Feature collection lives in `collectOptionalDeviceFeatures()` — order is `float32-filterable` → `timestamp-query` → subgroup variant. C++ `requiredFeatures[3]` uses the same order (`src/contracts/webgpu_optional_features.json`, enforced by `verify:device-policy`).

### Timestamp honesty (#1007 / #1030)

`getGPUTimings().available === true` and `timingSource === 'gpu-timestamp'` only after a successful async readback sets `hasRealGpuTimings`. Feature presence alone is insufficient; wall-clock fallback applies until real GPU durations are decoded.

## Canvas configure contract

Source of truth: [`src/contracts/canvas_configure.json`](../src/contracts/canvas_configure.json). `npm run verify:device-policy` asserts that `buildCanvasConfigureOptions()` (TS), the `ctx.configure` in `JS_CreateSurfaceFromCanvas`, and `ConfigureSurface()` (C++) all match it — `alphaMode`, `usage`, preferred format, `presentModeWasm = fifo`, explicit width/height, and that `ConfigureSurface()` is still called after surface import.

| Key | Default (v1) | Owner |
|-----|--------------|-------|
| `alphaMode` | `opaque` | TS + JS configure + C++ |
| `usage` | `RENDER_ATTACHMENT` | TS + JS configure + C++ |
| `format` | `getPreferredCanvasFormat()` | TS + JS configure (C++ mirrors via `JS_GetPreferredCanvasFormat`) |
| `presentModeWasm` | `fifo` | C++ `ConfigureSurface()` only — TS never sets a presentMode |
| `colorSpace` | `srgb` (browser default, not written) | opt-in only, TS-first |
| `toneMapping` | `standard` (browser default, not written) | opt-in only, TS-first |

Both paths negotiate the swapchain via the browser's preferred format:

```typescript
context.configure({
  device,
  format: navigator.gpu.getPreferredCanvasFormat(), // typically bgra8unorm or rgba8unorm
  alphaMode: 'opaque',
  usage: GPUTextureUsage.RENDER_ATTACHMENT,
});
```

WASM equivalent: `JS_CreateSurfaceFromCanvas` in `device.cpp` (same `alphaMode`, `usage`, and `getPreferredCanvasFormat()`).

That JS `ctx.configure` is **not** the only configure. Immediately after `importJsSurface`, C++ `ConfigureSurface()` runs a second configure with `presentMode = Fifo` and the canvas width/height. Both are required: the JS pass matches TypeScript and lets emdawn import the surface; the C++ pass sizes the swapchain. Do not delete the C++ call as a “simplification” — present can stay black.

### Present pipeline

Internal compute targets **rgba32float** (or policy-selected internal format). The final blit pass copies to the canvas swapchain texture obtained from `context.getCurrentTexture()`. The canvas format is **not** rgba32float — it is whatever `getPreferredCanvasFormat()` returns.

Diagnostics: `adapterSummary` includes `surfaceFormat=<format>` and `features=[...]` after device creation for TS/WASM parity reports.

gpu-chores (Tier 4b) **adopt** this device — they never call `requestDevice()`. See [GPU_CHORES.md](GPU_CHORES.md).

### Opt-in: `COPY_SRC` swapchain

After the default configure, `runWebGpuBootProbe()` calls `probeCanvasCopySrc()`: it configures `RENDER_ATTACHMENT | COPY_SRC` inside a `validation` error scope (and checks `getConfiguration().usage` where available), records the result, then **restores the render-only configure**. The flag is published as:

- `window.webgpuProbe.canvasCopySrc: boolean`
- `WebGpuProbeHandoff.canvasCopySrc` (plus `canvasColorOptIns` so callers can rebuild the exact live config)
- `adapterSummary … | canvas: copySrc=yes|no colorSpace=…`

Rejection is fail-soft — it never fails the ladder rung. `encodePresent` (TS) and `PresentToSurface` (C++) remain blit-to-swapchain. Capture code (WebCodecs recording) reconfigures with `buildCanvasConfigureOptions(device, format, { ...canvasColorOptIns, copySrc: true })` only when the flag is true; it does not create a second device.

**C++ parity (canvas_configure v2).** The WASM path keeps both default configures (`JS_CreateSurfaceFromCanvas` render-only, then `ConfigureSurface()`). Right after surface creation, `CreateDevice()` runs `JS_ProbeCanvasCopySrc` (configure `RENDER_ATTACHMENT | COPY_SRC`, `getConfiguration()` readback) between `wgpuDevicePushErrorScope(Validation)` and `wgpuDevicePopErrorScope` + `WaitAny`, which is the same pattern as the rgba16/32 storage probe. It stores `canvasCopySrcSupported_`, and `ConfigureSurface()` then restores render-only. `ConfigureSurface()` adds `WGPUTextureUsage_CopySrc` only while `canvasCopySrc_` is set, and only `SetCanvasCopySrc()` (export `_setCanvasCopySrc`) sets it. It refuses when the probe said no, and resize reconfigures keep it. The result is published as `window.webgpuProbe` `{ backend: 'wasm', ok: true, canvasCopySrc }` (`publishWasmProbeSuccess`, since `?renderer=wasm` skips the TS probe), `getDiagnostics().wasm.canvasCopySrc`, and `adapterSummary … | canvasCopySrc=yes|no`. `verify:device-policy` checks the probe usage, the scope ordering, the `if (canvasCopySrc_) config.usage |= …` enums against `cpp.usageEnums`, and setter-only assignment. WASM PNG capture does not need `COPY_SRC`: `captureFrame()` reads the internal `writeTexture_` back losslessly.

### Opt-in: Display P3 / extended tone mapping (default off)

**User setting.** Controls → Render Quality → **Wide-gamut output (Display P3)** (`data-testid="display-p3-toggle"`). The choice persists in `localStorage` under `px_display_p3` (`canvas_configure.json` `optIn.displayP3.storageKey`, service `src/services/displayP3.ts`). `?display_p3=1` still works and wins: either source enables the opt-in, so a URL-forced page turns P3 back on at the next load whatever the saved value. The default is unchanged: off, srgb/standard, nothing written to `configure`.

- Requests `colorSpace: 'display-p3'`. Never requested at boot unless the setting or URL opts in (Pascal-era GPUs, cheap panels, screenshot mismatch).
- `toneMapping: { mode: 'extended' }` is only tried behind the same opt-in **and** when `matchMedia('(dynamic-range: high)')` matches. The page evaluates the media query (a worker cannot see it) and passes it to the renderer. Format stays `getPreferredCanvasFormat()`.
- Negotiation (`negotiateCanvasColor`): p3+extended → p3+standard → default srgb. A configure throw, a validation-scope error, or a `getConfiguration()` readback that doesn't match counts as rejected. A rejection leaves the default sRGB swapchain configured, so the canvas never goes blank.
- **Live toggle** (`WebGPURenderer.setDisplayP3`, worker RPC `setDisplayP3`): re-runs the negotiation on the existing `GPUDevice`/context — no second device — and preserves the current `COPY_SRC` bit. Capture (`setCanvasCopySrc`) spreads the stored `canvasColorOptIns`, so a P3 canvas stays P3 through capture and restore.
- **Recording guard:** while the swapchain holds `COPY_SRC` for a GPU-encode take, or the page is recording, the toggle is *deferred* (`deferred: true`, nothing reconfigured). The UI says "applies after recording stops" and applies it when recording ends, so one file never mixes color spaces.
- **Diagnostics:** the applied values are in `window.webgpuProbe.canvasColorSpace` / `canvasToneMapping`, plus `canvasColorFallback` when the request was narrowed (`unsupported-p3`, `unsupported-extended-tone-mapping`, `not-hdr-display`). Both boot and live changes update it. `getDiagnostics().webgpu.canvas` carries `{ requestedDisplayP3, colorSpace, toneMapping, copySrc, fallbackReason }`. The Controls panel shows `Applied: display-p3 / extended` or `Using sRGB: <reason>`.
- TS-first. The WASM path stays srgb/standard (Tier B freeze); the toggle is disabled there.

#### Display color vs. encoded recording color

The setting changes what the canvas presents; recordings get their own tag. They are separate steps.

| Surface | What the setting changes | Color metadata |
| --- | --- | --- |
| On-screen canvas | `GPUCanvasContext` `colorSpace`/`toneMapping` as accepted above | Handled by the browser compositor |
| PNG screenshot (worker `captureFrame`) | The 2D encode surface is created as `display-p3` when the presented `VideoFrame` reports `smpte432` primaries; otherwise default sRGB | PNG carries no ICC profile from `convertToBlob`; treat as untagged |
| MediaRecorder / `captureStream` | Whatever the compositor hands the stream | None written by the app; the browser's own default |
| WebCodecs + `webm-muxer` | Frames are built from the canvas, so pixel values are P3 | **Tagged `display-p3`** when every frame reports `smpte432` primaries (see below); otherwise the encoder default |

**WebCodecs tag (`src/recording/webmColour.ts`).** Chromium's `VideoEncoder` reports `smpte170m` matrix, primaries and transfer in `decoderConfig.colorSpace` for every input frame, whatever the frame's own color space (checked for VP9, VP8 and AV1). `webm-muxer` copies that into the Matroska Colour element, so *every* WebCodecs take is labelled SMPTE 170M, not BT.709, and a P3 take would play desaturated. `webm-muxer` has no `smpte432` entry, so after `finalize()` the recorder rewrites two 1-byte values inside the fixed-size Colour element: Primaries → 12 (SMPTE EG 432-1) and Transfer → 13 (IEC 61966-2-1 sRGB curve). Matrix and range keep the encoder's own values (`smpte170m`, limited), because that is the conversion the encoder applied. No byte moves.

- The tag applies only when *every* encoded frame reported `smpte432`. A mixed or unreadable take keeps the encoder default and logs `[GPU encode] Display P3 frames … were not tagged`. The recording guard above makes mixed takes unreachable in normal use.
- sRGB takes are unchanged (still the encoder default). That default is a pre-existing approximation, not a P3 concern.
- Diagnostics: `GpuEncodeSession.colorTag` / `GpuEncodeRecorder.colorTag` (`'display-p3' | 'encoder-default'`), and `window.webgpuProbe.recordingColorTag` after each take.
- Verified in Chromium (VP9) by encoding smpte432 frames with the real recorder and decoding the file back through a `<video>` element: the decoded `VideoFrame.colorSpace` is `{ primaries: 'smpte432', transfer: 'iec61966-2-1' }` for the tagged take and `smpte170m` for an sRGB take. This proves the container tag is honored by the demuxer; it says nothing about on-screen appearance on a P3 panel (see the table below).
- MP4/H.264 is not offered (no MP4 muxer), so nothing else needs tagging.

#### Hardware validation record

Fill one row per tested browser/display. SwiftShader (the cloud VM) has no wide-gamut display, so it only exercises the sRGB fallback path. `tests/display-p3.swiftshader.spec.ts` (`npm run test:engine2 -- -g "Display P3"`) toggles P3 live in both render threads and asserts the canvas still presents, GPU errors stay empty, and a rejection lands on sRGB with `canvasColorFallback`.

| Browser / OS | Display | `color-gamut` | `dynamic-range` | Applied color space | Applied tone mapping | Fallback reason | Date / tester |
| --- | --- | --- | --- | --- | --- | --- | --- |
| _pending real hardware_ | | | | | | | |

## Deferred

- **C++ canvas parity:** ~~`COPY_SRC`~~ (done: canvas_configure v2, see above) / `colorSpace` + extended tone mapping on `JS_CreateSurfaceFromCanvas` + `ConfigureSurface()` — after #1080 (TS-first `?display_p3=1`).
- **HDR / PQ recording tags:** only the P3 + sRGB-curve tag is written. Extended tone mapping (`toneMapping: 'extended'`) output is not tagged as PQ/HLG.
