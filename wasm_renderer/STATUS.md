# C++ WASM Renderer — Current Status

**Last updated:** June 2026

---

## Implementation Status: Phase 3 Complete ✅ (compute + present pipeline; init/format/limits reliability hardened June 2026)

The C++ WASM renderer has advanced well beyond the March 2026 analysis documents.
The older analysis files (`ARCHITECTURE_ANALYSIS.md`, `COMPLETENESS_ANALYSIS.md`,
`PERFORMANCE_ANALYSIS.md`, `STABILITY_ANALYSIS.md`, `RENDERER_PLAN.md`) describe
an early-development snapshot and should **not** be treated as authoritative.

> **Note on "Phase 3 Complete":** this refers to the compute + present pipeline
> (shaders run, output reaches the canvas via `PresentToSurface`). It does
> **not** mean end-to-end usability is done — see
> [Remaining Work / Reliability](#remaining-work--reliability-june-2026) for
> integration glue, live-browser verification, and the
> [C++ Solidification Tracking](#c-solidification-tracking-2026-06) table
> (init/format/limits handshake hardened in #817–#822).

### What Is Implemented

| Feature | Status |
|---------|--------|
| WebGPU device + queue initialisation | ✅ Complete |
| Universal bind group layout (all 700+ shaders) | ✅ Complete |
| Ping-pong texture pipeline | ✅ Complete |
| Multi-slot shader pipeline (slots 0-2) | ✅ Complete |
| Slot execution modes (`chained` / `parallel`) | ✅ Complete |
| Shader loading & pipeline caching | ✅ Complete |
| Uniform buffer (time, mouse, ripples, params) | ✅ Complete |
| Audio reactivity (`updateAudioData`) | ✅ Complete |
| Depth map support (`updateDepthMap`) | ✅ Complete |
| Image upload from JS (`uploadImageData`) | ✅ Complete |
| Video frame upload from JS (`uploadVideoFrame`) | ✅ Complete |
| Canvas resize + resource recreation | ✅ Complete |
| Frame capture / screenshot (`captureFrame`) | ✅ Complete |
| Video recording (`startRecording`) | ✅ Complete |
| Mouse position / ripple input | ✅ Complete |
| RAII resource management | ✅ Complete |
| Error handling & validation | ✅ Complete (init error paths, structured diagnostics — #822) |
| TypeScript wrapper (`WASMRenderer.ts`) | ✅ Complete |
| `wasm_bridge.js` / `.d.ts` glue | ✅ Complete — canonical `wasm_renderer/wasm_bridge.js` synced to `src/wasm/` + `public/wasm/` (#821 ✅) |

### What Is Not Yet Done

| Item | Notes |
|------|-------|
| `RendererManager` WASM forwarding | `setSlotShader`, `updateSlotParams` not forwarded to WASM — see GAP §3.2 |
| `setInputSource` app wiring | Never called from App/WebGPUCanvas — generative mode unreachable for WASM |
| Build artefacts in `public/wasm/` | Requires Emscripten SDK locally; `build.sh` exits 0 without `emcc` |
| Full parity test suite | See [`WASM_TESTING.md`](../WASM_TESTING.md) |
| Performance benchmarking vs JS renderer | Not yet formally measured |
| Live verification on edge GPUs | June 2026 reliability fixes need real-browser smoke (`WASM_SMOKE_TEST.md`) |

---

## Remaining Work / Reliability (June 2026)

The May 2026 "Phase 3 Complete" milestone covered the **compute + present**
pipeline (shaders run every frame, output is blitted to the canvas via
`PresentToSurface`). The June 2026 follow-up work hardened the **init /
format / limits handshake**, which was previously the main source of
"renderer initializes but produces no output" failures.

Full details and verified line references are in the
[#799 roadmap comment](https://github.com/ford442/image_video_effects/issues/799#issuecomment-4678258584).
Current status of each item is tracked in the
[C++ Solidification Tracking table](../WASM_RENDERER_GAP_ANALYSIS.md#c-solidification-tracking-2026-06)
in `WASM_RENDERER_GAP_ANALYSIS.md`.

Original dependency-ordered PR sequence for this body of work:

1. **#821** — Bridge sync (`src/wasm/wasm_bridge.js` vs canonical `wasm_renderer/wasm_bridge.js`)
2. **#818 + #820** — Surface/pipeline format negotiation (`getPreferredCanvasFormat()`) + fatal surface-creation failure
3. **#817 + #819** — Adapter info/limits query + explicit `requiredLimits` validation
4. **#822** — Unified init error paths, RAII cleanup on every failure, structured diagnostics
5. **#823** — This documentation refresh

**Current status:** #817–#822 have landed (verified in `renderer.cpp` and
byte-identical bridge copies). #823 (this doc pass) is complete. Remaining work
is integration glue and live-browser verification — see
[`WASM_RENDERER_GAP_ANALYSIS.md`](../WASM_RENDERER_GAP_ANALYSIS.md) §3.2–3.4.

### C++ Solidification Tracking (2026-06)

| Issue | Status | Description |
|-------|--------|-------------|
| [#821](https://github.com/ford442/image_video_effects/issues/821) | ✅ | Bridge sync |
| [#818](https://github.com/ford442/image_video_effects/issues/818) | ✅ | Format negotiation (`getPreferredCanvasFormat()`) |
| [#820](https://github.com/ford442/image_video_effects/issues/820) | ✅ | Fatal surface creation |
| [#817](https://github.com/ford442/image_video_effects/issues/817) | ✅ | Adapter query/log |
| [#819](https://github.com/ford442/image_video_effects/issues/819) | ✅ | `requiredLimits` validation |
| [#822](https://github.com/ford442/image_video_effects/issues/822) | ✅ | Init hardening + structured diagnostics |
| [#823](https://github.com/ford442/image_video_effects/issues/823) | ✅ | WASM docs refresh |

Full line references and context:
[`WASM_RENDERER_GAP_ANALYSIS.md`](../WASM_RENDERER_GAP_ANALYSIS.md#c-solidification-tracking-2026-06).

---

## Architecture Summary

```
Browser (TypeScript)
  └─ RendererManager.ts        — selects WebGPU / WASM / Canvas2D
       └─ WASMRenderer.ts      — TypeScript wrapper
            └─ wasm_bridge.js  — JS glue
                 └─ pixelocity_wasm.{js,wasm}  — Emscripten output
                      └─ renderer.cpp / main.cpp  — C++ WebGPU via Dawn/emdawnwebgpu
```

## Selecting the WASM Renderer

See [`WASM_TESTING.md`](../WASM_TESTING.md) for full instructions.
Quick reference:

```
# Load the app with the WASM renderer forced:
http://localhost:3000/?renderer=wasm

# Switch at runtime from the browser console:
window.__rendererManager?.switchRenderer('wasm');
```

## Build Instructions

```bash
cd wasm_renderer
./build.sh        # requires Emscripten SDK (emsdk)
# outputs: public/wasm/pixelocity_wasm.{js,wasm} + synced wasm_bridge.js in public/wasm/ and src/wasm/
```
