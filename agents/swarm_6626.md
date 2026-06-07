# Swarm Coordination — 2026-06-06

**Date:** 2026-06-06
**Focus:** Shift toward **upgrading & optimizing** existing generative shaders + building flagship showcase shaders.
**Philosophy:** Upgrade > Create new (we already have 320+ generative shaders).

---

## Sprint Status (end of Batch 2)

| Phase | Shaders | Status | Report |
|-------|--------:|:------:|--------|
| Batch 1 — ACES only | 10 | ✅ Done | `agents/swarm-outputs/batch-1-validation.md` |
| Metadata drift sweep | 97 | ✅ Done | `agents/swarm-outputs/metadata-drift-validation.md` |
| Batch 2 — full plumbing | 10 | ✅ Done | `agents/swarm-outputs/batch-2-validation.md` |
| **Total upgraded today** | **117** | ✅ | — |
| Batch 3D — multi-pass (Claude) | 5 | ✅ Done | `agents/swarm-outputs/claude-notes/*.claude-optimization.md` |
| Batch 3A/B/C | 24 | ✅ Done | `agents/swarm-outputs/batch-3*-validation.md` |
| Batch 4 — generative wave | 44 | 🚀 In Progress | 4A/4B done; 4C/4D/4E/4F in flight |

### Batch 2 highlights
- 10/10 naga pass; 4 JSON files synced with full feature stack
- Duplicate ACES caught in `gen-mandelbox-explorer`, `gen-apollonian-gasket`
- Heaviest lift: `atmos_volumetric_fog` (ACES + audio + temporal + chromatic + dataA from near-scratch)
- All notes: `agents/swarm-outputs/kimi-notes/` (Batch 2 set)

### Remaining generative gaps (post-Batch 2 audit)
| Gap | Count |
|-----|------:|
| Missing chromatic aberration | 169 |
| Missing `dataTextureA` write | 122 |
| Metadata drift (`upgraded-rgba` ↔ no ACES) | **0** |

---

## Strategic Priorities (This Week)

| Priority | Area | Goal | Owner |
|---------|------|------|-------|
| P1 | **Batch 4 Upgrades** | Audio (8) + mouse (8) + perf (5) + bass_env (8) + plumbing (5) | All models |
| P2 | **Showcase Quality** | 1–2 flagship showcase shaders as quality references | Kimi Claw |
| P3 | **Performance & Structure** | LOD, early-exit, duplicate-fn cleanup on upgraded shaders | Claude + Codex |
| P4 | **Audio Reactivity** | Consistent `bass_env` + param mapping across upgraded shaders | All |
| P5 | **Documentation** | Queue files, validation reports, showcase criteria | All |

**Deferred (separate sprint):** GitHub #799 WASM context, #800 shader gallery UI

| Priority | Area | Goal | Owner |
|---------|------|------|-------|
| P0 | **Flagship Deep Upgrade (F1)** | One generative shader per model — extensive, portfolio-grade | All models |

---

## Flagship Deep Upgrade — F1 (One Shader Per Model)

Each model receives **one** generative shader for an **extensive** upgrade — not a boilerplate sweep. Goal: produce four reference-quality shaders that demonstrate what each model does best, then extract patterns into `WGSL_BUILTINS_GENERATIVE.md`.

**Rules:**
- Disjoint from Batch 3A/B/C queue (no overlap with bulk assignments)
- Target **+30–80 lines** of meaningful change (not padding)
- Must pass `showcase-checklist-v1.md` readiness criteria
- Deliverable: upgraded WGSL + JSON + model-specific notes file
- Codex validates all four after delivery; models do not cross-edit each other's F1 shader

| Model | Shader ID | Lines | Gap today | Why this pick | Extensive upgrade mandate |
|-------|-----------|------:|-----------|---------------|---------------------------|
| **Kimiclaw** | `gen-auroral-ferrofluid-monolith` | 278 | No ACES, no dataA; has chromatic/audio/mouse | Signature sculptural effect — magnetic liquid + aurora; high showcase potential | Bass-driven glyph formation on ferrofluid spikes; mouse drag = external B-field rotation; full upgraded-rgba stack; `bass_env` not raw bass; semantic alpha on liquid membrane; 4 params with clear semantics |
| **Claude** | `gen-chronos-labyrinth` | ✅ 416→479 | Was: no dataA, no chromatic. Now: full stack | Largest raymarched generative — perf + atmosphere is Claude's lane | ✅ Delivered: distance-based ray-step LOD; early-exit skips calcNormal+calcAO (~11 map() calls) on fog-faded hits; temporal rift-echo memory in dataA↔dataC (afterglow "bleeds through time"); chromatic aberration on echo; huePreserveClamp + existing IGN dither. fps-gain analysis in notes file |
| **Codex** | `gen-liquid-crystal-hive-mind` | 327 | No ACES, dataA, chromatic, or audio | Nearly bare plumbing — ideal reference for structural correctness | Full stack from scratch; rename/consolidate duplicate helpers; JSON↔header feature sync; fix any binding drift; produce the **gold validation report** other shaders are measured against; `.codex-fix.md` only if needed |
| **Kimi** | `gen-celestial-forge` | 420 | No dataA, no chromatic; has ACES/audio/mouse | Flagship cosmic forge — orchestrator synthesizes best patterns from all agents | Compare F1 outputs from other three models; apply best chunks (bass_env, mouse attractor, LOD comments); multi-layer compositing (forge core + stellar sparks + depth halo); write new canonical chunks back to `WGSL_BUILTINS_GENERATIVE.md` |

### F1 Deliverables (per model)

| Model | WGSL | JSON | Notes file |
|-------|------|------|------------|
| Kimiclaw | `public/shaders/gen-auroral-ferrofluid-monolith.wgsl` | `shader_definitions/generative/gen-auroral-ferrofluid-monolith.json` | `agents/swarm-outputs/kimi-notes/gen-auroral-ferrofluid-monolith.notes.kimiclaw.md` |
| Claude | `public/shaders/gen-chronos-labyrinth.wgsl` ✅ | `shader_definitions/generative/gen-chronos-labyrinth.json` ✅ | `agents/swarm-outputs/claude-notes/gen-chronos-labyrinth-f1.claude-optimization.md` ✅ |
| Codex | `public/shaders/gen-liquid-crystal-hive-mind.wgsl` | `shader_definitions/generative/gen-liquid-crystal-hive-mind.json` | `agents/swarm-outputs/codex-notes/gen-liquid-crystal-hive-mind.codex-reference.md` |
| Kimi | `public/shaders/gen-celestial-forge.wgsl` | `shader_definitions/generative/gen-celestial-forge.json` | `agents/swarm-outputs/kimi-notes/gen-celestial-forge.notes.kimi.md` |

### F1 Acceptance Criteria (all four)

- [ ] Full upgraded-rgba stack: ACES + chromatic + temporal + dataA write + semantic alpha
- [ ] Audio: `plasmaBuffer[0]` drives ≥2 visual parameters via `bass_env` (not raw bass strobing)
- [ ] Mouse: `u.zoom_config.yz` affects ≥2 parameters (not just vignette)
- [ ] `writeDepthTexture` stores meaningful depth (not passthrough 0.0)
- [ ] Header `Features:` matches JSON `features` exactly
- [ ] naga pass + `generate_shader_lists.js` pass
- [ ] Passes `agents/showcase-checklist-v1.md` (12s rotation ready)
- [ ] Notes file documents before/after line count + what changed + why

### F1 Schedule

```
Parallel (after Batch 3A validates, or immediately if capacity):
  Kimiclaw → gen-auroral-ferrofluid-monolith
  Claude   → gen-chronos-labyrinth
  Codex    → gen-liquid-crystal-hive-mind
    ↓ (all three delivered)
  Kimi     → gen-celestial-forge (synthesizes F1 patterns)
    ↓
  Codex    → F1 validation report → agents/swarm-outputs/flagship-f1-validation.md
```

---

## Batch 3 Launch Queue

Machine-readable: [`agents/swarm-tasks/batch-3-queue.json`](swarm-tasks/batch-3-queue.json)

### 3A — Chromatic only (4 shaders) · Kimiclaw · **NEXT**

Already have ACES + dataA + temporal. Add chromatic chunk only.

| # | Shader ID |
|---|-----------|
| 1 | `gen-translucent-nebula` |
| 2 | `gen-alpha-aurora` |
| 3 | `gen-ghost-flame` |
| 4 | `gen-prismatic-crystal-growth` |

> `electric-eel-storm` excluded — chromatic added in Batch 2.

### 3B — dataTextureA plumber (10 shaders) · Kimiclaw · after 3A

Reads `dataTextureC` but missing `textureStore(dataTextureA, ...)`.

| # | Shader ID |
|---|-----------|
| 1 | `gen-bioluminescent-abyss` |
| 2 | `cosmic-jellyfish` |
| 3 | `cosmic-web` |
| 4 | `gen-3d-sierpinski-chaos` |
| 5 | `gen-4d-projection-dream-weavers` |
| 6 | `gen-abyssal-chrono-coral` |
| 7 | `gen-abyssal-leviathan-scales` |
| 8 | `abyssal-quantum-leviathan-skeleton` |
| 9 | `gen-alien-flora` |
| 10 | `gen-art-deco-sky` |

### 3C — Chromatic sweep (10 shaders) · Kimiclaw · after 3B

Repurposed: ACES-gap batch is empty (drift = 0). Target shaders with ACES + dataA but no chromatic.

| # | Shader ID |
|---|-----------|
| 1 | `aurora-curtain` |
| 2 | `bioluminescent-bloom` |
| 3 | `gen-belousov-zhabotinsky` |
| 4 | `gen-bio-luminescent-jelly` |
| 5 | `gen-celestial-nanite-swarm-nebula` |
| 6 | `gen-crystal-lattice-growth` |
| 7 | `gen-crystalline-mandala-bloom` |
| 8 | `gen-dla-copper-deposition` |
| 9 | `gen-dynamic-tessellation-ornate-fractal-tiles` |
| 10 | `gen-fourier-epicycles` |

### 3D — Multi-pass flagships (5 shaders) · Claude · ✅ Done

| # | Shader ID | Notes |
|---|-----------|-------|
| D1 | `gen_reaction_diffusion` | RD state in dataA |
| D2 | `gen-murmuration-phantom` | extraBuffer flock (also Batch 2) |
| D3 | `gen-navier-stokes-ink` | Velocity advection |
| D4 | `gen-belousov-zhabotinsky` | Multi-scale RD |
| D5 | `gen-conway-game-of-life` | CA state bug fix + generation counter |

### 3E — Polish pass (3 shaders) · Claude · **Blocked on 3A**

| # | Shader ID | Blocked on |
|---|-----------|------------|
| E1 | `gen-translucent-nebula` | Kimiclaw 3A + `.notes.kimiclaw.md` |
| E2 | `gen-prismatic-crystal-growth` | Kimiclaw 3A + `.notes.kimiclaw.md` |
| E3 | `electric-eel-storm` | Kimiclaw notes (chromatic done; needs LOD polish) |

---

## Batch 4 — Generative Upgrade Wave (Per Model)

Next wave after Batch 3 + F1. Each model owns a **different upgrade dimension** so work stays parallel and non-overlapping.

| Track | Owner | Focus | Count |
|-------|-------|-------|------:|
| **4A** | Kimiclaw | Audio reactivity injection (missing `plasmaBuffer` in `main`) | 8 |
| **4B** | Kimiclaw | Mouse interaction pass (no `zoom_config.yz` usage) | 8 |
| **4C** | Claude | Heavy raymarcher LOD + early-exit | 5 |
| **4D** | Claude | `bass_env` migration (raw bass → envelope) | 8 |
| **4E** | Codex | Full-stack plumbing on high-line-count bare shaders | 5 |
| **4F** | Codex | JSON `params` semantics audit on upgraded generative | 10 |
| **4G** | Kimi | Batch 4 queue + `bass_env` canonical chunk in builtins | — |

### 4A — Audio injection (Kimiclaw)

Shaders with bindings declared but **no audio reads in `main()`**:

| # | Shader ID |
|---|-----------|
| 1 | `gen-bioluminescent-aether-jellyfish-swarm` |
| 2 | `gen-bifurcation-diagram` |
| 3 | `gen-bismuth-crystal-citadel` |
| 4 | `gen-brutalist-monument` |
| 5 | `gen-cosmic-slime-mold` |
| 6 | `gen-electric-kaleidoscope-storm` |
| 7 | `gen-isometric-city` |
| 8 | `gen-inverse-mandelbrot` |

**Mandate:** `bass` modulates scale/brightness; `mids` modulates speed/morph; `treble` modulates sparkle/grain. Use `bass_env` not raw `plasmaBuffer[0].x`.

### 4B — Mouse interaction (Kimiclaw)

Generative shaders with **no mouse position** in the algorithm (vignette-only doesn't count):

| # | Shader ID |
|---|-----------|
| 1 | `gen-zeta-function-landscape` |
| 2 | `gen-torus-knot-rainbow` |
| 3 | `gen-worley-cellular-noise` |
| 4 | `gen-sierpinski-tetrahedron` |
| 5 | `gen-percolation-threshold` |
| 6 | `gen-thermal-rainbow-topography` |
| 7 | `gen-singularity-forge` |
| 8 | `gen-rainbow-firefly-dance` |

**Mandate:** Mouse as attractor, repulsor, or field rotation — affect ≥2 visual parameters.

### 4C — Raymarch perf (Claude)

| # | Shader ID | Lines |
|---|-----------|------:|
| 1 | `gen-biomechanical-hive` | 356 |
| 2 | `gen-ethereal-anemone-bloom` | 386 |
| 3 | `gen-holographic-data-core` | 383 |
| 4 | `fractal-ice-palace` | 289 |
| 5 | `gen-celestial-prism-orchid` | 409 |

**Mandate:** Distance LOD on ray steps/noise octaves; early exit; document map() call reduction in notes.

### 4D — bass_env migration (Claude)

Batch 1 shaders with raw `plasmaBuffer[0].x` strobing — upgrade to envelope:

| # | Shader ID |
|---|-----------|
| 1 | `gen-celestial-weave` |
| 2 | `gen-magnetic-kelp` |
| 3 | `gen-vortex-cathedral` |
| 4 | `gen-luminous-cauldron` |
| 5 | `gen-neon-snowfall` |
| 6 | `gen-bioreactor-bloom` |
| 7 | `gen-opal-circuit` |
| 8 | `holographic-crystal` |

**Mandate:** Store previous envelope in `dataTextureA.r`; attack 0.8 / release 0.15.

### 4E — Full-stack plumbing (Codex)

High line-count shaders missing most of upgraded-rgba stack:

| # | Shader ID | Lines | Missing |
|---|-----------|------:|---------|
| 1 | `gen-biomechanical-hive` | 356 | dataA, chromatic |
| 2 | `gen-ethereal-anemone-bloom` | 386 | dataA, chromatic |
| 3 | `gen-holographic-data-core` | 383 | dataA, chromatic |
| 4 | `gen-neon-tropical-paradise` | 372 | dataA, chromatic |
| 5 | `gen-celestial-prism-orchid` | 409 | dataA, chromatic |

**Note:** Claude handles 4C perf on overlapping IDs; Codex does plumbing first, Claude polishes after.

### 4F — JSON params audit (Codex)

Verify `params` in JSON match what `u.zoom_params` actually controls in WGSL for these upgraded shaders:

`gen-protocell-division`, `gen-erosion-strata`, `atmos_volumetric_fog`, `gen-murmuration-phantom`, `neural-mandala`, `coral-growth`, `mycelium-network`, `gen-mandelbox-explorer`, `gen-apollonian-gasket`, `gen_cyclic_automaton`

---

## Agent Task Board

### Kimi Claw
**Role:** Bulk Batch 3 implementation + showcase shader creation
**Instructions:** [`agents/swarm-tasks/kimiclaw_6626.md`](swarm-tasks/kimiclaw_6626.md)

| Task | Status | Batch | Shaders | Notes |
|------|--------|-------|---------|-------|
| **3A chromatic** | ✅ Done | 3A | 4 | Highest impact, lowest risk — launch first |
| **3B dataTextureA** | ✅ Done | 3B | 10 | Validated 2026-06-06, 10/10 naga pass |
| **3C chromatic sweep** | ✅ Done | 3C | 10 | Validated 2026-06-06, 10/10 naga pass, 0 duplicate ACES |
| Write `.notes.kimiclaw.md` per shader | ✅ Done | all | 25 | 24 Batch 3 + 1 F1. Also caught & fixed 3 duplicate ACES in Batch 3C |
| Generate **Ethereal Silk** showcase | ✅ Done | showcase | 1 new | `gen-ethereal-silk-veil` — naga validated, 4 params, full stack |
| Generate **Fractal Ember** showcase | ✅ Done | showcase | 1 new | `gen-fractal-ember-lattice` — agent swarm synthesized, naga validated |
| Create `prompt-showcase-batch-1.md` | ✅ Done | docs | — | Created 2026-06-07 |
| Create `showcase-checklist-v1.md` | ✅ Done | docs | — | Created 2026-06-07 |
| Review showcase audio param mapping | Backlog | showcase | — | zoom_params 1–4 semantics |
| Optimize **Molten Gold** (upgrade pass) | Backlog | showcase | 1 | Improve performance, audio reactivity, and visual flourish. Use as flagship reference |
| Define "Flagship Showcase Shader" criteria | To Do | docs | — | What makes a shader worth promoting as a showcase reference |
| **F1 flagship: `gen-auroral-ferrofluid-monolith`** | ✅ Done | F1 | 1 | Extensive creative upgrade — see Flagship section |
| Extract F1 chunks → `WGSL_BUILTINS` | Backlog | F1 | — | After Kimi synthesizes `gen-celestial-forge` |
| 3B dataA spot-check (5 cosmetic gaps) | To Do | 3B+ | 5 | Pick 5 from the ~119 cosmetic-gap remainder Claude triaged out (no `dataTextureC` read dependency) — quick wins, low risk |
| Audit 3C chromatic targets for ACES dupes | ✅ Done | 3C | 10 | Pre-flight check before Codex validation — flag any `acesToneMap`/`aces_tonemap` stacking before writing the pass |
| Generate 3rd showcase shader | Backlog | showcase | 1 new | Follow `prompt-showcase-batch-1.md` + `showcase-checklist-v1.md`; gold ref `gen-protocell-division.wgsl` |
| Write showcase notes for new shaders | ✅ Done | showcase | 2 | Add/verify `.notes.kimi*.md` coverage for `gen-ethereal-silk-veil` and `gen-fractal-ember-lattice` with validation commands and param mapping |
| F1 audio polish follow-up | To Do | F1 | 1 | Re-check `gen-auroral-ferrofluid-monolith` against F1 audio criteria after Codex validation flags any gaps |
| 3A handoff package | ✅ Done | 3A | 4 | For each 3A shader, include exact changed lines + before/after feature list so Codex can validate without re-triage |
| **4A audio injection** | ✅ Done | 4A | 7 | 7/8 needed work; `gen-bifurcation-diagram` already had audio. Report: `batch-4a-4b-validation.md` |
| **4B mouse interaction** | ✅ Done | 4B | 2 | 2/8 needed work; 6 already had meaningful mouse. Report: `batch-4a-4b-validation.md` |
| **4A′ chromatic sweep #3** | Backlog | 4 | 10 | Next 10 generative with ACES+dataA but no chromatic (after 4A/4B) |
| **4B′ dataA cosmetic gaps** | Backlog | 4 | 5 | Quick `textureStore(dataTextureA)` on shaders with no `dataTextureC` dependency |
| Upgrade `gen-hypnotic-vortex-tunnel` | Backlog | 4 | 1 | Has stack but weak mouse — good single-shader creative pass |
| Write `.notes.kimiclaw.md` for Batch 3 | ✅ Done | 3 | 24 | All 24 files written + 3 duplicate ACES fixed |

**Invocation:** `kimi-cli --no-stream` · max 2 shaders per call · gold reference: `gen-protocell-division.wgsl`

---

### Claude
**Role:** Multi-pass architecture + performance polish + second-pass transcendence
**Instructions:** [`agents/swarm-tasks/claude_6_6_26.md`](swarm-tasks/claude_6_6_26.md)

| Task | Status | Batch | Shaders | Notes |
|------|--------|-------|---------|-------|
| **3D multi-pass** | ✅ Done | 3D | 5 | Notes in `claude-notes/` |
| **3B Priority B continuation** | In Progress | 3B+ | 3 done / next 10 | Jumped ahead on highest-impact bug-fix picks (disjoint from Kimiclaw's 10): `gen-langton-ant` (state was leaking into visible writeTexture — visual glitch + broken sim), `gen-turing-morphogenesis`, `gen-lichen-reaction-diffusion` (both had dead `prev.rgb` persistence feedback loops). Notes in `claude-notes/`. ~119 dataA gaps remain, mostly cosmetic (no `dataTextureC` read dependency). |
| Performance audit (frequent shaders) | Backlog | P3 | TBD | LOD, early-exit, branchless paths |
| Duplicate function cleanup | Backlog | P3 | Batch 3 touched | `aces_tonemap` vs `acesToneMap` pattern |
| **F1 flagship: `gen-chronos-labyrinth`** | ✅ Done | F1 | 1 | 416→479 lines (+64, within mandate). Distance-LOD ray stride, early-exit on fog-faded hits (skips 11 map() calls), temporal rift-echo memory in dataA/dataC, chromatic aberration on echo, huePreserveClamp. Notes: `claude-notes/gen-chronos-labyrinth-f1.claude-optimization.md` |
| Document F1 perf benchmarks | To Do | F1 | 1 | Before/after texture samples + ray steps in notes file |
| Help with `dataTextureA` writeback fixes | To Do | 3B | 10 | Support Kimiclaw on Priority B shaders |
| Apply new Psychedelic Utilities to upgraded shaders | Backlog | P3 | — | Ready after builtins update |
| Start planning **Batch 4** (multi-pass + advanced temporal) | Backlog | — | — | Identify candidates for true multi-pass upgrades. After Batch 3 stabilizes |
| Run validation pass | Ongoing | — | naga + feature flag + JSON sync check | After each batch |
| **Batch 5 — full-stack upgrade (Claude)** | ✅ Done | 5 | 12/12 | Self-selected via discovery script (CLOUD_UPGRADE.md §5.1, score≥12, ≤200L, has JSON, not in Linear-active list). Cohort A (5, score 15 — full stack from scratch): `gen-fractal-bioluminescence-spore-network`, `gen-kryonic-quantum-aether-fractal-core`, `gen-eldritch-quantum-fractal-eye`, `gen-hyper-dimensional-tesseract-labyrinth`, `gen-holographic-plasma-geode` — migrated legacy `u.config.y` "audio" anti-pattern → real `plasmaBuffer[0].xyz` bass/mids/treble, replaced hardcoded `vec4(col,1.0)` with semantic alpha, added `writeDepthTexture` + `dataTextureA` writes, synced headers/JSON. Cohort B (7, score 12 — dataA + tag sync): `gen-quasicrystal`, `gen-string-theory`, `gen-nebular-chrono-astrolabe`, `gen-graviton-plasma-lotus`, `gen-quantum-aether-origami`, `gen-voronoi-crystal`, `gen-xeno-botanical-synth-flora` — added `dataTextureA` writes + `upgraded-rgba`/`temporal`/`depth-aware` tags; also fixed 2 hardcoded-alpha branches in `gen-quantum-aether-origami`. All `naga` ✅ (12/12) + `generate_shader_lists.js` + `check_duplicates.js` (1130/1130 unique). Notes: `claude-notes/batch-5-full-stack-upgrade.claude-optimization.md`. |
| **4C raymarch perf** | To Do | 4C | 5 | LOD + early-exit on heavy generative raymarchers — see Batch 4 table |
| **4D bass_env migration** | ✅ Done | 4D | 8/8 | All 8 migrated: `gen-celestial-weave`, `gen-magnetic-kelp`, `gen-vortex-cathedral`, `gen-luminous-cauldron`, `gen-neon-snowfall`, `gen-bioreactor-bloom`, `gen-opal-circuit`, `holographic-crystal`. Added/reused `bass_env(prev,bass,attack,release)` (attack 0.8/release 0.15); envelope stored in `extraBuffer[0]` (deviation from `dataTextureA.r` mandate — those shaders already pack RGBA state there; see notes for rationale). 24 raw-bass call sites migrated to `smoothBass`. All `naga` ✅ + `generate_shader_lists.js` + `check_duplicates.js` (1130/1130 unique). Notes: `claude-notes/batch-4d-bass-env-migration.claude-optimization.md`. |
| **3E polish E1–E3** | ✅ Done | 3E | 3/3 done | E1 `gen-translucent-nebula` ✅: distance layer-LOD (8→5), branchless `hueToRGB`, `bass_env`-driven CA, feature sync. E2 `gen-prismatic-crystal-growth` ✅: ray-step LOD (`mix(0.7,1.0,...)`), caustics early-exit gate (`causticStrength*thickness>0.04`), branchless `hueToRGB`, `bass_env`-driven CA, `distance-lod` added. E3 `electric-eel-storm` ✅: added missing `bass_env` (envelope in `extraBuffer[3]`, attack 0.08/release 0.02) routed through 4 call sites, eel-loop early-exit gate (`length(uv-eelPos)<0.35`), distance-based octave LOD on `stormCloud` (4→2 / 3→2), `distance-lod` + `upgraded-rgba` feature sync. All 3 validated via `naga` + `generate_shader_lists.js` + `check_duplicates.js` (1130/1130 unique). Notes in `claude-notes/`. 3E polish pass complete. |
| Upgrade `gen-audiovisual-mandelbulb-raymarcher` | Backlog | 4 | 1 | Missing dataA + chromatic; natural follow-on to 4C perf patterns |
| Multi-pass: `gen-astro-kinetic-chrono-orrery` | Backlog | 4 | 1 | Orbital state in dataA; time-dilated trails via dataC |
| Apply psychedelic utilities to 4D batch | Backlog | 4 | 8 | `psychedelicPalette` / `organicDrift` on bass_env-upgraded shaders |

**Do not touch** Kimiclaw in-progress shaders until `.notes.kimiclaw.md` exists.
**F1 exception:** `gen-chronos-labyrinth` is Claude-owned regardless of batch queues.

---

### Codex
**Role:** Validation gate + edge-case repair + batch reports
**Instructions:** [`agents/swarm-tasks/codex_6626.md`](swarm-tasks/codex_6626.md)

| Task | Status | Details | Notes |
|------|--------|---------|-------|
| Validate **Batch 3A** (4 shaders) | To Do | naga + feature flags + JSON sync | Gate before 3B starts |
| Validate **Batch 3B** (10 shaders) | To Do | dataA writeback + temporal consistency | |
| Validate **Batch 3C** (10 shaders) | ✅ Pre-validated | chromatic + no duplicate ACES | All 10 pass; report in `batch-3c-validation.md` |
| Write `batch-3-validation.md` | ✅ Done | Combined 3A+3B+3C reports | `batch-3a-validation.md`, `batch-3b-validation.md`, `batch-3c-validation.md` |
| Metadata drift re-sweep | To Do | Confirm drift = 0 post-Batch 3 | Run audit script |
| Edge-case fixes | Ongoing | Complex `vec4<f32>()` ACES wrap, `let` reassignment | `.codex-fix.md` per fix |
| Logical structure cleanup | Backlog | Dead code, duplicate fns in Batch 3 shaders | After validation pass |
| Performance pattern audit | Backlog | Flag shaders with >8 texture loads/pixel | Feed to Claude |
| Add Psychedelic Utilities to `WGSL_BUILTINS_GENERATIVE.md` | ✅ Done | Added reusable color/motion helpers for Batch 4 | `psychedelicPalette`, `neonGlow`, `organicDrift`, `pulseScale`; `chromaticAberration` already existed |
| Apply new Psychedelic Utilities across upgraded shaders | Backlog | Batch-apply functions from WGSL_BUILTINS_GENERATIVE.md | Ready after builtins update |
| Performance profiling on top 20 generative shaders | Backlog | Identify biggest performance wins | Use showcase rotation as benchmark |
| **F1 flagship: `gen-liquid-crystal-hive-mind`** | ✅ Done | Full stack + structural reference quality | `naga` pass; feature/JSON sync pass; note: `codex-notes/gen-liquid-crystal-hive-mind.codex-reference.md` |
| **F1 validation report** | To Do | `flagship-f1-validation.md` after all F1 delivered | Score all 4 flagships |
| Compare F1 vs showcase checklist | To Do | Score each against `showcase-checklist-v1.md` | After F1 complete |
| **4E full-stack plumbing** | To Do | 4E | 5 | dataA + chromatic + temporal on high-line-count bare shaders |
| **4F JSON params audit** | To Do | 4F | 10 | Verify `zoom_params` ↔ slider labels on Batch 2/3 upgraded shaders |
| Validate **Batch 4A** (8 shaders) | To Do | 4A | 8 | Audio + bass_env gate after Kimiclaw |
| Validate **Batch 4B** (8 shaders) | To Do | 4B | 8 | Mouse interaction gate after Kimiclaw |
| Write `batch-4-validation.md` | To Do | 4 | — | After 4A–4F complete |
| Generative `bass_env` coverage audit | To Do | 4 | all | Count upgraded generative using raw bass vs envelope; feed Claude 4D |
| Flag duplicate helper functions | To Do | 4 | — | `hash12`/`h2`/`noise` redeclarations across generative — dedup candidates |

**Edge cases to watch** (learned from Batch 2):
- Duplicate ACES (`acesToneMap` stacked on `aces_tonemap`)
- `dataTextureC` read without `dataTextureA` write
- Header `Features:` ≠ JSON `features`

---

### Kimi (Orchestrator)
**Role:** Pattern synthesis + documentation + flagship capstone
**Instructions:** [`agents/swarm-tasks/kimi_6_6_26.md`](swarm-tasks/kimi_6_6_26.md)

| Task | Status | Batch | Details |
|------|--------|-------|---------|
| **F1 flagship: `gen-celestial-forge`** | To Do | F1 | Extensive upgrade after Kimiclaw/Claude/Codex F1 siblings land |
| Synthesize F1 patterns → `WGSL_BUILTINS_GENERATIVE.md` | To Do | F1 | New chunks: bass_env, mouse B-field, raymarch LOD stub |
| Write `gen-celestial-forge.notes.kimi.md` | To Do | F1 | Document which agent patterns were adopted and why |
| Maintain `batch-3-queue.json` | Ongoing | — | Keep queue in sync with this file |
| Review F1 vs showcase shaders | Backlog | F1 | Compare `gen-ethereal-silk-veil`, `gen-fractal-ember-lattice` against F1 outputs |
| **Define Batch 4 queue JSON** | To Do | 4G | Write `agents/swarm-tasks/batch-4-queue.json` from Batch 4 tables |
| **Add `bass_env` canonical chunk** | To Do | 4G | Document in `WGSL_BUILTINS_GENERATIVE.md` with attack/release defaults |
| **Plan Batch 5 targets** | Backlog | 5 | Remaining ~145 no-chromatic + ~110 no-dataA generative shaders |
| Upgrade `gen-gravitational-strain` | Backlog | 4 | 1 | Strong visual, partial stack — good orchestrator spot-check |
| Extract cross-agent patterns post-F1 | To Do | F1 | Document winning patterns from Kimiclaw/Claude/Codex F1 in builtins |
| Coordinate 4E→4C handoff | To Do | 4 | Codex plumbs 4E shaders first; Claude runs 4C perf after Codex validates |

---

### Shared / Coordination Tasks

| Task | Status | Owner | Details |
|------|--------|-------|---------|
| Create & maintain `swarm_6626.md` | ✅ Done | — | This file |
| Define "Showcase Readiness" criteria | To Do | All | What makes a shader good for 12s rotation |
| Update `WGSL_BUILTINS_GENERATIVE.md` if needed | Backlog | — | Add new patterns discovered during upgrades |
| Review GitHub Issues #799, #800, #801 | To Do | — | Decide priority vs current work |
| Create "Generative Shader Upgrade Playbook" | Backlog | All | Document standard upgrade steps (performance, temporal, audio, visual) |
| Establish performance benchmark for Showcase | To Do | All | Define acceptable FPS + visual quality bar for rotation mode |
| E1–E3 handoff notes | ✅ Done | Kimi Claw → Claude | `agents/swarm-outputs/kimi-notes/e1-e3-handoff-claude.md` |

---

## Launch Sequence

```
Batch 2 ✅ (117 shaders)
    ↓
Kimiclaw 3A (4) ──→ Codex validate ──→ unblocks Claude 3E
    ↓
Kimiclaw 3B (10) ──→ Codex validate
    ↓
Kimiclaw 3C (10) ──→ Codex validate ──→ batch-3-validation.md
    ↓
Claude 3E polish (3) + 3B continuation
    ↓
┌── F1 Flagship Deep Upgrade (parallel after 3A validates) ──────────────┐
│  Kimiclaw → gen-auroral-ferrofluid-monolith                          │
│  Claude   → gen-chronos-labyrinth                                    │
│  Codex    → gen-liquid-crystal-hive-mind                             │
│       ↓ (all three delivered)                                        │
│  Kimi     → gen-celestial-forge (synthesizes F1 patterns)            │
│       ↓                                                              │
│  Codex    → flagship-f1-validation.md                                │
└──────────────────────────────────────────────────────────────────────┘
    ↓
Batch 4 (parallel tracks):
  Kimiclaw 4A (audio, 8) + 4B (mouse, 8)
  Codex    4E (plumbing, 5) → 4F (params audit, 10)
  Claude   4D (bass_env, 8) + 4C (raymarch perf, 5) after 4E validates
```

**Parallel OK:** Batch 4 tracks are disjoint by dimension · Claude 4C waits on Codex 4E for overlapping IDs

---

## Reference Documents

| Doc | Purpose |
|-----|---------|
| [`kimi_6_6_26.md`](swarm-tasks/kimi_6_6_26.md) | Master plan + reusable WGSL chunks |
| [`kimiclaw_6626.md`](swarm-tasks/kimiclaw_6626.md) | Kimi Claw implementation lane |
| [`codex_6626.md`](swarm-tasks/codex_6626.md) | Validation + edge-case repair |
| [`claude_6_6_26.md`](swarm-tasks/claude_6_6_26.md) | Multi-pass + polish lane |
| [`batch-3-queue.json`](swarm-tasks/batch-3-queue.json) | Machine-readable shader assignments |
| [`WGSL_BUILTINS_GENERATIVE.md`](WGSL_BUILTINS_GENERATIVE.md) | Core standards + canonical chunks |
| [`agents/prompt-showcase-batch-1.md`](prompt-showcase-batch-1.md) | Showcase generation prompt |
| [`agents/showcase-checklist-v1.md`](showcase-checklist-v1.md) | 12s rotation quality gate |
| [`batch-2-validation.md`](swarm-outputs/batch-2-validation.md) | Latest completed batch report |
| [GitHub #801](https://github.com/ford442/image_video_effects/issues/801) | Batch 3 tracking issue |

**Gold reference shader:** `public/shaders/gen-protocell-division.wgsl` (Batch 2 upgraded-rgba stack)

---

## Validation Commands (orchestrator)

```bash
# Per shader
naga public/shaders/{shader-id}.wgsl

# After each sub-batch
node scripts/generate_shader_lists.js
node scripts/check_duplicates.js

# Drift check
node -e "
const fs=require('fs'),path=require('path');
let d=0;
for(const dir of fs.readdirSync('shader_definitions')){
  const p=path.join('shader_definitions',dir);
  if(!fs.statSync(p).isDirectory()) continue;
  for(const f of fs.readdirSync(p).filter(x=>x.endsWith('.json'))){
    const j=JSON.parse(fs.readFileSync(path.join(p,f)));
    if(!(j.features||[]).includes('upgraded-rgba')) continue;
    const w=fs.readFileSync(path.join('public',j.url),'utf8');
    if(!/fn acesToneMap|aces_tonemap/i.test(w)) d++;
  }
}
console.log('drift:',d);
"
```

---

## Notes / Decisions

- Upgrade > create: 117 shaders upgraded today; Batch 3 adds 24 more before new showcase work.
- Batch 3C repurposed from empty ACES-gap list — drift is 0 after metadata sweep.
- `electric-eel-storm` removed from 3A (chromatic done in Batch 2); stays in Claude 3E for LOD polish.
- `gen-belousov-zhabotinsky` appears in both 3C (Kimiclaw chromatic) and 3D (Claude multi-pass) — Claude done; Kimiclaw adds chromatic only if missing after audit.
- Showcase files (`prompt-showcase-batch-1.md`, `showcase-checklist-v1.md`) created on 2026-06-07.
- Performance and logical cleanliness are now explicit upgrade criteria alongside feature completeness.
- **F1 flagship picks** are disjoint from Batch 3 bulk queue — each model gets one shader for extensive, portfolio-grade work.
- Kimi's `gen-celestial-forge` runs **last** so it can synthesize patterns from the other three F1 deliveries.

---

**Next Sync:** After **F1 capstone** (`gen-celestial-forge`) + **Batch 4A first sub-batch** (4 shaders).

**Immediate action:** Codex F1 (`gen-liquid-crystal-hive-mind`) → Kimi F1 capstone → launch Kimiclaw 4A.
