# MEMORY.md - Long-Term Curated Memory (Spark Engine)

**Last updated:** 2026-08-06 (Batch 37 shader upgrades)

## 2026-08-06 — Shader upgrade Batch 37 (4-agent swarm)

- Same 4-agent pattern on the next 8 smallest pending generative shaders:
  Fireworks Fan Shell / Horse Tail / Ring Shell / Kamuro Gold, Symbiotic
  Cyber-Fungal Core-Reactor, Evolutionary Cellular Gardens, Chrono Kitsune
  Prism Weaver, Quantum Fluorescent Aether Moth Swarm; tracker is now #339.
- Fireworks-family normalized-pointer bug confirmed cohort-wide (yz-as-pixels);
  fixed config.y-as-audio in fungal/kitsune/moth, fungal's engine-owned
  zoom_config.w mutation slider, gardens' fake hash CA, moth's dead scatter +
  18-tap curl (→4-tap potential curl). Fungal gained 4 NEW indexed
  updatedParams (controls-dict schema; engine-owned control excluded).
- Coordinator caught a moth mouse y-flip (vertical mirror) post-swarm; fixed
  and re-gated. 7/7 pre-existing updatedParams byte-exact; state only
  extraBuffer[133..138] single-writer.
- Proof: gate 8/8, audits PASS, generative list synced, manifest 1,310/1,310
  (+1 = fungal qualifies), Jest 478/1, SKIP_WASM_BUILD=1 build green, drift
  restored. Visual QA external. ~111 pending generative remain.

## 2026-08-05 — Shader upgrade Batch 36 (4-agent swarm)

- Same 4-agent pattern on the next 8 smallest pending generative shaders:
  Cybernetic Ferro Coral, Thermal Rainbow Topography, Hyper Labyrinth,
  Topology Flow, Lichtenberg Storm, Phase-Transition Memory Weave, Luminescent
  Chrono-Fluid Astrolabe, Prismatic Void-Weaver Ouroboros; tracker is now #331.
- Repaired Astrolabe's completely scrambled uniform truth (time←config.z,
  audio←mouseDown), Ouroboros's fake rippleCount-audio + dead Twist Density,
  Topology Flow's unbounded ~15× feedback blowup, Thermal's top-left-pinned
  mouse, and cohort-wide missing A writes / far-is-one depth / hardcoded alpha.
- 8/8 updatedParams byte-exact; state only extraBuffer[133..138] single-writer.
- Proof: gate 8/8, audits PASS, generative list synced, manifest 1,309/1,309,
  Jest 478/1, SKIP_WASM_BUILD=1 build green, drift restored. Visual QA
  external. ~79 pending generative remain.

## 2026-08-05 — Shader upgrade Batch 35 (4-agent swarm)

- Full Algorithmist/Visualist/Interactivist/Optimizer swarm, 2 shaders each:
  Bioluminescent Cyber-Aether Void Seahorse, Velocity Bloom, Dragon Curve,
  Fractal Chrono-Dendrite Forge, Raptor Mini, Bismuth Singularity Loom Engine,
  3D Sierpinski Chaos, and Astro-Kinetic Chrono Orrery; tracker is now #323.
- Repaired Seahorse's non-canonical Uniforms struct, Bismuth's
  rippleCount-as-audio miswire, Orrery's 3 dead sliders + per-step Kepler
  hoisting, Sierpinski's filtering history read/flat depth, and gave
  Dendrite-forge 4 indexed updatedParams + 16x16x1 (stale unconsumed `controls`
  schema removed; effective defaults preserved). 7/7 pre-existing
  updatedParams byte-exact; state only extraBuffer[133..138] single-writer.
- Proof: focused gate 8/8, strict audits PASS, generative list synced
  (regenerate WITHOUT --base-url; build prebuild re-adds URL drift so re-sync
  after), manifest 1,309/1,309, Jest 478 pass / 1 skip, SKIP_WASM_BUILD=1
  build green, unrelated drift restored. Visual QA is a real-GPU handoff.
- Pending-pool recipe recorded in memory/2026-08-05.md (~87 generative remain).

## 2026-08-03 — Shader upgrade Batch 34

- The user immediately rolled into Batch 34, reinforcing the preference to
  continue directly through the clean pending generative queue. Completed
  Celestial Glass Tornado, String Theory, Voronoi Crystal, Chromodynamic Plasma
  Collider, Magnetic Ferrofluid, Psy Swirls, Audio Spirograph, and
  Bioluminescent Aether Pulsar; tracker is now #315.
- Fixed normalized-pointer-as-pixel mistakes, backward signed marching, missing
  A/depth writes, unguarded ripple ages/counts, filter-dependent C reads,
  inverted string energy glow, stub-only spirograph geometry, and Pulsar's
  generic control remapping.
- All eight now use bounded spring/click interaction, A as display history,
  generated relief/hit depth, exact saved control arrays, canonical bindings,
  and 16x16x1 workgroups. Persistent state stays in `extraBuffer[133..138]`.
- Focused gate 8/8, strict uniform/buffer/liveness/catalog audits, duplicate
  scan 1,320/1,320, Jest 478 pass / 1 skip, and production build all pass.
  Unrelated generated drift was restored; real-GPU visual QA remains external.

## 2026-08-03 — Shader upgrade Batch 33

- Completed a balanced hardening batch for Superfluid Quantum Foam, Cymatic
  Plasma Mandalas, Fractal Clockwork, Neuro-Kinetic Bloom, Nebular Chrono
  Astrolabe, Lenia 2, Graviton Plasma Lotus, and Silica Tsunami. Tracker is now
  #307.
- Added consistent spring/click interaction with persistent state restricted to
  `extraBuffer[133..138]`; corrected mouse/config semantics, unsafe math,
  workgroup drift, feedback reads, bounded raymarching, HDR output, and depth.
- Intentionally repaired Lenia's state ownership so C supplies prior species
  state, A receives the next state, and writeTexture stays presentation-only.
  Silica's refraction control now drives real IOR transmission.
- Exact saved updatedParams stayed intact. The focused gate is 8/8,
  strict uniform/buffer/liveness/catalog audits pass, duplicate scan is
  1,320/1,320, Jest is 478 pass / 1 skip, and the production build is green.
  Unrelated generated drift was restored; live visual QA remains external.

## 2026-08-03 — Shader upgrade Batches 31 and 32

- Resumed Kimi's interrupted generative-geometry swarm: coordinator-reviewed
  all 13 Batch 31 drafts and completed the five partial plus three missing Batch
  32 targets. Tracker is now #299.
- Cross-cutting fixes: canonical uniform meanings, plasmaBuffer[0]-only audio,
  guarded FFT access, non-filtering rgba32float feedback, defined falloffs,
  bounded ripple geometry, safe normalization, live controls, and consistent
  near-is-one depth. Existing saved-preset arrays stayed byte-equivalent; text
  metadata is additive and scientifically/descriptively honest.
- Batch 32 added budgeted attractor tubes, analytic IFS/monotile sculptures,
  raymarched cavern materials, interactive fluid geometry, and heightfield
  stained glass. Complete briefs and WGSL/JSON/MD output packages remain under
  the dated Kimi swarm directories.
- Final proof: explicit 21-file gate 21/21, strict extraBuffer and custom
  slider/JSON/list audits clean, 1,320 unique IDs, 1,307 manifest entries, Jest
  478 pass / 1 skip, and production build green. Unrelated generator/report
  drift was restored; visual QA remains external because the VM has no GPU.

## 2026-08-02 — Shader upgrade Batch 30

- Upgraded the next eight clean 120–122-line shaders: Gamma Ray Burst,
  Temporal Rift, Voxel Depth Sort, CRT Phosphor Decay, Infinite Spiral Zoom,
  Neon Poly Grid, X-Ray Reveal, and Color Channel Weave (tracker #271–278).
- Repaired runaway gamma math, missing bounds/border clamps, additive voxel
  shadows, two legacy 8x8 workgroups, Spiral's blue-channel angle alias, X-Ray
  softness/NaN issues, and Weave's reserved-zone audio bug.
- Standardized spring/click/FFT interaction with persistent state only in
  `[133..139]`; preserved source params and every raw/display feedback role.
- Focused gate/audits, generated catalogs, 1,319-ID duplicate scan, full Jest,
  and `SKIP_WASM_BUILD=1` production build all passed. VM GPU limitation leaves
  visual smoke to real hardware; unrelated generated/report state was preserved.

## 2026-08-02 — Shader upgrade Batch 29
- Continued the smallest-first clean single-pass queue with `sonic-boom`,
  `spectrum-bleed`, `anamorphic-caustic-flare`, `ascii-lens`, `digital-haze`,
  `heat-haze-mirage`, `interactive-film-burn`, and
  `porcelain-fracture-glow` (tracker #263–270; completed total 270).
- Fixed Spectrum Bleed's four controls reading time/mouse instead of
  `zoom_params`, its idempotent blur loop, Heat Haze's reserved-zone audio
  reads, ASCII Lens's missing A write/dead audio, and Digital Haze's dead
  density control. Added click launches, spring interaction, and FFT voices.
- Coordinator review repaired a missing bounds guard, an every-pixel persistent
  state race, ambiguous initialization, wrong click-shock direction, border
  samples, and unbounded event/HDR stacking. New state remains in
  `extraBuffer[133..138]`; raw temporal and mask/field feedback roles stay intact.
- Source params stayed exact; four indexed additive `updatedParams` and truthful
  feature/depth metadata match generated lists. Proof: focused gate 8/8 with
  zero warnings/buffer violations; dead-slider, strict-buffer, JSON/list audits
  clean; 1,319 unique IDs; 1,306 manifest entries; Jest 69 suites / 478 pass /
  1 skip; `SKIP_WASM_BUILD=1` production build green. Unrelated Physics Lab
  list drift and the existing WGSL report were restored byte-for-byte. Live
  WebGPU visual proof remains a real-hardware handoff.

## 2026-08-02 — Shader upgrade Batch 28
- Continued the smallest-first clean single-pass queue with
  `spec-importance-sampled-bokeh`, `chromatic-shockwave`, `film-cross-process`,
  `fluid-grid`, `infinite-video-feedback`, `pixel-storm`, `pixelation-drift`, and
  `silk-flow-advection` (tracker #255–262; completed total 262).
- Wired Chromatic Shockwave's dead Ring Count, corrected Fluid Grid's mislabeled
  controls, implemented Infinite Feedback's advertised mouse transform, made
  Pixelation Drift's mouse feature real, and activated Silk Flow's formerly
  write-only velocity history. Fixed missing bounds guards, displaced-sample
  safety, aspect-space transforms, exact-center math, and eager alpha division.
- All eight gained top-left-safe spring interaction, guarded click behavior, and
  regional FFT voices. Source params stayed exact; four indexed additive
  `updatedParams` and truthful feature/depth metadata propagated to generated
  lists. New persistent state remains in `extraBuffer[133..138]`; raw HDR,
  temporal display-history, and velocity feedback roles remain unchanged.
- Proof: focused Naga/bindgroup gate 8/8 with zero warnings/buffer violations;
  dead-slider, strict-buffer, JSON, and generated-list audits clean; 1,319 unique
  IDs; 1,306 manifest entries; Jest 69 suites / 478 pass / 1 skip;
  `SKIP_WASM_BUILD=1` production build green. Unrelated Physics Lab list drift
  and the pre-existing WGSL report were preserved byte-for-byte. Live WebGPU
  visual proof remains a real-hardware handoff.

## 2026-08-02 — Shader upgrade Batch 27
- Continued the smallest-first clean single-pass queue with `melting-oil`,
  `spec-iridescence-engine`, `spectral-waves`, `aero-chromatics`,
  `chroma-kinetic`, `cyber-trace`, `gen-chrono-erosion-feedback-melting`, and
  `quantum-flux` (tracker #247–254; completed total 254).
- Rewired three mislabeled Melting Oil sliders, three shaders that declared but
  never sampled audio, and Chrono Erosion's dead Feedback Mix. Added guarded
  click behavior, spring interaction, and regional FFT voices throughout.
- Coordinator review clamped Sobel border loads, fixed top-left initialization
  ambiguity, added the missing iridescence bounds guard, corrected aspect-space
  directions back into UV space, and bounded Cyber Trace's display emission with
  a hue-preserving soft knee while keeping raw clamp-2.0 history untouched.
- Source params stayed exact and each definition gained an indexed additive
  `updatedParams`; additive feature tags now match live audio/depth/temporal use.
  New persistent state remains in `extraBuffer[133..138]` and all feedback roles
  remain unchanged.
- Proof: focused Naga/bindgroup gate 8/8 with zero warnings/buffer violations;
  dead-slider, strict extraBuffer, JSON, and generated-list audits clean; 1,319
  unique IDs; 1,306 manifest entries; Jest 69 suites / 478 pass / 1 skip;
  `SKIP_WASM_BUILD=1` production build green. Unrelated Physics Lab list drift
  was removed and the pre-existing WGSL report preserved byte-for-byte. Live
  WebGPU visual proof remains a real-hardware handoff.

## 2026-08-02 — Shader upgrade Batch 26
- Continued the smallest-first clean single-pass queue with
  `temporal-frequency-decomposition`, `glass-wipes`, `interactive-zoom-blur`,
  `reality-tear`, `bubble-lens`, `cross-mouse-spec-dispersion-lens`,
  `laser-burn`, and `magnetic-luma-sort` (tracker #239–246; total 246).
- Core wins: wired Temporal Frequency Decomposition's previously dead mouse tag;
  corrected the prismatic crossover's elliptical lens; removed Magnetic Luma
  Sort's dead final-color experiment; wired formerly dead audio in Glass Wipes
  and Magnetic Luma Sort; added guarded click behavior and FFT voices throughout.
- Coordinator review replaced non-atomic every-pixel state stores in Temporal,
  Reality Tear, and Laser Burn with single-writer persistence, made top-left
  initialization explicit where position-zero sentinels were unsafe, and added
  a coarse cull before Bubble Lens satellite evaluations. New state remains in
  `extraBuffer[133..138]`; history binding 13 and all A/C state roles are intact.
- Source `params` stayed byte-equivalent; four indexed additive `updatedParams`
  were generated for each shader. Glass Wipes and Magnetic Luma Sort now carry
  truthful additive `audio-reactive` features.
- Proof: focused Naga/bindgroup gate 8/8 with zero warnings/buffer violations;
  dead-slider and JSON/list audits clean; 1,319 unique IDs; 1,306 manifest entries;
  Jest 69 suites / 478 pass / 1 skip; `SKIP_WASM_BUILD=1` production build green.
  Unrelated Physics Lab list drift and the pre-existing WGSL report were restored
  byte-for-byte. Live WebGPU visual proof remains a real-hardware handoff.

## 2026-08-02 — Shader upgrade Batch 25
- Continued the smallest-first all-category queue with `signal-tuner`,
  `fiber-optic-weave`, `hybrid-fractal-feedback`, `scan-slice`,
  `split-dimension`, `temporal-decay-multiresolution`, `paper-cutout`, and
  `rgb-delay-brush` (tracker #231–238; completed total 238).
- Major correctness repairs: Hybrid Fractal's four JSON controls now map to their
  named WGSL behaviors; unsafe 256-entry plasma palettes in Hybrid/Fiber were
  replaced by bounded procedural palettes plus valid FFT bins 1–8; Signal Tuner
  moved hidden origin state to safe persistent slots so A contains display RGBA
  everywhere; Paper Cutout accepts top-left mouse and now writes real relief.
- The history-ring effect now earns its mouse tag with a spring temporal lens and
  click echoes while preserving binding 13, its eight-layer indices, and read-only
  `extraBuffer[4]`. RGB Delay's scientific header is now explicitly a stylized,
  non-calibrated absorption model; its raw temporal A/C feedback stays intact.
- All eight gained guarded normalized click effects and meaningful regional FFT
  behavior. Source params stayed exact; indexed additive `updatedParams` were
  synchronized into generated lists. New state uses only [133..139].
- Proof: focused Naga/bindgroup gate 8/8 with zero warnings/buffer violations;
  dead-slider, extraBuffer, JSON, and generated-list audits clean; 1,319 unique
  IDs; 1,306 manifest entries; Jest 68 suites / 464 pass / 1 skip; production
  build green with `SKIP_WASM_BUILD=1`.
- Direct `tsx` again hit the known VM IPC `EPERM`; `node --import tsx` succeeded.
  The pre-existing WGSL report and unrelated simulation list were preserved
  byte-for-byte. Live WebGPU proof remains a real-hardware handoff.

## 2026-08-02 — Shader upgrade Batch 24
- Continued the smallest-first all-category queue with eight clean single-pass
  shaders: `quantum-tunnel-interactive`, `vhs-tracking-mouse`,
  `blueprint-reveal`, `cyber-grid-pulse`, `night-vision-scope`, `data-stream`,
  `glitch-slice-mirror`, and `knitted-fabric` (tracker #223–230).
- All eight gained spring-weighted interaction, guarded normalized click effects,
  and per-region FFT detail. Specific fixes include aspect-correct Data Stream
  wake, live treble characters, honest Night Vision depth, bounded HDR/emission,
  displaced depth sampling, and nonnegative click-slice intensity.
- Feedback truth held: Blueprint keeps raw temporal reveal state in A; Knitted
  Fabric moved display RGBA to host-primary A and diagnostic masks to B. All new
  persistent writes are confined to `extraBuffer[133..138]`.
- Source parameter IDs/defaults/ranges/steps stayed exact. Each definition gained
  indexed additive `updatedParams`; truthful click/depth metadata was added.
- Proof: focused Naga/bindgroup gate 8/8 with zero warnings/buffer violations;
  no dead sliders; 1,319 unique IDs; 1,306 manifest entries; Jest 68 suites / 464
  pass / 1 skip; production builds green with `SKIP_WASM_BUILD=1`. Direct `tsx`
  hit the known VM IPC `EPERM`; `node --import tsx` rebuilt the manifest.
- Live WebGPU visual/thumbnail QA remains external because this VM has no adapter.
  Pre-existing Batch 23 work and WGSL report bytes were preserved; unrelated
  Physics Lab simulation-list drift was removed byte-for-byte.

## 2026-08-01 — Shader upgrade Batch 23
- Eight upgrades shipped locally: `gen-fireworks-roman-candle`,
  `gen-zeta-function-landscape`, `gen-bioluminescent-reaction-diffusion`,
  `gen-cycloid-bloom`, `crt-scanline-damage`, `steampunk-gear-lens`,
  `fireworks-depth-parade`, and `fractal-noise-dissolve` (tracker #215–222).
- Key correctness wins: normalized pointer fixes in the fireworks family,
  eta-based zeta continuation, boundary-safe RD stencil + valid FFT bins 1–8,
  no Steampunk double mask, honest relief/shell/luminance depth, and bounded
  Fractal burn emission. Cycloid search dropped 1,205→360 tests/pixel.
- Contracts held: image source `params` and generative `updatedParams` unchanged;
  four image `updatedParams` added; only Depth Parade gained `supportsDepth`;
  RD keeps raw state in A; other A/B feedback roles unchanged; new state uses
  only `extraBuffer[133..138]`.
- Verification: 8/8 focused Naga/bindgroup gate, zero workgroup warnings and
  buffer/dead-slider violations, 1,319 unique IDs, Jest 464 pass / 1 skip, and
  `SKIP_WASM_BUILD=1` production build green. Real-GPU visual QA remains external.

## 2026-08-01 — WebGPU frame split (#1043)
- `src/renderer/webgpu/frame.ts` is now a **194 LOC** lifecycle facade (down from 873): RAF/media refresh, uniform writes, history-ring advancement, FPS, and top-level timing.
- New seams: `frameState.ts` for renderer-owned state adapters, `present.ts` for input scale/copy + canvas acquire/blit/submit, and `slotDispatch.ts` for parallel/chained/GraphRunner dispatch, quality caps, feedback copies, and compute timestamp phases.
- Contract stays fixed: when feedback uses both storage buffers, copy **B→C first, A→C last** so primary simulation state wins. The older pure `slotOrchestrator` model now agrees.
- Pure tests cover copy order, graph-vs-linear resolution, graph quality caps, blit cache invalidation, and generative present selection.
- Green proof: 68 Jest suites / 464 pass / 1 skip, TypeScript, focused ESLint, device + uniform policy sync, production CRA build, and 254.49 KiB gzip main bundle under 320 KiB.
- VM workaround: direct `tsx` may fail with `listen EPERM`; use `node --import tsx scripts/build-unified-manifest.ts`, then `npm run build --ignore-scripts` after lifecycle generation. Real GPU visual QA remains external.

## 2026-08-01 — Toolchain foundation (#1042)
- Phase 0 + low-risk Phase 1 guardrails landed locally: 320 KiB gzip main-chunk CI budget, explicit lazy `auto-dj` / `transformers` / `web-llm` checks, direct/alias dependency duplicate protection, and AI-loader source boundaries.
- Fresh baseline: main ~251.43 KiB gzip; Transformers ~175.76 KiB and WebLLM ~2,090.61 KiB remain excluded lazy chunks.
- Package/lock were already TypeScript 5.4.5; local install was stale at 4.9.5. After `npm ci`, `npx tsc --noEmit` passes with two narrow test-fixture typing updates.
- CRA 5's stale peer metadata still lists TypeScript only through 4.x (`npm ls` marks 5.4.5 invalid), but locked TS 5.4.5 passes both full typecheck and CRA/craco build. CI now runs the real typecheck; Vite remains the long-term peer-mismatch exit.
- `public/wasm/` is explicitly documented as the only deployable WASM artifact SoT; bridge source remains `wasm_renderer/bridge/*.js`. Device initialization was not changed.
- Removed tracked root junk `a.out.wasm`, `upg.zip`, `patch_wasm_final16.js`, and `fix_eslint2.py` (Git-recoverable). CRA→Vite remains a separate optional spike.
- Green proof: production build, 64 Jest suites / 428 pass / 1 skip, TypeScript 5.4 typecheck, device-policy sync, WASM validation, bundle/dependency gate, diff check.

## 2026-08-01 — Branch consolidation
- Audited all local/remote alternate branches vs `main`. Nearly everything useful was already merged (foundation waves, relay hops, MIDI, CORS/blank-after-scale, shader plans/impls).
- **Imported into main** (`0a74d08a`): celestial-lion + void-urchin plan files + queue pending entries (only unique orphans).
- **Closed junk PRs:** #995 (stale midi), #1020 (moth 397-file rewrite), #1053 (urchin draft after landing).
- **Deleted** all non-main local + remote branches and foundation worktrees. Repo is main-only.
- Left uncommitted Batch 21 WIP alone (moire / mouse-gravity / fireworks-edge-ignite).

## 2026-07-29 — Progress audit & next foundation wave
- **Board was empty** (July 26 closed #1007–#1031 tooling/content campaigns). Created **7 open issues** for next code foundation + product:
  - #1038 Uniforms SoT (`config.y` = **rippleCount**, not delta_time in agent docs)
  - #1043 finish `frame.ts` modularization (present/blit/slot dispatch)
  - #1039 real-GPU format-tier + multipass budget evidence
  - #1040 WASM Tier A go/no-go on discrete GPUs (stay B until then)
  - #1044 thumbs 27% → 80% (GPU waves; tooling already done)
  - #1041 multipass physics polish (ripple/fabric/caustics discoverability)
  - #1042 toolchain: TS upgrade, bundle budget, optional CRA→Vite
- **Strategic call:** foundation first (#1038, #1043) before another generative swarm; content flagship = multipass polish not more single-pass volume; WASM feature freeze until #1040.
- **Health at audit time:** device policy sync OK; format tiers in tree; dual Storage re-exports only; package dual-deps cleaned. Root junk noted here was removed by the 2026-08-01 toolchain pass above.


## WGSL cross-cutting improvements (2026-07-12 audit)
- **Engine wins (all shaders):** gate historyTex copy (only 11 use binding 13); reuse extraBuffer Float32Array; fix dataTexA/B→C double-copy in chained slots; merge queue submits; GPU image upload path.
- **Mouse Y convention (2026-07-19):** Removed erroneous `1.0 - y` flip in `WebGPURenderer.updateMouse` — `zoom_config.yz` is now canvas UV (0=top, 1=bottom), matching WASM + `WGSL_BUILTINS_GENERATIVE.md`. Patched ~70 WGSL files that had compensating `1.0 - zoom_config.z` / `1.0 - mouseUV.y` / `(0.5 - mouse.y)` flips. Script: `scripts/fix_mouse_y_compensation.py`.
- **Subgroup infra:** `-sg.wgsl` variant loader removed 2026-07-26; subgroup **feature** still requested when available for inline `enable subgroups` WGSL. TS timestamp-query **wired 2026-07-26** (feature request + ring-buffered readback + honesty gate `hasRealGpuTimings`).
- **Live rating API (2026-07-22):** `POST /api/shaders/{id}/rate` wants JSON `{ rating }` not FormData `{ stars }`. No `/api/shaders/{id}/play` on production. Use `postShaderRating()`.
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

## Progress audit 2026-07-22 — next moves

**Foundation vs content:** Wave 2 structure is good enough to ship product/content in parallel. Prioritize:
1. Small engine fixes (#1007 timestamp-query TS parity) before honest benches
2. Content: generative updatedParams (#1011), multipass physics on existing GraphRunner (#1009), thumbs on real GPU (#1012)
3. Hygiene: bundle/AI lazy load (#1010), WASM evidence when discrete GPU available (#1013)
4. Larger architecture: format tiering (#1008) before mobile-quality multipass

**Created issues:** #1007–#1013. Existing open: #976 attract/importer, #983/#984 gate (likely mostly done — verify before more work).

**Stale notes corrected:** CommunityGallery is mounted in `AiVjStudioPanel`; weekly_plan "unmounted" is outdated.

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

## Generative upgrade swarm — Batch 14 recovery (2026-07-22)
- Kimi completed shader/JSON edits for all 8 targets but stopped before the
  `spore-galaxy` note and integration closeout. Codex recovered and closed the batch.
- Targets: gen-bioelectric-pulse, gen_grok4_life, gen_reaction_diffusion,
  gravito-phononic-accretion, neural-mandala, phosphorescent-jellyfish, spore-galaxy,
  topological-acoustic-knots. Tracker entries #143–150; completed count now 150.
- Gate 8/8 green; JSON contracts preserved; shader lists and 1310-ID duplicate check clean;
  Jest 49 suites / 339 pass / 1 skip.
- Full Naga scan is 1314/1315. The only failure is unrelated/unmodified
  `gen-luminescent-aether-plasma-astro-axolotl.wgsl` (`invalid left-hand side of assignment`).
- `spore-galaxy` feedback fix is important: color now writes dataTextureA (host copies A→C
  last), masks write dataTextureB, enabling real color trails instead of mask-as-color feedback.
- No live visual QA in the headless VM; use real WebGPU hardware for look/slider tuning.

## Thumbnail coverage — corrected August 2026 baseline

- Nominal: **349/1,306 (26.7%)**; eligible: 1,305 after the justified `deep-workgroup-multi-effect-blend` hardware skip.
- The old Python PNG audit did not reverse row filters and over-reported failures. Correct decoding identifies **77 genuinely black thumbnails**, making healthy eligible coverage **272/1,305 (20.8%)** and the honest 80% backlog **772**.
- Always audit and force-regenerate invalid existing PNGs before `--missing` waves. Priority order: generative, simulation multipass, interactive-mouse, then remaining categories.
- Do not allowlist renderable failures to improve the denominator. CI remains reporting-only until healthy coverage reaches at least 50%.
- The current Cloud VM's production WebGPU probe produced a zero-energy frame, so batch generation requires a verified discrete-GPU host. See `reports/thumbnail-coverage-2026-08.md`.
