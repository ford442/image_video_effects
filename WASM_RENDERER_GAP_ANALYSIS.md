# WASM Renderer: Gap Analysis & Production Readiness

> **Type:** Epic / Tracking Document  
> **Labels:** `wasm`, `renderer`, `infrastructure`  
> **Current as of:** **July 2026**  
> **Related:** [`wasm_renderer/STATUS.md`](./wasm_renderer/STATUS.md), [`WASM_BACKEND_POLICY.md`](./WASM_BACKEND_POLICY.md), [`WASM_PROMOTION_TRACKING.md`](./WASM_PROMOTION_TRACKING.md)

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

**Updated bottom line (July 2026):** Compute + present + init handshake are hardened (#817–#822 ✅). Integration glue (#845–#849 ✅) and July follow-ups (#886–#889 ✅) landed in tree. **Still Tier B experimental** — promotion gates tracked in [`WASM_PROMOTION_TRACKING.md`](./WASM_PROMOTION_TRACKING.md). TS WebGPU remains production default.

---

## July 2026 — Current open work

| Area | Status | Tracking |
|------|--------|----------|
| **Promotion to Tier A** | Not met — needs bench JSON + multi-GPU parity + 4wk CI | [`WASM_PROMOTION_TRACKING.md`](./WASM_PROMOTION_TRACKING.md), [#890](https://github.com/ford442/image_video_effects/issues/890) |
| **Edge GPU live verification** | Informal only | Manual smoke + `WASM_GPU_TESTS=1` runs on real hardware |
| **Visual pixel-diff parity** | Not automated | Future work (post-#889) |
| **WASM GPU timestamp queries** | Wall-clock timings only (`timingSource: 'wall-clock'`) | Documented limitation (#888) |
| **Docs accuracy** | This pass (#890) | GAP, STATUS, README, WASM_*.md |

**Closed July epic items (implemented in tree):**

| Issue | Topic | Status |
|-------|-------|--------|
| [#886](https://github.com/ford442/image_video_effects/issues/886) | Recording via internal readback (not blank `captureStream`) | ✅ |
| [#887](https://github.com/ford442/image_video_effects/issues/887) | RendererManager duck-typed forwarding + `setInputSource` | ✅ |
| [#888](https://github.com/ford442/image_video_effects/issues/888) | FFT bins, `getAudioData`, recording flags | ✅ (GPU timestamps: wall-clock only) |
| [#889](https://github.com/ford442/image_video_effects/issues/889) | Playwright smoke, parity, `test:wasm:bench`, CI jobs | ✅ |

Umbrella: [#885](https://github.com/ford442/image_video_effects/issues/885)

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
| TS integration (manager)  | **Functional (July 2026)**         | Duck-typed forwarding (#887); resync on switch; Tier B — not production SLA |
| App → renderer wiring     | **Functional (July 2026)**         | `setInputSource`, slot params, recording via manager (#886–#887) |
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
- **Capture/Recording bridge**: `beginFrameCapture` + `mapAsync` + `ReadCapturedFrame`; `startRecording()` uses GPU readback → offscreen canvas → `captureStream` when WASM active (#886 ✅).
- **Resize**: `ResizeCanvas` / `RecreateTextures` properly releases + rebuilds all size-dependent textures (including data A/B/C, depth, ping-pongs, readback buffer).
- **Generative placeholder**: 1×1 black `emptyTexture_` + `InputSource::Generative` path exists in C++.
- **Bridge & TS wrapper**: `wasm_bridge.js` (public version) + `WASMRenderer.ts` expose `setSlot*`, `updateDepthMap`, `updateAudioData`, `captureFrame`, `startRecording`, `resizeCanvas`, etc. Diagnostics present.
- **Artifacts**: `public/wasm/pixelocity_wasm.{js,wasm}` are genuine Emscripten output with correct magic and exports. CI rebuilds from source; `build.sh` fails without emcc unless `SKIP_WASM_BUILD=1`.

---

## 3. Gaps & Residual Risk (July 2026)

> **May 2026 sections 3.1–3.6** described blockers that are now **resolved** in tree. They are preserved in [§3 Historical (May 2026)](#3-historical-may-2026--superseded) for archaeology only.

### 3.1 Active gaps (promotion blockers)

| Gap | Impact | Mitigation / tracking |
|-----|--------|----------------------|
| Promotion gates not met | WASM stays Tier B | [`WASM_PROMOTION_TRACKING.md`](./WASM_PROMOTION_TRACKING.md) |
| No benchmark evidence on target GPUs | Cannot justify Tier A | `WASM_GPU_TESTS=1 npm run test:wasm:bench` → attach JSON |
| Playwright parity unverified on ≥2 GPUs | Reliability gate open | Self-hosted / manual GPU runs (#889 infra) |
| No automated visual pixel-diff | Parity is statistical (luminance) only | Future work |
| WASM `getGPUTimings` wall-clock only | Perf analysis less precise than TS GPU timestamps | Documented (#888) |
| Edge GPU init/render | May still fail on weak/odd drivers | Structured diagnostics (#822); manual smoke |
| Per-slot separate `QueueSubmit` | Potential perf overhead | Benchmark gate will surface if material |

### 3.2 Resolved (June–July 2026)

| Former gap | Resolution |
|------------|------------|
| No presentation to canvas | `PresentToSurface()` wired (#817–#822 era) |
| Init/format/limits handshake fragile | #817–#822 ✅ |
| RendererManager WASM forwarding | Duck-typed dispatch + resync (#845, #887) |
| `setInputSource` never called | Wired in App/WebGPUCanvas (#846, #887) |
| Recording used blank DOM `captureStream` | Internal readback path (#886) |
| Missing FFT / `getAudioData` / slot state APIs | #888 ✅ |
| No Playwright / bench automation | #889 ✅ — see §6 |
| Stale bridge copy | #821 ✅ — `build.sh` + validator |

### 3. Historical (May 2026 — superseded)

<details>
<summary>Click to expand May 2026 gap descriptions (no longer accurate)</summary>

#### 3.1 ~~No Pixels Ever Reach the Canvas~~ — RESOLVED (June 2026)
- Was: `Render()` ended after compute with no present pass.
- Now: `PresentToSurface()` at `renderer.cpp:1725`.

#### 3.2 ~~RendererManager Forwards Almost Nothing to WASM~~ — RESOLVED (July 2026, #887)
- Was: `instanceof WebGPURenderer`-only branches; `(as any)` bypasses.
- Now: Duck-typed forwarding on `RendererManager`; `resyncShaderStack` on backend switch.

#### 3.3 ~~Input Source & Generative Never Wired~~ — RESOLVED (July 2026, #846/#887)
- Was: Zero `setInputSource` call sites.
- Now: Called from input-source handlers + resync on renderer switch.

#### 3.4 ~~Recording & Screenshots Are Half-Real~~ — RESOLVED (July 2026, #886)
- Was: `startRecording()` used DOM `captureStream` on potentially blank canvas.
- Now: WASM path uses GPU readback → offscreen canvas → `captureStream`.

#### 3.5 ~~Partial Interface Implementation~~ — LARGELY RESOLVED (July 2026, #888)
- Was: Missing FFT, `updateSlotParams`, `getSlotState`, `getGPUTimings`, recording flags.
- Now: Implemented; WASM GPU timings remain wall-clock only (`available: false`).

#### 3.6 Other Runtime Risks (partially open)
- Per-slot submit overhead — still true; benchmark gate tracks impact.
- Bridge sync — resolved (#821).

</details>

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
| Full FFT bins                    | ✅                         | ✅ (C++ `SetAudioFrequencyBins` + TS `getAudioData`) | Good (#888) |
| Mouse + ripples                  | ✅                         | ✅                                 | Good |
| Image / video / webcam upload    | ✅                         | ✅ (persistent staging for video)  | Good |
| Generative (no input)            | ✅                         | ✅ (`setInputSource` wired)          | Good (#887) |
| HLS live streams                 | ✅ (via video element)     | ⚠️ Same path, limited test coverage | Tier B |
| Dynamic canvas resize            | ✅                         | ✅ (RecreateTextures)              | Good |
| Screenshot / captureFrame        | ✅                         | ✅ (internal readback)             | Good |
| 8s WebM recording                | ✅ (canvas.captureStream)  | ✅ (readback → offscreen stream)     | Good (#886) |
| Shader caching / precompile      | ✅                         | ⚠️ Per-load compile, no cache      | Basic |
| GPU timing queries               | ✅ (when supported)        | ⚠️ wall-clock only                   | Partial (#888) |
| `setRecording` / loop mode       | ✅                         | ✅                                   | Good (#888) |
| BroadcastChannel remote          | ✅                         | ❌ (JS layer only)                 | N/A |
| Presentation to canvas           | ✅                         | ✅ (`PresentToSurface`)              | Good |

**Remaining parity gaps (non-blocking for Tier B, blocking for Tier A promotion):**

1. GPU timestamp queries on WASM path (wall-clock fallback only).
2. Automated visual pixel-diff (statistical luminance parity exists via Playwright).
3. Promotion evidence — see [`WASM_PROMOTION_TRACKING.md`](./WASM_PROMOTION_TRACKING.md).

**Resolved (was highest-priority):**

1. ~~End-to-end presentation.~~ **Done (June 2026).**
2. ~~Init/format/limits handshake (#817–#822).~~ **Done.**
3. ~~RendererManager WASM forwarding.~~ **Done (#887).**
4. ~~App-level `setInputSource`.~~ **Done (#887).**
5. ~~Recording integration.~~ **Done (#886).**
6. ~~CI + Playwright + benchmarks.~~ **Done (#889).**

---

## 6. Testing & Validation Status

- **Unit tests**: `WASMBridge.test.ts`, `WASMRenderer.*.test.ts`, `RendererManager.test.ts` — bridge surface + manager parity (mocked WASM module; no real GPU in Jest).
- **Playwright smoke** (`tests/wasm-renderer.smoke.spec.ts`): `?renderer=wasm&testMode=1`, 5-shader parity matrix, multi-slot stack, console error collection, FPS/canvas health. **Soft mode** (default CI) tolerates JS fallback when no WebGPU adapter; **strict mode** (`WASM_GPU_TESTS=1`) requires active `wasm` backend.
- **Parity matrix** (`tests/renderer-parity.spec.ts`): WASM vs WebGPU luminance comparison on `PARITY_MATRIX` shaders.
- **Benchmarks** (`tests/wasm-benchmark.spec.ts`): `npm run test:wasm:bench` → `test-results/wasm-benchmark-report.json` with promotion gate assessment (≥1.25× on ≥3 shaders per `WASM_BACKEND_POLICY.md`).
- **CI**: `wasm` job (emsdk build + Jest); `test-wasm-e2e` (soft smoke + strict GPU suite, skips without adapter); `wasm-gpu-manual` (`workflow_dispatch`) for self-hosted GPU runs.
- **Manual smoke docs**: `WASM_SMOKE_TEST.md`, `WASM_TEST_SUITE.md` — local GPU verification + contributor commands.
- **Still missing**: automated visual pixel-diff parity; real GPU numbers on CI (requires labeled/self-hosted runners); 4 consecutive green weeks for promotion.

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

### Phase 1 — Glue & Correctness ✅ (July 2026, #845–#849 + #886–#887)
- ✅ `RendererManager` duck-typed forwarding for slot/shader/param APIs
- ✅ `updateSlotParams` / `getSlotState` on WASMRenderer
- ✅ App/WebGPUCanvas routed through manager (reduced `(as any)` bypasses)
- ✅ `setInputSource(...)` from input-source handlers + resync on switch
- ✅ Recording via internal readback (#886)

### Phase 2 — Build & CI ✅ (June 2026)
- ✅ Emscripten + emdawnwebgpu in CI `wasm` job (`mymindstorm/setup-emsdk@v14`)
- ✅ `build.sh` fails without emcc unless `SKIP_WASM_BUILD=1`
- ✅ **CI-built, committed baseline** artifact strategy — see [`wasm_renderer/ARTIFACTS.md`](./wasm_renderer/ARTIFACTS.md)
- ✅ Canonical `wasm_renderer/wasm_bridge.js` copied to `src/wasm/` + `public/wasm/`; validator checks all three
- ✅ Jest WASM smoke in `wasm` job; Playwright smoke in `test-wasm-e2e`

### Phase 3 — Parity & Hardening (partial — July 2026)
- ✅ FFT bins, `getAudioData`, recording flags (#888)
- ✅ Playwright smoke + parity + benchmark JSON (#889) — see `WASM_TEST_SUITE.md`
- ⬜ Visual pixel-diff parity (future)
- ⬜ Promotion gates — [`WASM_PROMOTION_TRACKING.md`](./WASM_PROMOTION_TRACKING.md)
- ⬜ Per-slot submit optimization (if benchmarks show need)
- ⬜ Shader hot-reload path (dev `shaderHotReload=1` exists; production polish TBD)

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

All six C++ reliability issues (#817–#822) and integration issues #845–#849 are
implemented in tree. July glue (#886–#889) is implemented in tree.

**Tier B (July 2026):** WASM is experimental opt-in — see [`WASM_BACKEND_POLICY.md`](./WASM_BACKEND_POLICY.md).

**Promotion tracking:** [`WASM_PROMOTION_TRACKING.md`](./WASM_PROMOTION_TRACKING.md) ([#890](https://github.com/ford442/image_video_effects/issues/890)).

**July 2026 epic (#885):** Sub-issues #886–#889 implemented; #890 docs + promotion checklist (this pass).

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

