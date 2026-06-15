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
> **not** mean the renderer is fully hardened — see
> [Remaining Work / Reliability](#remaining-work--reliability-june-2026) below
> for the init/format/limits handshake issues tracked for June 2026, and the
> [C++ Solidification Tracking table](../WASM_RENDERER_GAP_ANALYSIS.md#c-solidification-tracking-2026-06)
> in `WASM_RENDERER_GAP_ANALYSIS.md` for current status.

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
| `wasm_bridge.js` / `.d.ts` glue | ✅ Complete for the app-facing copy (`src/wasm/wasm_bridge.js`, incl. #822 diagnostics exports); 🔶 `wasm_renderer/wasm_bridge.js` dev copy still ~190 lines out of sync — #821 |

### What Is Not Yet Done

| Item | Notes |
|------|-------|
| #821 — full `wasm_bridge.js` sync | `wasm_renderer/wasm_bridge.js` (dev copy) and `src/wasm/wasm_bridge.js` (app-facing) still differ; each has exports/diagnostics the other lacks |
| Build artefacts in `public/wasm/` | Requires Emscripten SDK; not committed to repo |
| Full parity test suite | See [`WASM_TESTING.md`](../WASM_TESTING.md) for manual test plan |
| Performance benchmarking vs JS renderer | Not yet formally measured |
| Live verification of June 2026 reliability fixes | #817/#818/#819/#820/#822 landed in code; needs a real-browser smoke test once `build.sh` runs outside the sandbox (see `WASM_SMOKE_TEST.md`) |

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

**Current status:** #818, #820, #817, #819, and #822 have landed (verified in
`renderer.cpp`). **#821 is partial** — the app-facing bridge has the new
diagnostics exports, but the two `wasm_bridge.js` copies still differ by
~190 lines, so full sync is still open. #823 (this doc pass) is in progress.

See [`WASM_RENDERER_GAP_ANALYSIS.md`](../WASM_RENDERER_GAP_ANALYSIS.md) for the
full before/after analysis and current per-issue status.

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
# outputs: public/wasm/pixelocity_wasm.{js,wasm}
```
