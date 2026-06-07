# WASM Renderer: Gap Analysis & Production Readiness (May 2026)

> **Type:** Epic / Tracking Document  
> **Labels:** `wasm`, `renderer`, `infrastructure`, `help wanted`  
> **Current as of:** May 2026 (post-Phase 3 commits)  
> **Related:** `wasm_renderer/STATUS.md` (over-optimistic), `wasm_renderer/README.md`, `WASM_TESTING.md`, `WASM_SMOKE_TEST.md`

---

## TL;DR — Current Reality

The C++ WASM renderer has received **significant investment** (multi-slot pipeline, depth, audio, RAII, async capture, workgroup parsing, device-lost handling) between March and May 2026. The compute core is real, compiles cleanly via Emscripten + emdawnwebgpu, and the JS bridge + TypeScript wrapper expose a rich API.

**However, the WASM path is still not a viable drop-in renderer.**

- The renderer **initializes successfully** (WebGPU device + all textures/buffers/pipelines) and can execute the full 700+ WGSL compute shaders.
- **It produces zero visible output on the canvas.** `Render()` only issues compute passes and texture copies. The render pipeline (dead code) and surface presentation path were never wired up. No `BeginRenderPass`, no surface configuration, no texture view for the HTML canvas.
- **Critical integration bugs** in `RendererManager` mean slot changes and parameter updates from the UI are never forwarded to the C++ side when WASM is active.
- The app **never calls `setInputSource`** on any renderer, so generative/procedural mode support in the C++ is unreachable.
- Build/CI hygiene is still broken: `npm run build` silently skips (or swallows hard failures from) the WASM build on machines without Emscripten.

**Result:** `?renderer=wasm` produces a black or frozen canvas while the C++ side burns CPU/GPU in the background doing invisible work. The cascade remains **TS WebGPU → (WASM that silently fails to present) → Canvas2D fallback** in practice.

The old root GAP doc (pre-Phase work) was pessimistic but directionally correct on viability. The `wasm_renderer/STATUS.md` and `README.md` claims of "Phase 3 Complete" and "all features ✅" are not supported by the code.

---

## 1. Current Status (Overall Health)

| Aspect                    | Assessment                          | Evidence |
|---------------------------|-------------------------------------|----------|
| C++ compute engine        | Advanced (Phase 2.5–3 quality)     | Full multi-slot, depth upload, audio to both buffers, RAII, workgroup parser, async readback |
| Presentation / output     | **Completely missing**             | Zero `BeginRenderPass` or surface usage anywhere in renderer.cpp |
| TS integration (manager)  | **Broken for WASM**                | `setSlotShader`, `updateSlotParams` only forward to `WebGPURenderer` |
| App → renderer wiring     | Incomplete                         | No `setInputSource` calls; render() args ignored by WASM path |
| Build / CI                | Fragile / misleading               | Artifacts committed; prebuild swallows; no emsdk in CI |
| Documentation             | Misleading                         | STATUS.md claims complete; reality does not match |
| End-to-end usability      | Non-functional                     | Cannot replace TS renderer today |

**Bottom line:** Excellent low-level WebGPU C++ work that stopped short of being a usable renderer. The "last mile" (presentation + glue) was never finished.

---

## 2. What's Working (Evidence-Based)

- **Device & resources**: `Initialize()` creates instance/adapter/device/queue with proper async callbacks + error handlers (device-lost, uncaptured-error). All 13 bind-group entries + samplers + uniform/extra/plasma buffers + 2048² textures created.
- **Multi-slot pipeline**: `Render()` correctly walks enabled slots[0..2], chooses chained vs parallel read source, writes per-slot `zoom_params` via `WriteSlotParams`, dispatches with correct parsed workgroup sizes, does final feedback copies. Separate `QueueSubmit` per slot (heavy but intentional for uniform ordering).
- **Shader loading**: `LoadShader` parses `@workgroup_size`, compiles WGSL via Dawn, caches pipelines. Matches the universal bind-group layout from AGENTS.md.
- **Depth**: `UpdateDepthMap` does `wgpuQueueWriteTexture` into `depthTextureRead_` (with zero-fill for partial uploads). Respects canvas size.
- **Audio**: `SetAudioData` → `UpdateUniformBuffer` writes to `extraBuffer_[0..2]` and `plasmaBuffer_[0]` as vec4(bass,mid,treble,0). Both shader conventions satisfied.
- **Capture/Recording bridge**: `beginFrameCapture` + `mapAsync` + `ReadCapturedFrame` (float→u8 conversion) + JS polling + `captureFrame()`/`startRecording()` (the latter uses `canvas.captureStream` on the input canvas element, bypassing internal textures).
- **Resize**: `ResizeCanvas` / `RecreateTextures` properly releases + rebuilds all size-dependent textures (including data A/B/C, depth, ping-pongs, readback buffer).
- **Generative placeholder**: 1×1 black `emptyTexture_` + `InputSource::Generative` path exists in C++.
- **Bridge & TS wrapper**: `wasm_bridge.js` (public version) + `WASMRenderer.ts` expose `setSlot*`, `updateDepthMap`, `updateAudioData`, `captureFrame`, `startRecording`, `resizeCanvas`, etc. Diagnostics present.
- **Artifacts**: `public/wasm/pixelocity_wasm.{js,wasm}` (66 KB + 96 KB, May 26 build) are genuine Emscripten output with correct magic and exports (not the old `Promise.resolve({})` stub). `build.sh` now hard-fails without `emcc`.

---

## 3. What's Broken / Incomplete

### 3.1 No Pixels Ever Reach the Canvas (Critical Blocker)
- `Render()` ends after compute + `CopyTextureToTexture` feedback. No render pass, no `wgpuSurfaceGetCurrentTexture`, no `BeginRenderPass`, no `Draw`.
- `CreateRenderPipeline()` builds a dead full-screen sampler of `writeTexture_` but is never used.
- The canvas element passed to `initWasmRenderer` is only used for width/height; its WebGPU context (if any) is never acquired or configured by the C++ side.
- **Observable result**: Switching to WASM shows black/frozen output. The TS renderer (or previous frame) owns the canvas.

### 3.2 RendererManager Forwards Almost Nothing to WASM
- `setSlotShader(index, id)`: only `if (instanceof WebGPURenderer)`
- `updateSlotParams(...)`: only `if (instanceof WebGPURenderer)`
- `loadShaders`, several other helpers have the same one-sided dispatch.
- App code often does `(rendererRef.current as any).setSlotShader(...)` — fragile and bypasses the manager's (already incomplete) logic.
- Consequence: changing shaders in slots or moving sliders has no effect under WASM.

### 3.3 Input Source & Generative Never Wired
- Zero call sites for `renderer.setInputSource(...)` or `WasmBridge.setInputSource` in `App.tsx`, `WebGPUCanvas.tsx`, or `Controls.tsx`.
- Video/webcam paths work because `updateVideoFrame()` is called on the active renderer (and WASM implements it).
- Generative shaders and explicit "live" / "generative" source selection are no-ops for WASM.

### 3.4 Recording & Screenshots Are Half-Real
- `startRecording()` in the bridge ignores the WASM renderer entirely and does `canvas.captureStream(60)` + `MediaRecorder` on the JS canvas (which may be blank when WASM is "active").
- The internal `captureFrame()` / readback path works in isolation but is not used by the app's recording UI.

### 3.5 Partial Interface Implementation
WASMRenderer implements many optionals but is missing:
- `updateAudioFrequencyBins` (full FFT → extraBuffer)
- `updateSlotParams` (aggregate form used by WebGPUCanvas effect)
- `getSlotState`, `getGPUTimings`, `getSupportsDeepWorkgroup`, `setRecording`/`setRecordingMode`
- `getFrameImage`

### 3.6 Other Runtime Risks
- Every slot = separate encoder + submit (no single-encoder multi-pass).
- Readback path assumes RGBA32Float internal format and does manual float→u8 (correct for capture but highlights that the "final" texture is never presented as 8-bit either).
- No high-DPI handling, no dynamic context loss recovery beyond the callbacks.
- `src/wasm/wasm_bridge.js` (bundled) is older than `public/wasm/wasm_bridge.js` (copied at build) → skew risk.

---

## 4. Build & Integration Issues

| Problem | Location | Impact |
|---------|----------|--------|
| `prebuild` / `build` swallow failures | `package.json:22,27` | `npm run build` succeeds while shipping stale WASM or nothing |
| No Emscripten in CI | `.github/workflows/ci.yml` | `wasm:build` either skipped or hard-fails silently; artifacts never regenerated in PRs |
| Artifacts committed | `public/wasm/`, `build/wasm/`, `wasm_renderer/build/` | Drift inevitable; 96 KB binary in git |
| Two bridge copies | `src/wasm/wasm_bridge.js` vs `public/wasm/wasm_bridge.js` | Version skew between bundled imports and runtime-loaded glue |
| `build.sh` improved but still env-sensitive | `wasm_renderer/build.sh` | Hard-coded candidate paths for emsdk_env.sh |
| CMake is secondary | `CMakeLists.txt` comment says "use build.sh" | Maintainers must keep two export lists in sync |

The old stub behavior is gone (good), but the "silent degradation" problem moved up one layer into the npm scripts.

---

## 5. Feature Parity Gaps (vs TypeScript Renderer)

| Feature                          | TS WebGPURenderer          | WASM (C++)                          | Status |
|----------------------------------|----------------------------|-------------------------------------|--------|
| Single-pass WGSL compute         | ✅                         | ✅ (full bind group, dynamic wg)   | Good |
| 3-slot chained / parallel        | ✅                         | ✅ (per-slot submits + param patch) | Core works |
| Depth map (AI)                   | ✅                         | ✅ (QueueWriteTexture)             | Wired |
| 3-band audio (bass/mid/treble)   | ✅                         | ✅ (extra + plasma)                | Wired |
| Full FFT bins                    | ✅                         | ❌ (only 3-band)                   | Partial |
| Mouse + ripples                  | ✅                         | ✅                                 | Good |
| Image / video / webcam upload    | ✅                         | ✅ (persistent staging for video)  | Good |
| Generative (no input)            | ✅                         | ⚠️ API exists, never called        | Unreachable |
| HLS live streams                 | ✅ (via video element)     | ⚠️ Same path, untested             | Untested |
| Dynamic canvas resize            | ✅                         | ✅ (RecreateTextures)              | Good |
| Screenshot / captureFrame        | ✅                         | ✅ (internal) / JS side            | Half |
| 8s WebM recording                | ✅ (canvas.captureStream)  | ⚠️ JS canvas only (may be blank)   | Broken when active |
| Shader caching / precompile      | ✅                         | ⚠️ Per-load compile, no cache      | Basic |
| GPU timing queries               | ✅                         | ❌                                 | Missing |
| `setRecording` / loop mode       | ✅                         | ❌ (different API)                 | Interface gap |
| BroadcastChannel remote          | ✅                         | ❌ (JS layer only)                 | N/A |
| Presentation to canvas           | ✅ (full WebGPU render pass) | ❌ **Nothing**                    | **Blocker** |

**Highest-priority missing pieces for usability:**
1. End-to-end presentation (render pass + surface or texture-to-canvas path).
2. Complete `RendererManager` forwarding for all WASM methods.
3. App-level calls to `setInputSource` + per-renderer input mode handling.
4. Wire `updateSlotParams` or normalize the slot param API.
5. CI + build that actually produces fresh artifacts or fails visibly.

---

## 6. Testing & Validation Status

- **Unit tests**: `src/__tests__/WASMBridge.test.ts` only mocks the bridge surface. No real WASM execution.
- **Manual smoke docs**: `WASM_SMOKE_TEST.md` and `WASM_TESTING.md` are high-quality and describe `?renderer=wasm`, `getDiagnostics()`, runtime switching, and a checklist. They assume a working build.
- **No automated parity or visual regression tests** for the WASM path.
- **No performance numbers** (the original motivation).
- **No Playwright / CI job** that actually builds with emsdk and exercises `?renderer=wasm`.
- In practice, the only way to know it is broken is to try it manually with a local emsdk.

---

## 7. Recommended Next Steps / Roadmap (Prioritized)

### Phase 0 — Make It Visible (1–3 days, unblocks everything)
- Implement the missing presentation path in C++ (configure surface from the canvas or, simpler, expose `getOutputTexture()` + let JS do a blit, or add a proper render pass that writes to a surface configured in JS).
- Or (faster): after the last compute, copy `writeTexture_` to a shared staging texture that the TS side can sample in its own render pass when WASM is active.
- Add a visible "WASM presents: NO OUTPUT" warning banner when the WASM renderer is selected but presentation is not wired.

### Phase 1 — Glue & Correctness (1 week)
- Fix `RendererManager`: add `else if (instanceof WASMRenderer)` branches for `setSlotShader`, `setSlotParams`/`updateSlotParams`, `setSlotMode`, `loadShader`, `updateSlotParams`, etc.
- Add `updateSlotParams` (or a normalized `setActiveSlotParams`) to WASMRenderer that calls the per-slot C++ API for the active slot.
- Audit every `(as any).foo` call site in App.tsx / WebGPUCanvas and route through the manager.
- Call `setInputSource(...)` from the input-source change handlers (map 'generative' → 4, etc.) for both renderers.

### Phase 2 — Build & CI (3–5 days)
- Add Emscripten + emdawnwebgpu setup to a new "wasm" job or optional matrix in CI (use emsdk action or container).
- Remove the `2>/dev/null || echo` wrappers or make `wasm:build` a required step that fails the build when artifacts are missing/stale.
- Decide: commit artifacts (with hash manifest) **or** treat WASM as an explicit opt-in dev-only backend.
- Sync the two `wasm_bridge.js` copies or make one the source of truth and copy in a build step.

### Phase 3 — Parity & Hardening (2–3 weeks)
- Implement missing interface methods (`updateAudioFrequencyBins`, full recording integration using internal readback + JS encoding, `setRecording` adapter).
- Add WASM smoke + visual parity tests (even if just "does FPS stay > 30 and no console errors for 10 shaders").
- Performance benchmark (frame time, memory, shader compile) vs TS renderer on 3–5 representative shaders.
- Clean up per-slot submit pattern if it causes measurable overhead.
- RAII + error handling is already good; add shader hot-reload / recompilation path.

### Decision Point for Maintainers
**Do we want WASM as a supported backend in the next 3 months?**

- **Yes** → Commit to Phase 0 + 1 immediately. The C++ core is worth finishing.
- **No** → Remove the toggle, the `?renderer=wasm` path, the dead `wasm_renderer/` docs that claim completion, and the committed binaries. Keep the C++ as a research artifact or delete it to reduce confusion. The TS renderer is the only production path.

---

## Appendix: Quick Diagnostics (Still Valid)

```bash
# Is the glue a stub?
grep -c "Promise.resolve({})" public/wasm/pixelocity_wasm.js   # should be 0

# Real build?
ls -lh public/wasm/pixelocity_wasm.wasm   # ~96 KB, starts with \0asm

# In browser console with WASM active:
window.__rendererManager?.getDiagnostics()
# Look for rendererType:"wasm", wasm.initialized:true, but also visually inspect canvas

# Force it:
http://localhost:3000/?renderer=wasm
```

---

*Analysis performed May 2026 by direct source inspection of `wasm_renderer/{main.cpp,renderer.{h,cpp},build.sh,CMakeLists.txt,wasm_bridge.js}`, `src/renderer/{RendererManager.ts,WASMRenderer.ts,WebGPURenderer.ts,types.ts}`, `src/components/WebGPUCanvas.tsx`, `src/App.tsx`, package.json, CI yaml, committed artifacts, and git history since April 2026. The gap between "advanced compute prototype" and "usable renderer" is the central finding.*

