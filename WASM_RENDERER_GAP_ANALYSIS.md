# WASM Renderer: Gap Analysis & Production Readiness Blockers

> **Type:** Epic / Tracking Issue  
> **Labels:** `wasm`, `renderer`, `infrastructure`, `help wanted`  
> **Related:** `wasm_renderer/COMPLETENESS_ANALYSIS.md`, `wasm_renderer/ARCHITECTURE_ANALYSIS.md`, `wasm_renderer/RENDERER_PLAN.md`

---

## TL;DR

The WASM renderer path is **architecturally present but functionally non-viable** today. `public/wasm/pixelocity_wasm.js` is a **dummy stub** (resolves to `{}`), so the compiled `.wasm` binary (79 KB) is unreachable from the browser. Even if the loader were fixed, the underlying C++ renderer is only **~30 % feature-complete** compared to the TypeScript renderer. The app currently cascades: **TS WebGPU → WASM (fails silently) → Canvas2D fallback**.

**Yes, we still need the C++ code.** It is the actual WASM renderer implementation. Without it, there is nothing to compile. The problem is that the build pipeline produces a broken loader, the JS/C++ API boundary has signature mismatches, and the C++ core is missing critical features (multi-slot stacking, depth maps, audio, recording, etc.).

---

## 1. Current Behavior vs. Expected Behavior

### Current Behavior
- `npm run wasm:build` runs `wasm_renderer/build.sh`.
- If `emcc` is missing (CI, fresh clones, most dev machines), the script silently writes a **dummy stub** to `public/wasm/pixelocity_wasm.js`:
  ```js
  window.PixelocityWASM = function() { return Promise.resolve({}); };
  ```
- `npm run prebuild` wraps this with `2>/dev/null || echo '⚠️ WASM build skipped ...'`, so failures are **never surfaced**.
- At runtime, `useWASM.ts` dynamically imports the stub. `loadWASM()` "succeeds" but the module has **zero usable exports** (`_initWasmRenderer`, `ccall`, etc. are `undefined`).
- `RendererManager.ts` tries WASM second in the cascade, fails, and falls through to the Canvas2D fallback or the TS WebGPU renderer.

### Expected Behavior
- `npm run build` produces a **real Emscripten JS glue** (`pixelocity_wasm.js`) alongside the `.wasm` binary.
- The WASM renderer loads successfully and achieves **feature parity** with the TS renderer.
- `RendererManager.ts` can select WASM as a genuine high-performance backend.

---

## 2. Root Cause: Build & Integration Layer Is Broken

| Layer | Status | Problem |
|-------|--------|---------|
| **Build script** | ⚠️ Partial | `build.sh` creates dummy stub when `emcc` absent; no CI enforcement |
| **CMake** | 🔴 Broken | Double `add_executable()`, missing `renderer.cpp`, undefined `${SOURCES}` |
| **Emscripten glue** | 🔴 Missing | `public/wasm/pixelocity_wasm.js` is a 1-line stub, not real Emscripten output |
| **JS/C++ API boundary** | 🔴 Mismatched | `updateUniforms()` passes 8 args from JS; C++ export accepts 0 |
| **Bridge** | 🟡 Incomplete | `wasm_bridge.js` missing wrappers for slots, depth, recording, input sources |
| **C++ core** | 🟡 ~30 % | Single-pass only; no multi-slot, no audio uniforms, no depth upload, no recording |

### 2.1 Files Involved
- `wasm_renderer/build.sh`
- `wasm_renderer/CMakeLists.txt`
- `public/wasm/pixelocity_wasm.js` (stub)
- `public/wasm/pixelocity_wasm.wasm` (real but unreachable)
- `src/hooks/useWASM.ts`
- `src/renderer/WASMRenderer.ts`
- `src/renderer/RendererManager.ts`
- `wasm_renderer/wasm_bridge.js`
- `wasm_renderer/main.cpp`
- `wasm_renderer/renderer.cpp`
- `wasm_renderer/renderer.h`

---

## 3. Feature Parity Matrix: TS Renderer vs. WASM Renderer

| Feature | TS Renderer | WASM Renderer | Priority |
|---------|-------------|---------------|----------|
| Single-pass compute shaders | ✅ | ✅ | — |
| Multi-slot shader stacking (3 slots, chained / parallel) | ✅ | ❌ **MISSING** | **Critical** |
| Ping-pong texture management | ✅ | ⚠️ Partial | — |
| Fixed 2048×2048 internal resolution | ✅ | ✅ | — |
| Static images | ✅ | ✅ | — |
| Video files / webcam | ✅ | ✅ | — |
| HLS live streams | ✅ | ❌ **MISSING** | High |
| Generative / procedural shaders | ✅ | ❌ **MISSING** | High |
| AI depth estimation → depth texture | ✅ | ❌ Stub only | **Critical** |
| Depth-aware shader effects | ✅ | ⚠️ Untested | Medium |
| Mouse position / clicks / ripples | ✅ | ✅ | — |
| Multi-touch | ✅ | ❌ **MISSING** | Medium |
| Audio analyzer (bass / mid / treble) | ✅ | ❌ **MISSING** | High |
| Audio-reactive shader uniforms | ✅ | ❌ **MISSING** | High |
| Video recording (8 s WebM clips) | ✅ | ❌ **MISSING** | High |
| Screenshots | ✅ | ❌ **MISSING** | Medium |
| BroadcastChannel remote control | ✅ | ❌ **MISSING** | Medium |
| Shader caching / precompilation | ✅ | ❌ **MISSING** | Medium |
| Dynamic canvas resize | ✅ | ❌ **MISSING** | Medium |
| High-DPI / Retina | ✅ | ⚠️ Partial | Medium |
| FPS counter | ✅ | ✅ | — |
| GPU timestamp profiling | ✅ | ❌ **MISSING** | Low |
| Frame-rate throttling / battery awareness | ✅ | ❌ **MISSING** | Low |

---

## 4. Critical C++ Code Gaps

The C++ source (~1,560 lines across `main.cpp`, `renderer.cpp`, `renderer.h`) is **real and compiles**, but several core subsystems are missing or stubbed:

### 4.1 Multi-Slot Pipeline (Biggest Architectural Blocker)
The TS renderer runs up to 3 shaders in sequence (`Slot 0 → Slot 1 → Slot 2`) with independent parameters and chained texture binding. The C++ `WebGPURenderer::Render()` only executes **one** compute pass. Adding multi-slot support requires:
- Per-slot state (`ShaderSlot` struct, `MAX_SHADER_SLOTS = 3`)
- Chained compute passes with ping-pong texture swapping
- Per-slot bind-group updates for `readTexture` / `writeTexture`
- JS bridge wrappers: `setSlotShader(slot, id)`, `setSlotParams(slot, params)`

**Effort estimate:** 2–3 weeks.

### 4.2 Depth Map Upload
`WebGPURenderer::UpdateDepthMap()` is declared in `renderer.h` but **empty** in `renderer.cpp`. The TS renderer uploads a `Float32Array` from the Xenova DPT-Hybrid-MIDAS model to `readDepthTexture` every frame. WASM needs:
- `wgpuQueueWriteTexture` path for single-channel `R32Float` data
- JS bridge: `updateDepthMap(data: Float32Array, w, h)`

**Effort estimate:** 3–5 days.

### 4.3 Audio Reactivity
`main.cpp` has `SetAudioData(bass, mid, treble)` but the data **never reaches shader uniforms**. The TS renderer pipes audio into `extraBuffer` / `plasmaBuffer`. WASM needs:
- Audio fields in the uniform struct (or a dedicated audio buffer)
- Uniform upload path in `renderer.cpp`
- JS bridge: `updateAudioData(bass, mid, treble)`

**Effort estimate:** 1 week.

### 4.4 Recording / Screenshots
Completely absent from C++. The TS renderer uses `canvas.captureStream(60)` + `MediaRecorder`. WASM would need:
- Frame readback: `CopyTextureToBuffer` → `mapAsync`
- Either JS-side `MediaRecorder` integration via `EM_JS` macros, or raw buffer export to JS for encoding

**Effort estimate:** 1–2 weeks.

### 4.5 Generative Shader Input
Generative shaders (e.g., `gen-orb`, `gen-nebula`) do not need an input image. The TS renderer binds a black/empty texture when `inputSource === 'generative'`. WASM hard-codes image/video upload paths and has no `InputSource::Generative` enum.

**Effort estimate:** 2–3 days.

### 4.6 Dynamic Workgroup Sizes
The TS renderer **parses `@workgroup_size` from WGSL source** and dispatches accordingly. The C++ renderer hard-codes `(8, 8, 1)` in `Render()`. Some shaders use `(64, 1, 1)` or `(256, 1, 1)`; these will produce incorrect results or GPU errors under WASM.

**Effort estimate:** 3–5 days.

---

## 5. API Boundary Mismatches

| JS Side (`wasm_bridge.js`) | C++ Side (`main.cpp`) | Issue |
|----------------------------|----------------------|-------|
| `updateUniforms(time, mouseX, mouseY, mouseDown, p1, p2, p3, p4)` — 8 args | `void updateUniforms()` — 0 args | **Stack corruption / UB** |
| `_initWasmRenderer(width, height, agentCount)` | `initWasmRenderer(width, height)` — no agent count | Signature drift; `useWASM.ts` references stale API |
| `setSlotShader(slot, id)` | **Does not exist** | Missing entirely |
| `updateDepthMap(data, w, h)` | `UpdateDepthMap()` stub | No implementation |
| `setRecording(isRecording)` | **Does not exist** | Missing entirely |
| `setInputSource(source)` | **Does not exist** | Missing entirely |

**Recommendation:** Consolidate all C API exports into a single `extern "C"` block with consistent `wasm*` naming (see `RENDERER_PLAN.md` §1.2 for a full proposed API).

---

## 6. Build System Issues

### 6.1 `CMakeLists.txt` is broken
- Two `add_executable()` calls — the second overwrites the first, dropping `main.cpp`.
- `renderer.cpp` is **not listed** in source files.
- `${SOURCES}` and `${HEADERS}` are referenced but never defined.
- Result: CMake path cannot produce a working binary even if `emcc` is present.

### 6.2 `build.sh` silently degrades
```bash
if ! command -v emcc &> /dev/null; then
    echo "/* stub */ window.PixelocityWASM = function() { return Promise.resolve({}); };" \
        > "$OUTPUT_DIR/pixelocity_wasm.js"
    exit 0  # Exits SUCCESS — build appears green
fi
```
This means:
- CI passes even when the WASM renderer is not built.
- Developers may not realize they are shipping a stub.
- The real `pixelocity_wasm.wasm` (from a previous build) sits next to a fake `.js`, creating a **misleading artifact pair**.

### 6.3 `package.json` prebuild silently skips
```json
"prebuild": "(npm run wasm:build 2>/dev/null || echo '⚠️ WASM build skipped ...') && node scripts/generate_shader_lists.js"
```
Failures are swallowed by `2>/dev/null` and the `||` clause.

---

## 7. Do We Still Need the C++ Code?

**Yes.**

The C++ code is not a wrapper around the TS renderer — it is a **separate native implementation** of the WebGPU compute pipeline. The performance rationale for WASM is:
- Reduce JS heap overhead (~200 MB → ~150 MB target)
- Eliminate per-frame `Float32Array` conversions for video uploads (persistent staging buffer)
- Faster shader compilation via direct WASM calls
- Potential for SIMD pixel conversion and fewer texture copies

**If we remove the C++ code, there is nothing to compile to `.wasm`.** The TS renderer cannot be transpiled to WASM; it is a fundamentally different runtime path.

However, the C++ code as it stands is **not production-ready**. It is a partial implementation that needs significant investment to reach parity.

---

## 8. Proposed Next Steps (Roadmap)

### Phase 0: Fix the Build & Loader (Days)
- [ ] **Restore working Emscripten build in CI**
  - Add `emsdk` setup to `.github/workflows/ci.yml`
  - Fail the build if `emcc` is missing (remove silent stub generation)
  - Produce real `pixelocity_wasm.js` glue alongside `.wasm`
- [ ] **Fix `CMakeLists.txt`**
  - Remove duplicate `add_executable()`
  - Explicitly list `main.cpp renderer.cpp`
  - Or deprecate CMake and document `build.sh` as the blessed path
- [ ] **Fix `updateUniforms` API mismatch**
  - Align JS bridge signature with C++ export (or vice versa)
- [ ] **Add null-checks to `wasm_bridge.js`**
  - Every `_malloc` must have a corresponding `_free` in `try/finally`

### Phase 1: Core Architecture (Weeks)
- [ ] **Implement multi-slot shader pipeline** (3 slots, chained / parallel)
  - Add `ShaderSlot` state to `renderer.h`
  - Modify `Render()` to dispatch chained compute passes
  - Add JS bridge: `setSlotShader`, `setSlotParams`, `setSlotMode`
- [ ] **Wire up audio data to uniforms / `extraBuffer`**
- [ ] **Implement `UpdateDepthMap`** (float32 upload to `depthTextureRead_`)
- [ ] **Add generative shader support** (bind empty texture when no input)

### Phase 2: Features & Polish (Weeks)
- [ ] **Recording / screenshots**
  - Frame readback via `CopyTextureToBuffer` + `mapAsync`
  - `EM_JS` wrappers for `MediaRecorder` or export raw frames to JS
- [ ] **Persistent staging buffer** for video uploads (eliminate per-frame 64 MB heap allocs)
- [ ] **Dynamic workgroup size parsing** from WGSL source (match TS behavior)
- [ ] **Dynamic canvas resize** (runtime texture recreation)

### Phase 3: Cleanup & Hardening (Weeks)
- [ ] **Remove dead Physarum code** from `main.cpp` (~250 lines)
- [ ] **RAII wrappers** for all raw WebGPU pointers
- [ ] **Device-lost callbacks** and shader compilation error reporting
- [ ] **Synchronize `useWASM.ts` / `WASMRenderer.ts` / `wasm_bridge.js`** with `main.cpp` exports
- [ ] **Add WASM renderer tests** (even if just Emscripten shell tests)

---

## 9. Estimated Effort

Based on `RENDERER_PLAN.md` and `COMPLETENESS_ANALYSIS.md`:

| Phase | Duration | Outcome |
|-------|----------|---------|
| Phase 0 | 2–3 days | WASM loads without crashing; real JS glue in CI |
| Phase 1 | 3–4 weeks | Multi-slot, audio, depth, generative input work |
| Phase 2 | 2–3 weeks | Recording, staging buffer, dynamic workgroups |
| Phase 3 | 2–3 weeks | Cleanup, RAII, error handling, tests |
| **Total** | **~8–10 weeks (1 developer)** | Full parity with TS renderer |

---

## 10. Decision Points for Maintainers

1. **Should WASM be a supported backend for the next release?**
   - If **yes**, we should commit to Phase 0 immediately and schedule Phase 1.
   - If **no**, we should remove the WASM toggle from `LiveStudioTab.tsx`, delete the stub artifacts, and archive `wasm_renderer/` to avoid confusing new contributors.

2. **CMake or `build.sh`?**
   - `CMakeLists.txt` is currently broken. Fixing it is trivial, but maintaining two build paths is overhead. Pick one and delete the other.

3. **Should `prebuild` fail hard when `emcc` is missing?**
   - Current behavior: silent skip → developers ship a stub unknowingly.
   - Recommended: make `wasm:build` a **separate, explicit step** (not part of `prebuild`) and fail loudly if `emcc` is absent.

---

## Appendix: Quick Diagnostic Commands

```bash
# Check if the JS glue is a stub
grep -c "Promise.resolve({})" public/wasm/pixelocity_wasm.js
# If result > 0, you are shipping a dummy loader.

# Check if the real .wasm exists
ls -lh public/wasm/pixelocity_wasm.wasm

# Verify emcc is available
which emcc || echo "Emscripten NOT installed — WASM build will produce a stub"

# Check CMake validity
cd wasm_renderer && cmake -B build . 2>&1 | head -20
```

---

*Issue drafted from analysis of `wasm_renderer/` source, `src/renderer/` integration layer, and CI build configuration. See linked analysis docs in `wasm_renderer/` for deeper technical detail.*
