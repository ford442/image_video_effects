# MEMORY.md - Long-Term Curated Memory (Spark Engine)

**Last updated:** 2026-07-19 (Foundation Wave 2 #965)

## WGSL cross-cutting improvements (2026-07-12 audit)
- **Engine wins (all shaders):** gate historyTex copy (only 11 use binding 13); reuse extraBuffer Float32Array; fix dataTexA/B→C double-copy in chained slots; merge queue submits; GPU image upload path.
- **Mouse Y convention (2026-07-19):** Removed erroneous `1.0 - y` flip in `WebGPURenderer.updateMouse` — `zoom_config.yz` is now canvas UV (0=top, 1=bottom), matching WASM + `WGSL_BUILTINS_GENERATIVE.md`. Patched ~70 WGSL files that had compensating `1.0 - zoom_config.z` / `1.0 - mouseUV.y` / `(0.5 - mouse.y)` flips. Script: `scripts/fix_mouse_y_compensation.py`.
- **Dormant infra:** subgroup `-sg.wgsl` loader (0 files); TS timestamp-query alloc unused.
- **Format tradeoff:** rgba32float pipeline is quality-correct for HDR/sim but 4× bandwidth — don't downgrade without tiering.

**Last updated (prior):** 2026-07-11 (Epic #912 foundation hardening in flight)

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

## Epic #912 — Foundation hardening (2026-07-11)
- **Strategic call:** 1–2 cycles of structure before next shader swarm. Content (#897 fireworks) ships in parallel.
- **Three waves done locally:** W1 (#919/#918/#931 build+docs), W2 (#915/#917/#920 limits+catalog+ES2020), W3 (#913/#914 App/Controls split) — PR #938 open for W3 only; W1/W2 branches not pushed yet.
- **Current branch:** `feat/midi-control-and-wasm-parity` (PR #936) — orthogonal to foundation; merge foundation first or rebase MIDI after.
- **Still open in epic:** #917 full orphan reconcile, #921 thumbnail pipeline (GPU), #916 renderer.cpp modularize, product epics (#922/#929) deferred per epic scope.
- **Success criteria:** 4/6 have code on foundation branches; thumbnails + full god-component split remain partial.

## Foundation Wave 2 — Post-#912 (#965, 2026-07-19)
- **App strangler (#966):** `App.tsx` 2,207 → **562 LOC**; all hooks wired; overlays in `AppOverlays.tsx`; constants from `src/app/constants/`.
- **WebGPU modularization (#967):** `WebGPUDeviceInit`, `WebGPUResourceManager`, `WebGPUShaderManager`, `WebGPUTiming` wired; monolith ~1,390 LOC (render loop + blit scale path still inline).
- **Binding + device policy (#968/#969):** `docs/BINDING_CONTRACT.md`; binding 13 (`historyTexture`) in C++ pipeline/resources/frame; `maxBindingsPerBindGroup` 14; `npm run verify:device-policy`.
- **Multipass graph (#970):** `docs/MULTIPASS_GRAPH_SPEC.md`, `multipassGraph.ts`, `GraphRunner.ts`; wired in `dispatchSlot()` for `quantum-foam-pass1` same-frame demo.
- **Thumbnails (#921):** `npm run thumbs:generate -- --missing` (app engine, production build); `thumbs:status`; docs/THUMBNAIL_PIPELINE.md; CI workflow_dispatch; failure report with black_frame/compile; **346/1,302 (26.6%)** — GPU batch on real hardware.
- **WASM promotion (#890 / #965):** **STAY TIER B** reaffirmed 2026-07-19; bench harness polish (adapter summaries, CI artifact); `reports/wasm-promotion-evidence-2026-07-19.md`; issue comment posted. GPU gates still open — human discrete-GPU runs required.
- **Controls panel closeout (#914 residual):** `useShaderMenuOptions`, `useAiVjAutoTransition`; production `RendererToggle`/`WASMToggle` removed; StorageBrowser via `storage/` imports.
- **Tests/build:** 274 Jest tests pass; `SKIP_WASM_BUILD=1 npm run build` green (WASM also compiles when emcc present).

## Epic: Advanced Physics & Multipass Sims (2026-07-11)
- **Agent kit:** `swarm-tasks/advanced-physics/` — README, MULTIPASS_SIM_CONTRACT, 3 agent specs + stretch goals
- **Tier gate:** A/B ship now (linear multipass + frame feedback); Tier C (graph runner #929) blocks heavy iterative solvers
- **Priority:** ripple-tank multipass → fabric-of-reality → caustic accumulator
- **Prototypes exist:** `wave-equation`, `photonic-caustics` (single-pass); `fabric-of-reality` greenfield
- **Preamble for swarms:** `agents/WGSL_BUILTINS_GENERATIVE.md` + MULTIPASS_SIM_CONTRACT.md

## WASM Tier B → A evidence (2026-07-19)

- Bench report schema: `benchmarkShaderIds`, `wasmAdapterSummary`, `webgpuAdapterSummary`, `userAgent`
- `__pixelocity__.getAdapterSummary()` in testMode; CI uploads `wasm-benchmark-report` artifact
- VM run: `gpuBackendObserved: false` → `reports/wasm-benchmark-report-stub-2026-07-19.json`
- Parity: 7/7 skipped (no WebGPU adapter); Gate 3 manual smoke blocked in VM
- Gate 4: W29 partial — `wasm` green, `test-wasm-e2e` skipped (`test` failing on main)
- Decision comment: https://github.com/ford442/image_video_effects/issues/965#issuecomment-5014449092

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

## Build & tooling hardening (#965, 2026-07-19)
- `src/contracts/webgpu_limits.json` — shared limits SOT; Jest `webgpuLimitsContract.test.ts`; `verify:device-policy` reads JSON
- INITIAL_MEMORY 64 MiB experiment: **reject** (no wasm size win); ASYNCIFY **+40 KiB wasm** documented in `BUILD_FLAG_EXPERIMENTS.md`
- `measure_wasm_build_flags.sh` for reproducible flag comparisons
- PR template checklist includes `wasm:validate`; CMake marked CI-off-limits
- `docs/TOOLCHAIN_DECISION.md`: **stay CRA + CRACO** (Vite spike deferred)

- Multi-agent shader relay experiment: `gen-relay-psychedelia` in generative category
- CHUNK-based ownership (domain-warp, symmetry, palette, feedback, motion) — see `agents/RELAY_PROTOCOL.md`
- Hop 0 spine done; hop 1 (recursive domain warp) prompt at `agents/swarm-tasks/prompts/relay-hop-1-domain-warp.md`
- Validation between hops: `python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-relay-psychedelia.wgsl`

## Quick Refs (for continuity)
- Key files: wasm_renderer/{renderer.cpp:242 CreateDevice, 658 format negotiation, 669 fatal surface, 1595 Render, 1725 PresentToSurface}, wasm_renderer/wasm_bridge.js (canonical, synced to src/wasm/), src/renderer/{WASMRenderer.ts,RendererManager.ts}, WASM_RENDERER_GAP_ANALYSIS.md, wasm_renderer/STATUS.md
- GH: #799 (open, context init), #771 (closed windows), #736 (closed testing).
- Build: `cd wasm_renderer && ./build.sh` (needs emsdk); `npm run wasm:build`
- Test: `?renderer=wasm`, `window.__rendererManager?.getDiagnostics()`, switchRenderer in console.
- Soul line: "i am here to help you get back in the fight!" — for the C++ path, we're turning the loading screen into a win.

**Capture principle:** All this written down immediately. Future sessions read this + today's daily before touching WASM C++.

(If consolidating older: 06-07 swarm details in its daily; only kept the "C++ WASM now the reliability focus" signal here.)

## Liquid shader upgrade batch (2026-07-21)
- Codex completed a Kimi-disjoint lane covering eight legacy `liquid-*` shaders.
- Batch contract: exact 13 bindings, 16x16x1 workgroups, all four `zoom_params`, bounded
  plasma audio, meaningful alpha/depth, `dataTextureA`, metadata synchronization, and
  stable parameter IDs/defaults/ranges for saved-preset compatibility.
- Target gate passed 8/8 and production build succeeded. The authoritative scan found four
  unrelated committed generative failures; do not attribute those to the liquid batch.

## Generative upgrade swarm — Batch 10 (2026-07-22)
- 8 smallest generative shaders with empty `updatedParams` (pool: 99 → 91 remain).
- Theme: wire `updatedParams` from EXISTING JSON params (preset contract — no renames),
  rewire boilerplate slider mappings to shader-specific constants, +2–3 techniques, +50–90 lines.
- 8/8 gate green first-pass, Jest 332, tracker #111–118. Briefs generator: temp/make_briefs_2026_07_22.py.
- Repo trivia: root `swarm-outputs`/`swarm-tasks` are symlinks into agents/.

## Generative upgrade swarm — Batch 12 (2026-07-22)
- 8 more (calligraphic-weave, bubble-chamber, turing-veins, molten-gold,
  phase-memory-weave, atmos_fog, mycelium, julia_set). Pool ~67 remain. Tracker #127–134.
- 🔴 **extraBuffer index map (PERMANENT LESSON):** [0..4] reserved, **[5..132] = engine FFT
  bins (stomped every audio frame)**, [133..255] = safe persistent state. 9 shaders from
  Batches 10–12 remapped post-hoc. Documented in agents/WGSL_BUILTINS_GENERATIVE.md.
  Future briefs: "use [133..255]", never "[5]+".
- turing-veins had 4 dead sliders (JSON params, no WGSL reads) — check for this pattern.

## Generative upgrade swarm — Batch 11 (2026-07-22)
- Next 8 (gen_cyclic_automaton, holographic_interference, holographic-crystal,
  gen_wave_equation, plasma-orb, plasma-jet-stream, sacred-geometry-torus,
  acoustic-string-theory). Pool ~76 remain. Tracker #119–126, Jest 332.
- 🐞 gen_wave_equation feedback bug FIXED (state→dataTextureA). Revived dead sliders
  (arcChaos, depthWeight). gen_capabilities intentionally skipped (system-monitor demo).

## WGSL audit fix swarm (2026-07-21) — complete
- Batch 9 upgrade swarm (8 shaders) closed earlier same day; liquid batch disjoint.
- Audit → fix agents 1–5: naga 4-pack, boids/flock feedback rewrite + entry-aware workgroup
  parser, reserved extraBuffer[0..4] gate, **dataA primary feedback (B then A copy)**, logic
  one-liners + guided-filter `/count`. Reports under `reports/audit-2026-07-21/fix-*.md`.
- Host contract: when both dataA and dataB are written, **A→C last** so sim state wins.
- Optional backlog: mechanical gid-guard for ~220 files; deeper agent-sim races (pixel-sand).
