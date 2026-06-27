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
work to make the init/format/limits handshake robust. **As of June 2026, all
six have landed** — verified in `renderer.cpp` and the canonical bridge sync
(`wasm_renderer/wasm_bridge.js` ↔ `src/wasm/wasm_bridge.js`, guarded by
`scripts/validate_wasm_artifacts.js`). See the
**[C++ Solidification Tracking](#c-solidification-tracking-2026-06)** section
and the full dependency-ordered roadmap in
[#799's tracking comment](https://github.com/ford442/image_video_effects/issues/799#issuecomment-4678258584).

**Updated bottom line (June 2026):** compute + present + init handshake are hardened (#817–#822 ✅).
Integration glue (#845–#847 ✅) and CI/testing (#848–#849 largely ✅) are in tree.
**Product decision: [Tier B — experimental opt-in](./WASM_BACKEND_POLICY.md)** — TS WebGPU remains default; WASM is not production-SLA until promotion gates pass.

---

## TL;DR — Current Reality

The C++ WASM renderer has received **significant investment** (multi-slot pipeline, depth, audio, RAII, async capture, workgroup parsing, device-lost handling) between March and May 2026. The compute core is real, compiles cleanly via Emscripten + emdawnwebgpu, and the JS bridge + TypeScript wrapper expose a rich API.

**However, the WASM path is not a production-default renderer** (see [WASM_BACKEND_POLICY.md](./WASM_BACKEND_POLICY.md)).

- The renderer **initializes successfully** on capable GPUs and can execute the full 700+ WGSL compute shaders.
- Init/format/limits handshake (#817–#822 ✅). Integration glue (#845–#847 ✅) landed June 2026.
- **Tier B policy:** WASM is opt-in only (`?renderer=wasm` or Controls switcher); labeled **Experimental** in UI.
- Residual risk: live-browser verification on edge GPUs; benchmark-driven promotion decision pending.

**Result:** Fallback cascade remains **TS WebGPU (default) → Canvas2D**. WASM is a parallel experimental path, not an automatic fallback.

The old root GAP doc (pre-Phase work) was pessimistic but directionally correct on viability. `wasm_renderer/STATUS.md` and `README.md` previously overstated **reliability** with unqualified "Phase 3 complete" — now caveated; see `wasm_renderer/STATUS.md`.

---

## 1. Current Status (Overall Health)

| Aspect                    | Assessment                          | Evidence |
|---------------------------|-------------------------------------|----------|
| C++ compute engine        | Advanced (Phase 2.5–3 quality)     | Full multi-slot, depth upload, audio to both buffers, RAII, workgroup parser, async readback |
| Presentation / output     | **Implemented** (June 2026)        | `Render()` → `PresentToSurface()` (renderer.cpp:1725), full acquire/render-pass/blit (renderer.cpp:924-1000), real `CreateRenderPipeline()` |
| Init / format / limits handshake | **Hardened (June 2026)**     | Fatal surface (#820 ✅), `getPreferredCanvasFormat()` (#818 ✅), `requiredLimits`/validation (#817/#819 ✅), unified init errors (#822 ✅), bridge sync (#821 ✅) |
| TS integration (manager)  | **Functional (June 2026)**         | #845 forwarding + #846 input sources wired; Tier B — not production SLA |
| App → renderer wiring     | **Functional (June 2026)**         | `setInputSource`, slot params via RendererManager |
| Build / CI                | **Hardened (June 2026 Phase 2)**   | CI `wasm` job + emsdk; artifact upload; Jest + Playwright; see `ARTIFACTS.md` |
| Product support tier      | **Tier B — Experimental**          | See [`WASM_BACKEND_POLICY.md`](./WASM_BACKEND_POLICY.md) |
| End-to-end usability      | Opt-in path on capable GPUs        | Edge GPU verification + benchmark promotion gate pending |

**Bottom line:** C++ WASM is a **working experimental backend** under Tier B policy. TS WebGPU is production default. Promotion to Tier A requires benchmark + reliability gates in [`WASM_BACKEND_POLICY.md`](./WASM_BACKEND_POLICY.md).

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
- **Artifacts**: `public/wasm/pixelocity_wasm.{js,wasm}` are genuine Emscripten output with correct magic and exports. CI rebuilds from source; `build.sh` fails without emcc unless `SKIP_WASM_BUILD=1`.

---

## 3. What's Broken / Incomplete

### 3.1 ~~No Pixels Ever Reach the Canvas~~ — RESOLVED (June 2026); see §0 update
- ~~`Render()` ends after compute + `CopyTextureToTexture` feedback. No render pass...~~ **No longer true.** `Render()` now calls `PresentToSurface()` (renderer.cpp:1725), which does `wgpuSurfaceGetCurrentTexture` → `BeginRenderPass` → `SetPipeline`/`SetBindGroup` → `Draw` → `End` → submit (renderer.cpp:924-1000).
- ~~`CreateRenderPipeline()` builds a dead full-screen sampler...~~ **No longer true.** It builds the pipeline used by `PresentToSurface()`.
- The canvas element passed to `initWasmRenderer` is used to create and configure a real WebGPU surface (see `JS_CreateSurfaceFromCanvas` / `ConfigureSurface`).
- **Residual risk (post-#817–#822):** init failures should now surface via structured diagnostics (`failedStageName`, `lastInitError`) instead of a silent black canvas, but live-browser verification on edge GPUs is still pending. Integration gaps (§3.2–3.4) can also make the canvas appear broken even when init succeeds.

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
- `src/wasm/wasm_bridge.js` is kept in sync with `wasm_renderer/wasm_bridge.js` by `build.sh` and `validate_wasm_artifacts.js` (#821 ✅).

---

## 4. Build & Integration Issues

| Problem | Location | Impact |
|---------|----------|--------|
| `prebuild` / `build` swallow failures | `package.json:22,27` | `npm run build` succeeds while shipping stale WASM or nothing |
| No Emscripten in CI | `.github/workflows/ci.yml` | **Resolved** — dedicated `wasm` job with `mymindstorm/setup-emsdk@v14` |
| Artifacts committed | `public/wasm/`, `build/wasm/`, `wasm_renderer/build/` | Drift inevitable; 96 KB binary in git |
| Two bridge copies | `src/wasm/` vs `wasm_renderer/` vs `public/wasm/` | **Resolved (#821):** `build.sh` copies canonical bridge to both `src/wasm/` and `public/wasm/`; validator fails on skew |
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
| Presentation to canvas           | ✅ (full WebGPU render pass) | ✅ (render pass via `PresentToSurface`, June 2026) | Implemented; init handshake hardened (#817–#822 ✅) |

**Highest-priority missing pieces for usability:**
1. ~~End-to-end presentation (render pass + surface or texture-to-canvas path).~~ **Done (June 2026).**
2. ~~Init/format/limits handshake (#817–#822).~~ **Done (June 2026).**
3. Complete `RendererManager` forwarding for all WASM methods.
4. App-level calls to `setInputSource` + per-renderer input mode handling.
5. Wire `updateSlotParams` or normalize the slot param API.
6. CI + build that actually produces fresh artifacts or fails visibly.

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

### Phase 0 — Make It Reliable (June 2026: done via #817–#822)
- ~~Implement the missing presentation path in C++...~~ **Done.** `Render()` → `PresentToSurface()` is wired with a real render pass (see §0 update).
- The **init/format/limits handshake**, tracked as #817–#822 (parent [#799](https://github.com/ford442/image_video_effects/issues/799)), is **complete**:
  - #821 ✅ — bridge sync (`build.sh` → `src/wasm/` + `public/wasm/`; `validate_wasm_artifacts.js` guard)
  - #818 ✅ — surface/pipeline format via `getPreferredCanvasFormat()`
  - #820 ✅ — fatal surface-creation failure
  - #817 ✅ — adapter info/limits query + logging
  - #819 ✅ — explicit `requiredLimits` + early validation
  - #822 ✅ — unified init error paths, RAII cleanup, structured diagnostics to JS
- See **[C++ Solidification Tracking](#c-solidification-tracking-2026-06)** and the [#799 roadmap comment](https://github.com/ford442/image_video_effects/issues/799#issuecomment-4678258584).

### Phase 1 — Glue & Correctness (1 week)
- Fix `RendererManager`: add `else if (instanceof WASMRenderer)` branches for `setSlotShader`, `setSlotParams`/`updateSlotParams`, `setSlotMode`, `loadShader`, `updateSlotParams`, etc.
- Add `updateSlotParams` (or a normalized `setActiveSlotParams`) to WASMRenderer that calls the per-slot C++ API for the active slot.
- Audit every `(as any).foo` call site in App.tsx / WebGPUCanvas and route through the manager.
- Call `setInputSource(...)` from the input-source change handlers (map 'generative' → 4, etc.) for both renderers.

### Phase 2 — Build & CI ✅ (June 2026)
- ✅ Emscripten + emdawnwebgpu in CI `wasm` job (`mymindstorm/setup-emsdk@v14`)
- ✅ `build.sh` fails without emcc unless `SKIP_WASM_BUILD=1`
- ✅ **CI-built, committed baseline** artifact strategy — see [`wasm_renderer/ARTIFACTS.md`](./wasm_renderer/ARTIFACTS.md)
- ✅ Canonical `wasm_renderer/wasm_bridge.js` copied to `src/wasm/` + `public/wasm/`; validator checks all three
- ✅ Jest WASM smoke in `wasm` job; Playwright smoke in `test-wasm-e2e`

### Phase 3 — Parity & Hardening (2–3 weeks)
- Implement missing interface methods (`updateAudioFrequencyBins`, full recording integration using internal readback + JS encoding, `setRecording` adapter).
- Add WASM smoke + visual parity tests (even if just "does FPS stay > 30 and no console errors for 10 shaders").
- Performance benchmark (frame time, memory, shader compile) vs TS renderer on 3–5 representative shaders.
- Clean up per-slot submit pattern if it causes measurable overhead.
- RAII + error handling is already good; add shader hot-reload / recompilation path.

### Decision Point for Maintainers — **RESOLVED: Option B (June 2026)**

**Decision:** Tier B — **opt-in experimental backend**. TypeScript WebGPU is the supported production default.

Full policy, promotion gates, and demotion criteria:
**[`WASM_BACKEND_POLICY.md`](./WASM_BACKEND_POLICY.md)**

| If… | Then… |
|-----|--------|
| Promotion gates pass (perf, parity, 4wk CI) | Promote to Tier A — equal SLA, consider default for heavy-shader cohort |
| Benchmarks show no win / edge GPU init fails often | Demote to Tier D — hide toggle, archive `wasm_renderer/` |
| Wins on 3–5 heavy shaders only | Revisit hybrid routing (Tier C) — separate decision |

**Do not** invest in full dual-renderer SLA until promotion gates pass.

---

## C++ Solidification Tracking (2026-06)

Dependency-ordered tracking for the init/format/limits handshake work.
Full details and verified line references:
[#799 tracking comment](https://github.com/ford442/image_video_effects/issues/799#issuecomment-4678258584).

Recommended PR order (all landed as of this doc pass):

1. **#821** — Bridge sync
2. **#818 + #820** — Format negotiation + fatal surface
3. **#817 + #819** — Adapter/limits validation
4. **#822** — Init hardening + structured diagnostics
5. **#823** — This documentation refresh

| Issue | Status | Description |
|-------|--------|-------------|
| [#821](https://github.com/ford442/image_video_effects/issues/821) | ✅ | Bridge sync — `wasm_renderer/wasm_bridge.js` is source of truth; copied to `src/wasm/` + `public/wasm/` by `build.sh`; validator fails on skew |
| [#818](https://github.com/ford442/image_video_effects/issues/818) | ✅ | Surface/pipeline format negotiation via `getPreferredCanvasFormat()` |
| [#820](https://github.com/ford442/image_video_effects/issues/820) | ✅ | Fatal surface-creation failure |
| [#817](https://github.com/ford442/image_video_effects/issues/817) | ✅ | Adapter info/limits query + logging |
| [#819](https://github.com/ford442/image_video_effects/issues/819) | ✅ | Explicit `requiredLimits` + early validation |
| [#822](https://github.com/ford442/image_video_effects/issues/822) | ✅ | Unified init error paths, RAII cleanup, structured diagnostics (`getLastInitErrorStage`/`Message` → JS) |
| [#823](https://github.com/ford442/image_video_effects/issues/823) | ✅ | WASM docs refresh (this pass) |

All six C++ reliability issues (#817–#822) and integration issues #845–#847 are
implemented in tree.

**Tier B (June 2026):** WASM is experimental opt-in — see [`WASM_BACKEND_POLICY.md`](../WASM_BACKEND_POLICY.md).

**Remaining before Tier A promotion:**

- Live-browser smoke on edge GPUs
- Benchmark report attached to promotion issue (run `WASM_GPU_TESTS=1 npm run test:wasm:bench`)
- Close #848 / #849 with final CI + test suite links

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

