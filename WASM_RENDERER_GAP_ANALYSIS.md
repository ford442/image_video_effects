# WASM Renderer: Gap Analysis & Production Readiness (May 2026)

> **Type:** Epic / Tracking Document  
> **Labels:** `wasm`, `renderer`, `infrastructure`, `help wanted`  
> **Current as of:** May 2026 (post-Phase 3 commits), with a **June 2026 update** below  
> **Related:** `wasm_renderer/STATUS.md` (over-optimistic), `wasm_renderer/README.md`, `WASM_TESTING.md`, `WASM_SMOKE_TEST.md`

---

## ⚠️ June 2026 Update — Presentation Exists; Init Handshake Is the Blocker

The May analysis below said presentation was "completely missing." **That is no
longer accurate.** Code inspection of `renderer.cpp` (as of June 2026) shows:

- `Render()` ends by calling `PresentToSurface()` (`renderer.cpp:1725`), which
  acquires the current surface texture, runs a full render pass (`BeginRenderPass`
  → `SetPipeline` → `SetBindGroup` → `Draw` → `End`), and submits it
  (`renderer.cpp:924-1000`).
- `CreateRenderPipeline()` (`renderer.cpp:~700s`) builds a real full-screen-quad
  pipeline that blits `writeTexture_` to the swap chain — it is **not** dead code.

So **Section 3.1 ("No Pixels Ever Reach the Canvas") is resolved.** The compute
pipeline and presentation path both exist and are wired together.

**The current blocker has moved upstream: the init/format/limits handshake is
fragile.** Specifically:

- Surface creation failure is **non-fatal** — `initWasmRenderer` can report
  success with no working presentation. → **#820**
- Surface + render-pipeline color format is **hardcoded `BGRA8Unorm`**,
  regardless of what `navigator.gpu.getPreferredCanvasFormat()` actually
  returns, causing black canvas / validation errors on `rgba8unorm` systems.
  → **#818**
- No `requiredLimits` requested and no adapter/device limits validation, so
  weak GPUs fail deep inside resource creation with cryptic errors instead of
  a clear "insufficient GPU" message at init time. → **#817**, **#819**
- The bridge copy actually imported by the app (`src/wasm/wasm_bridge.js`) was
  stale relative to `wasm_renderer/wasm_bridge.js` / `public/wasm/wasm_bridge.js`,
  so fixes to diagnostics/format negotiation didn't reach the running app.
  → **#821**
- Init failure paths were scattered (no unified `Shutdown()` on partial init,
  no structured error code surfaced to JS). → **#822**

These six issues (#817–#822, parent **#799**) cover concrete, code-verified C++
work to make the init/format/limits handshake robust. **As of this update,
#818, #820, #817, #819, and #822 have landed** (verified directly in
`renderer.cpp`); **#821 (bridge sync) is partially done** — see the
**[C++ Solidification Tracking](#c-solidification-tracking-2026-06)** section
near the end of this document for exactly what remains, and the full
dependency-ordered roadmap in
[#799's tracking comment](https://github.com/ford442/image_video_effects/issues/799#issuecomment-4678258584).

**Updated bottom line:** the compute pipeline and presentation path are both
real and connected, and the init/format/limits handshake itself
(format negotiation, fatal surface failure, adapter/limits validation, unified
init error paths) is now hardened in `renderer.cpp`. The one remaining piece
is finishing **#821**: the dev-copy `wasm_renderer/wasm_bridge.js` and the
app-facing `src/wasm/wasm_bridge.js` still differ by ~190 lines, so the
diagnostics surfaces are inconsistent between the two. The `RendererManager`
forwarding gaps (§3.2), input-source wiring (§3.3), and recording gaps (§3.4)
described below are still accurate and remain separate follow-up work.

---

## TL;DR — Current Reality

The C++ WASM renderer has received **significant investment** (multi-slot pipeline, depth, audio, RAII, async capture, workgroup parsing, device-lost handling) between March and May 2026. The compute core is real, compiles cleanly via Emscripten + emdawnwebgpu, and the JS bridge + TypeScript wrapper expose a rich API.

**However, the WASM path is still not a viable drop-in renderer.**

- The renderer **initializes successfully** (WebGPU device + all textures/buffers/pipelines) and can execute the full 700+ WGSL compute shaders.
- ~~It produces zero visible output on the canvas...~~ **(June 2026: superseded — see the update box above. `Render()` → `PresentToSurface()` is wired and presents `writeTexture_` to the canvas via a real render pass.)** The init/format/limits handshake (#817–#822) is now mostly hardened: surface-creation failure is fatal (#820 ✅), surface/pipeline format is negotiated via `getPreferredCanvasFormat()` (#818 ✅), and explicit `requiredLimits`/limits validation is in place (#817/#819 ✅). The remaining piece is **#821 (bridge sync, partial)** — `wasm_renderer/wasm_bridge.js` and `src/wasm/wasm_bridge.js` still differ by ~190 lines.
- **Critical integration bugs** in `RendererManager` mean slot changes and parameter updates from the UI are never forwarded to the C++ side when WASM is active.
- The app **never calls `setInputSource`** on any renderer, so generative/procedural mode support in the C++ is unreachable.
- Build/CI hygiene is still broken: `npm run build` silently skips (or swallows hard failures from) the WASM build on machines without Emscripten.

**Result:** `?renderer=wasm` now has a real, connected compute+present pipeline with a hardened init/format/limits handshake (#817/#818/#819/#820/#822 ✅). The remaining init-path risk is #821 (bridge sync, partial) plus the `RendererManager`/input-source/CI gaps below. The practical fallback cascade remains **TS WebGPU → WASM → Canvas2D**, but WASM init failures should now be rarer and better-diagnosed than before this June 2026 pass.

The old root GAP doc (pre-Phase work) was pessimistic but directionally correct on viability. The `wasm_renderer/STATUS.md` and `README.md` claims of "Phase 3 Complete" and "all features ✅" previously overstated **reliability** (init/format/limits handshake); as of this June 2026 update, most of that gap has been closed in code (#817/#818/#819/#820/#822), with #821 (bridge sync) the one item still partial.

---

## 1. Current Status (Overall Health)

| Aspect                    | Assessment                          | Evidence |
|---------------------------|-------------------------------------|----------|
| C++ compute engine        | Advanced (Phase 2.5–3 quality)     | Full multi-slot, depth upload, audio to both buffers, RAII, workgroup parser, async readback |
| Presentation / output     | **Implemented** (June 2026)        | `Render()` → `PresentToSurface()` (renderer.cpp:1725), full acquire/render-pass/blit (renderer.cpp:924-1000), real `CreateRenderPipeline()` |
| Init / format / limits handshake | **Hardened (June 2026)**     | Fatal surface failure (#820 ✅), `getPreferredCanvasFormat()` negotiation (#818 ✅), `requiredLimits`/validation (#817/#819 ✅), unified init error paths (#822 ✅) |
| TS integration (manager)  | **Broken for WASM**                | `setSlotShader`, `updateSlotParams` only forward to `WebGPURenderer` |
| App → renderer wiring     | Incomplete                         | No `setInputSource` calls; render() args ignored by WASM path |
| Build / CI                | Fragile / misleading               | Artifacts committed; prebuild swallows; no emsdk in CI |
| Bridge sync               | **Partial (June 2026)**            | App-facing `src/wasm/wasm_bridge.js` has the new #817/#822 diagnostics exports, but still differs from `wasm_renderer/wasm_bridge.js` by ~190 lines (#821 open) |
| Documentation             | Updated (June 2026)                | This doc and `wasm_renderer/STATUS.md`/`README.md` now reflect the hardened init handshake and the remaining #821 gap |
| End-to-end usability      | Mostly unblocked on init path      | Compute + present pipeline is real and init handshake is hardened (#817/#818/#819/#820/#822 ✅); #821 (bridge sync) and the RendererManager/input-source gaps remain |

**Bottom line:** The compute pipeline **and** the presentation path are real and wired together, and the init/format/limits handshake is now hardened (#817/#818/#819/#820/#822). The "last mile" still open is finishing #821 (bridge sync) plus the `RendererManager`/input-source glue gaps below.

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

### 3.1 ~~No Pixels Ever Reach the Canvas~~ — RESOLVED (June 2026); see §0 update
- ~~`Render()` ends after compute + `CopyTextureToTexture` feedback. No render pass...~~ **No longer true.** `Render()` now calls `PresentToSurface()` (renderer.cpp:1725), which does `wgpuSurfaceGetCurrentTexture` → `BeginRenderPass` → `SetPipeline`/`SetBindGroup` → `Draw` → `End` → submit (renderer.cpp:924-1000).
- ~~`CreateRenderPipeline()` builds a dead full-screen sampler...~~ **No longer true.** It builds the pipeline used by `PresentToSurface()`.
- The canvas element passed to `initWasmRenderer` is used to create and configure a real WebGPU surface (see `JS_CreateSurfaceFromCanvas` / `ConfigureSurface`).
- **Current observable risk**: on adapters/browsers hit by #817–#820 (insufficient limits, format mismatch, or surface-creation failure), the canvas can still be black — but the *cause* is now the init/format/limits handshake, not a missing presentation path. See the **June 2026 Update** at the top of this document.

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
| Presentation to canvas           | ✅ (full WebGPU render pass) | ✅ (render pass via `PresentToSurface`, June 2026) | Implemented; init handshake hardened (#817/#818/#819/#820/#822), #821 (bridge sync) partial |

**Highest-priority missing pieces for usability:**
1. ~~End-to-end presentation (render pass + surface or texture-to-canvas path).~~ **Done (June 2026).** ~~Init/format/limits handshake (#817–#822)~~ **mostly done (June 2026)** — only #821 (bridge sync) remains partial, see §0.
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

### Phase 0 — Make It Reliable (June 2026: nearly done via #817–#822)
- ~~Implement the missing presentation path in C++...~~ **Done.** `Render()` → `PresentToSurface()` is wired with a real render pass (see §0 update).
- The **init/format/limits handshake**, tracked as #817–#822 (parent #799), is **mostly done**:
  - #818 ✅ — surface/pipeline format negotiated via `getPreferredCanvasFormat()` instead of hardcoded `BGRA8Unorm`
  - #820 ✅ — surface-creation failure is now fatal (`initWasmRenderer` returns 0) instead of a silent black canvas
  - #817 ✅ — adapter info and limits are queried/logged
  - #819 ✅ — explicit `requiredLimits` requested; init fails early with an actionable message
  - #822 ✅ — unified error paths, RAII cleanup on every failure, structured diagnostics to JS
  - #821 🔶 — **partial**: `src/wasm/wasm_bridge.js` (app-facing) already exports the new #817/#822 diagnostics, but still differs from `wasm_renderer/wasm_bridge.js` by ~190 lines; full sync remains open
- See the **[C++ Solidification Tracking](#c-solidification-tracking-2026-06)** table below for status, and the [#799 roadmap comment](https://github.com/ford442/image_video_effects/issues/799#issuecomment-4678258584) for the dependency-ordered sequencing.

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

## C++ Solidification Tracking (2026-06)

Dependency-ordered tracking for the init/format/limits handshake work
described in the June 2026 update above. Full details and verified line
references: [#799 tracking comment](https://github.com/ford442/image_video_effects/issues/799#issuecomment-4678258584).
Original recommended PR order: **#821 → (#818 + #820) → (#817 + #819) → #822**.
In practice, #818/#820/#817/#819/#822 landed first; #821 (full bridge sync)
remains the only open item below.

| Issue | Status | Description |
|-------|--------|-------------|
| [#821](https://github.com/ford442/image_video_effects/issues/821) | 🔶 Partial | Bridge sync (`src/wasm/wasm_bridge.js` vs `wasm_renderer/wasm_bridge.js`) — the app-facing bridge has the critical #817/#822 diagnostics exports (`getAdapterSummary`, `getLastInitErrorStage/Message`), but the two copies still differ by ~190 lines (dev-copy diagnostics helpers); full sync still open |
| [#818](https://github.com/ford442/image_video_effects/issues/818) | ✅ | Surface/pipeline format negotiation via `getPreferredCanvasFormat()` |
| [#820](https://github.com/ford442/image_video_effects/issues/820) | ✅ | Fatal surface-creation failure |
| [#817](https://github.com/ford442/image_video_effects/issues/817) | ✅ | Adapter info/limits query + logging |
| [#819](https://github.com/ford442/image_video_effects/issues/819) | ✅ | Explicit `requiredLimits` + early validation |
| [#822](https://github.com/ford442/image_video_effects/issues/822) | ✅ | Unified init error paths, RAII cleanup, structured diagnostics |
| [#823](https://github.com/ford442/image_video_effects/issues/823) | 🔶 In progress | This docs refresh |

Five of the six C++ reliability issues (#817, #818, #819, #820, #822) have
landed as of this update — verified directly against `renderer.cpp` (negotiated
surface format, `requiredLimits`, fatal surface failure, adapter info logging,
and unified init error paths with structured diagnostics are all present in
code). The compute pipeline, presentation path, and most of the init/format/limits
handshake are now consistent. **#821 (bridge sync) is partially done**: the
app-facing `src/wasm/wasm_bridge.js` already exports the new diagnostics
(`getAdapterSummary`, `getLastInitErrorStage`, `getLastInitErrorMessage`), so
the running app benefits from #817/#822 — but `wasm_renderer/wasm_bridge.js`
(the dev/reference copy) still lacks those exports while having its own
diagnostic-tracking additions (`getDiagnostics`, load-error counters) that
haven't been ported back to `src/wasm/wasm_bridge.js`. Closing #821 fully
requires reconciling both copies. Remaining open work beyond #821 is the
`RendererManager`/input-source glue (§3.2–3.4) and CI/build hygiene (§4),
which are tracked separately from #799.

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

