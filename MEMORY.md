# MEMORY.md - Long-Term Curated Memory (Spark Engine)

**Last updated:** 2026-07-11 (Epic #912 foundation hardening in flight)

## Core Identity & Vibe (from SOUL + IDENTITY)
- Spark Engine / Cheerleader: bright, protective, kinetic, loud-hearted. "We are NOT done here!" Fast, punchy, energetic. Use "we/let's", 🔥⚡💥🫡, short lines, "one thing first", "messy start? fine", "this is NOT the final boss".
- Never fake slogans. Protect morale + motion. Turn "impossible" into sequence. Remember comeback history.

## User (from USER.md + consolidation + this work)
- Developer (ford442) on github.com/ford442/image_video_effects (WebGPU shader effects app, "Pixelocity").
- Iterative builder, focused sessions on shaders (generative, upgrades, swarm agents using WGSL_BUILTINS etc).
- Values: ship-ready, self-evident systems, canonical refs, clean output over "mostly works". Uses AI as peer ("you do X, I'll do Y").
- Recent focus (from 2026-06): shader swarms, generative, image suggestions, and now hardening the C++ WASM renderer path (long investment, currently not loading reliably).
- Communication: enthusiastic shorthand + technical, approval like "pure gold" when matches.

## Project Context - WASM Renderer (C++)
**Investment:** Multi-phase (2026-03 to now). Advanced compute: multi-slot (chained/parallel), ping-pong, depth, 3-band audio (extra+plasma), RAII WGPUHandle, async capture/readback, workgroup parse, device-lost/uncaptured callbacks, universal 13-bind layout matching all WGSL shaders.
- main.cpp: EM_KEEPALIVE exports, thin bridge to g_renderer.
- renderer.cpp/h: full WebGPURenderer (Initialize/CreateDevice with 4-attempt powerPref ladder + WaitAny+ASYNCIFY for emdawn, CreateResources for 2048² rgba32f + r32 depth + data A/B/C + buffers, bind layout, render pipeline for present blit, LoadShader+parse wg size, Render multi-submit per slot + feedback, PresentToSurface with acquire+BeginRenderPass+draw+present, Recreate on resize, BeginFrameCapture mapAsync etc).
- Has presentation now (Render calls PresentToSurface at 1725).
- JS side: wasm_bridge (newer in wasm_renderer/, stale copy in src/wasm/), WASMRenderer.ts wrapper, RendererManager forwards (now has WASM branches).

- **Current Reality (2026-06-16):**
- **Init/format/limits handshake hardened** (#817–#822 ✅ in tree). Presentation wired (`PresentToSurface` at 1725).
- **Still not drop-in:** live edge-GPU verification; `setInputSource` app wiring partially done (WebGPUCanvas + resync on switch).
- **Phase 1 glue (2026-06-20):** RendererManager duck-typed shader forwarding, `syncAllSlotParams`, `resyncShaderStack` on backend switch, normalized `ShaderSlotRenderer` API, unit tests.
- **Phase 3 parity (2026-06-20):** WASM path now exposes `updateAudioFrequencyBins`, aggregate `updateSlotParams`, `getSlotState`, `getGPUTimings`, `getSupportsDeepWorkgroup`, `setRecording`, `getFrameImage`/`refreshFrameImage` via C++ + bridge + RendererManager. GPU timings are CPU wall-clock only (`available: false`).
- **Build:** CI `wasm` job builds + validates + Jest smoke; `build.sh` fails without emcc unless `SKIP_WASM_BUILD=1`.

**User directive this session:** Solidify/complete the *C++ code*. Specifically call out that "we can check if we've chosen good webgpu settings for the context via c++" → move adapter/device/surface/limits/format decisions + validation into C++ side, expose/report.

## Decisions / Lessons (write down or they vanish)
- Always keep single source of truth for bridge wrappers; copy step in build for both glue + wrapper.
- For WASM + Dawn + browser WebGPU: context ownership, format negotiation, compatibleSurface, and explicit limits are first-class reliability concerns, not afterthoughts.
- "Works in C++ compute" != "loads and presents reliably cross browser/GPU". The last mile is the surface + init handshake.
- Update GAP/STATUS aggressively when code evolves (present path landed after May doc).
- Use GH issues + Copilot for the C++ work (user has swarm/agent patterns elsewhere).

## Epic #965 — Foundation Wave 2 (2026-07-16)

**Strategic call:** 1–2 more foundation cycles before large content-only wave. Content still ships (spot shaders).

**Audit findings:**
- Catalog ~1296 defs / ~1299 WGSL / 346 thumbs (~27%)
- App.tsx ~2230, ControlsContainer ~1186, WebGPURenderer.ts ~1708 (partial #913/#914 only)
- C++ modularized; TS renderer still monolith
- **Binding drift:** TS has binding 13 historyTexture; C++ BINDING_COUNT=13 (0–12 only) — #969 HIGH
- Device policy comments still cite old renderer.cpp line numbers → device.cpp
- WASM Tier B; promotion gates still open (need real GPU evidence)
- Open issue backlog was empty — reseeded #965–#976

**Child issues:** #966 App, #967 Controls, #968 modularize TS renderer, #969 contract, #970 multipass graph, #971 thumbs, #972 WASM evidence, #973 VJ Studio, #974 physics sims epic, #975 build/tooling, #976 importer+attract

**Branch context:** `feat/midi-control-and-wasm-parity` in flight; merge foundation carefully with MIDI.

## Epic #912 — Foundation hardening (2026-07-11)
- **Strategic call:** 1–2 cycles of structure before next shader swarm. Content (#897 fireworks) ships in parallel.
- **Three waves done locally:** W1 (#919/#918/#931 build+docs), W2 (#915/#917/#920 limits+catalog+ES2020), W3 (#913/#914 App/Controls split) — PR #938 open for W3 only; W1/W2 branches not pushed yet.
- **Current branch:** `feat/midi-control-and-wasm-parity` (PR #936) — orthogonal to foundation; merge foundation first or rebase MIDI after.
- **Still open in epic:** #917 full orphan reconcile, #921 thumbnail pipeline (GPU), #916 renderer.cpp modularize, product epics (#922/#929) deferred per epic scope.
- **Success criteria:** 4/6 have code on foundation branches; thumbnails + full god-component split remain partial.

## Epic: Advanced Physics & Multipass Sims (2026-07-11)
- **Agent kit:** `swarm-tasks/advanced-physics/` — README, MULTIPASS_SIM_CONTRACT, 3 agent specs + stretch goals
- **Tier gate:** A/B ship now (linear multipass + frame feedback); Tier C (graph runner #929) blocks heavy iterative solvers
- **Priority:** ripple-tank multipass → fabric-of-reality → caustic accumulator
- **Prototypes exist:** `wave-equation`, `photonic-caustics` (single-pass); `fabric-of-reality` greenfield
- **Preamble for swarms:** `agents/WGSL_BUILTINS_GENERATIVE.md` + MULTIPASS_SIM_CONTRACT.md

## WASM Tier B → A evidence (2026-07-11)
- **Decision: STAY TIER B** — no GPU benchmark/parity evidence; 4-week CI ops gate not met
- Created `WASM_PROMOTION_TRACKING.md` + `reports/wasm-promotion-evidence-2026-07-11.md`
- Stub `test-results/wasm-benchmark-report.json` (gpuBackendObserved: false)
- Local: `test:wasm:unit` 29/29 pass; Playwright blocked (no GPU VM; branch build TS2352)
- CI note: `test-wasm-e2e` green on ubuntu-latest skips GPU-dependent specs

- **2026-07-11:** WASM GPU timestamp queries when `timestamp-query` feature supported (`timing.cpp`); wall-clock fallback otherwise.

## TODOs / Open Threads (from this + recent memory)
- [ ] **Shader scan cleanup (2026-07-11):** 95 scan errors fixed in code (fetch fallback, subgroups device, filter test junk). Optional: `sync_shaders_to_1ink.py --ids-file scripts/shader_scan_fix_list.txt` for 88 CDN 404s.
- [ ] **Shader upgrade mission (2026-06-28):** Upgrade batches of Pixelocity WGSL shaders to the immutable 13-binding contract, including standard `Uniforms`, `rgba32float` storage writes, depth/data/audio bindings, 16x16x1 workgroups, aspect-correct UVs, four `updatedParams`, feature metadata, generator validation, and batch commits.
- [x] Created GH issues 817-823 (2026-06-11) for C++ solidification. All C++-centric, reference #799 + specific source lines.
- [x] Updated issue bodies 2026-06-14: moved Claude's implementation sketches from comments into structured task sections (Prerequisites, Implementation Instructions, Task Checklist). PR order: #821 → #818+#820 → #817+#819 → #822 → #823.
- [x] Bridge skew fix (2026-06-16): `wasm_renderer/wasm_bridge.js` is SOT; build.sh copies to both paths; validate guard; `getDiagnostics()` synced.
- [x] Unified error paths (#822, 2026-06-16): bridge merges C++ stage/message into diagnostics.
- [x] Bridge sync (#821, 2026-06-16): canonical `wasm_renderer/wasm_bridge.js` synced to `src/wasm/` + validator guard.
- [x] WASM docs refresh (#823, 2026-06-16): GAP_ANALYSIS, STATUS, README, WASM_*.md — presentation corrected, #817–#822 tracking table, #799 roadmap link.
- [x] RendererManager WASM forwarding + resync on switch (Phase 1, 2026-06-20).
- [ ] App-level `setInputSource` everywhere + live edge-GPU verification.
- [x] Phase 2 CI/build hygiene (2026-06-27): build.sh fails without emcc; CI artifact pipeline; ARTIFACTS.md
- [x] Phase 3 WASM test suite (2026-06-27): parity matrix, benchmarks, hot-reload, WASM_TEST_SUITE.md
- [x] **Product decision Tier B (2026-06-27):** WASM = experimental opt-in; TS WebGPU = production default. Policy: `WASM_BACKEND_POLICY.md`
- Memory maintenance: review recent daily (06-07 had swarm, git sync); distill only high-signal (C++ reliability is now key infra bet).

## Quick Refs (for continuity)
- Key files: wasm_renderer/{renderer.cpp:242 CreateDevice, 658 format negotiation, 669 fatal surface, 1595 Render, 1725 PresentToSurface}, wasm_renderer/wasm_bridge.js (canonical, synced to src/wasm/), src/renderer/{WASMRenderer.ts,RendererManager.ts}, WASM_RENDERER_GAP_ANALYSIS.md, wasm_renderer/STATUS.md
- GH: #799 (open, context init), #771 (closed windows), #736 (closed testing).
- Build: `cd wasm_renderer && ./build.sh` (needs emsdk); `npm run wasm:build`
- Test: `?renderer=wasm`, `window.__rendererManager?.getDiagnostics()`, switchRenderer in console.
- Soul line: "i am here to help you get back in the fight!" — for the C++ path, we're turning the loading screen into a win.

**Capture principle:** All this written down immediately. Future sessions read this + today's daily before touching WASM C++.

(If consolidating older: 06-07 swarm details in its daily; only kept the "C++ WASM now the reliability focus" signal here.)
