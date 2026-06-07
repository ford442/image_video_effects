# Composer Plan — Generative Shader Upgrade Sprint

**Date:** 2026-06-06  
**Scope:** Upgrade generative WGSL shaders to `upgraded-rgba` standard  
**Category:** `generative` (317 shaders)  
**Constraint:** Shader authors only — do NOT modify `Renderer.ts`, `types.ts`, or bind groups.

---

## Executive Summary

The generative category is the largest in Pixelocity (317 shaders) and the primary focus for today's upgrade sprint. Infrastructure is solid (`CLOUD_UPGRADE.md`, `WGSL_BUILTINS_GENERATIVE.md`, batch JSON files, kimi-notes workflow). The main gaps are **execution consistency**: JSON tags ahead of code, ACES at ~14%, and hardcoded alpha almost everywhere.

**Today's goals:**
1. Ship Batch 1 (10 shaders — ACES + semantic alpha only)
2. Fix metadata drift (107 false `upgraded-rgba` tags)
3. Execute Batch 2 (10 shaders — full plumbing pass)
4. Open GitHub epic + child issues for tracking

---

## Current State Audit

| Metric | Count | Notes |
|--------|------:|-------|
| Total generative shaders | 317 | Largest category |
| `upgraded-rgba` in JSON | 124 | — |
| Actual `acesToneMap` in WGSL | 44 | **107 metadata drift** |
| Missing ACES entirely | 273 | Primary backlog |
| Chromatic aberration | 131 | ~186 still flat |
| Reads `dataTextureC` | 317 | All have temporal read binding |
| Writes `dataTextureA` | 189 | **128 missing writeback** |
| Hardcoded `alpha = 1.0` | 307 | Almost universal |
| `bass_env` smoothing | 6 | Underused, high value |
| Legacy `(8, 8, 1)` workgroup | 8 | Do not change unless sim requires it |

### Metadata Drift

107 shaders have `"upgraded-rgba"` in JSON but no `acesToneMap` / `toneMapACES` in WGSL. Examples:

- `gen-celestial-weave`, `gen-magnetic-kelp`, `gen-vortex-cathedral`
- `gen-neon-snowfall`, `gen-bioreactor-bloom`, `mycelium-network`
- `gen-stardust-nebula`, `gen-plasma-mandala`, `gen-cyclic-automaton`

**Rule:** Only tag `upgraded-rgba` when ACES is present in WGSL.

### Gold Template Shaders

Copy structure from these — they have all modern features:

| Shader | Lines | Why |
|--------|------:|-----|
| `gen-conway-game-of-life` | 137 | Short, complete CA + ACES + chromatic + semantic alpha |
| `gen-langton-ant` | 137 | Emergent patterns + heat-map trails |
| `gen-turing-morphogenesis` | 146 | Reaction-diffusion + depth-aware scale |
| `gen-alpha-aurora` | 292 | Rich flourish: curl noise, spectral color, `bass_env` |
| `gen-dragon-curve` | — | IFS + ACES |
| `gen-barnsley-fern` | — | IFS + ACES |
| `gen-worley-cellular-noise` | — | Worley FBM + chromatic |
| `gen-lorenz-attractor` | — | Attractor flow + audio |

---

## Reference Documents

| File | Purpose |
|------|---------|
| `agents/CLOUD_UPGRADE.md` | Upgrade standard, scoring, workflow |
| `agents/WGSL_BUILTINS_GENERATIVE.md` | Canonical chunks, template, anti-patterns |
| `shader_plans/generative_upgrades.md` | Scientific visual upgrade paths |
| `upgrade_batches/batch_1_generative.json` | Batch 1 targets (ACES-only) |
| `upgrade_batches/batch_2_generative.json` | Batch 2 targets (full plumbing) |
| `AUDIT_REPORT.md` | Repo-wide audit (2026-05-31) |
| `AGENTS.md` | Immutable infrastructure rules |

---

## Techniques / Functions / Constants to Include

### Constants (always declare)

```wgsl
const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
```

### Core Chunk Library

Copy verbatim from `agents/WGSL_BUILTINS_GENERATIVE.md` — do not invent variants.

| Chunk | Source | Use in generative |
|-------|--------|-------------------|
| `hash21` / `hash12` | `gen_grid.wgsl` | Particles, seeds, jitter |
| `valueNoise` + `fbm` | WGSL_BUILTINS §4 | Terrain, clouds, organic flow |
| `domainWarp` | WGSL_BUILTINS §4 | Upgrade rigid patterns (grids, spirals) |
| `curlNoise` / `dwfbm3` | `gen-alpha-aurora.wgsl` | Aurora, smoke, flow fields |
| `acesToneMap` | Gold templates | **Required** on all upgraded shaders |
| `luma` | WGSL_BUILTINS §5 | Semantic alpha |
| `spectralColor` / `heatColor` | `gen-alpha-aurora.wgsl` | Scientific palettes |
| `bass_env` | `gen-alpha-aurora.wgsl` | Smooth audio → `extraBuffer[0]` |
| `rot2` | WGSL_BUILTINS §7 | Spirals, mandalas, epicycles |
| SDF primitives | WGSL_BUILTINS §6 | Raymarched generative |
| Temporal decay | WGSL_BUILTINS §9 | `mix(prev.rgb * decay, color, blend)` |
| `genChromaticShift` | WGSL_BUILTINS §8 | Generative chromatic (no readTexture) |

Attribute borrowed chunks:

```wgsl
// ═══ CHUNK: hash21 (from gen_grid.wgsl) ═══
```

### Output Contract (every shader)

```wgsl
textureStore(writeTexture, coord, vec4<f32>(color, alpha));       // semantic alpha
textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0,0,0)); // procedural depth
textureStore(dataTextureA, coord, vec4<f32>(...));               // temporal state
```

### Semantic Alpha Rules

Never `vec4<f32>(color, 1.0)` unless fully opaque by design.

| Alpha meaning | Example |
|---------------|---------|
| Intensity / density | `clamp(luma(color) * 1.5, 0.2, 0.95)` |
| Depth compositing | `presence * (0.7 + depth * 0.3)` |
| Simulation heat | `clamp(heat * 0.08, 0.0, 0.9)` |
| Particle count | `clamp(count * 0.1, 0.0, 1.0)` |

### Audio Reactivity

```wgsl
let bass   = plasmaBuffer[0].x;  // radius, pulse, rotation
let mids   = plasmaBuffer[0].y;  // color cycling, chromatic
let treble = plasmaBuffer[0].z;  // sparkle, jitter

// GOOD
let strength = baseStrength * (1.0 + bass * 0.5);

// BAD
let strength = bass * 100.0;
```

### Scientific Visual Upgrade Paths (Tier 1 micro)

From `shader_plans/generative_upgrades.md` — for shaders needing visual transformation, not just plumbing:

| Shader | Current | Upgrade concept |
|--------|---------|-----------------|
| `gen_grokcf_interference` | Wave interference | Modal synthesis / Chladni cymatics |
| `gen_julia_set` | Basic Julia | Newton fractal basins or Buddhabrot |
| `gen_psychedelic_spiral` | Spiral | Fourier epicycles / superformula |
| `gen_wave_equation` | Wave physics | Klein-Gordon solitons |
| `gen_reaction_diffusion` | Gray-Scott | Multi-species Turing |
| `gen_fluffy_raincloud` | Particle cloud | Curl noise + vorticity confinement |

---

## Agent Assignments

### Kimi Claw — Bulk creative upgrades

**Best for:** Swarm batches of 10–16 shaders, visual flourishes, new generative structure, compilation fixes.

**Today's assignment:** Batch 1 + Tier-1 micro visual upgrades.

#### Kimi Claw Prompt (Batch 1)

```
You are upgrading generative WGSL shaders for Pixelocity.
Read agents/CLOUD_UPGRADE.md and agents/WGSL_BUILTINS_GENERATIVE.md first.

Target batch: upgrade_batches/batch_1_generative.json

Shaders:
  gen-celestial-weave, gen-magnetic-kelp, gen-vortex-cathedral,
  gen-luminous-cauldron, gen-neon-snowfall, gen-bioreactor-bloom,
  gen-opal-circuit, holographic-crystal, spore-galaxy, acoustic-string-theory

Rules:
- DO NOT modify Renderer.ts, types.ts, or bindings
- Upgrade = visibly richer output, not just plumbing
- These shaders already have chromatic + temporal + audio
- ADD: acesToneMap before final write
- ADD: semantic alpha (replace hardcoded 1.0) — use intensity × depth or luma
- Copy acesToneMap verbatim from gen-conway-game-of-life.wgsl
- Keep existing visual algorithm intact unless broken
- Update JSON features only if WGSL matches (upgraded-rgba requires ACES)
- Run: naga public/shaders/SHADER_ID.wgsl

Deliver per shader:
  - public/shaders/SHADER_ID.wgsl
  - shader_definitions/generative/SHADER_ID.json (if features changed)
  - agents/swarm-outputs/kimi-notes/SHADER_ID.notes.kimi.md
```

#### Kimi Claw Prompt (Tier-1 micro visual upgrades)

```
You are doing VISUAL upgrades on micro generative shaders for Pixelocity.
Read shader_plans/generative_upgrades.md for scientific upgrade paths.

Priority targets:
  gen_grokcf_interference → Modal synthesis / Chladni cymatics
  gen_julia_set           → Newton fractal or Buddhabrot

Also apply full upgraded-rgba stack:
  acesToneMap, semantic alpha, bass/mids/treble, dataTextureA write,
  chromatic aberration, standard header

Rules:
- DO NOT modify Renderer.ts, types.ts, or bindings
- The output must look MEANINGFULLY different from before
- Copy hash21/fbm/aces chunks from agents/WGSL_BUILTINS_GENERATIVE.md
- Attribute chunks with // ═══ CHUNK: name (from shader.wgsl) ═══
- Run naga validation before finishing

Deliver: WGSL + JSON + kimi-notes
```

---

### Codex — Precision completion passes

**Best for:** Metadata drift fixes, alpha semantics, branchless refactors, naga errors, JSON ↔ WGSL sync.

**Today's assignment:** Metadata drift sweep + Batch 2 completion review.

#### Codex Prompt (Metadata drift)

```
Completion pass: reconcile upgraded-rgba metadata drift in generative shaders.

107 shaders have "upgraded-rgba" in JSON but no acesToneMap in WGSL.
Read agents/CLOUD_UPGRADE.md §2.

For each shader in the drift list:
  [ ] Add acesToneMap if shader is otherwise complete
  [ ] OR remove "upgraded-rgba" from JSON features if not ready
  [ ] Fix hardcoded alpha = 1.0 where present
  [ ] Ensure textureStore(dataTextureA, ...) exists
  [ ] Run: naga public/shaders/SHADER_ID.wgsl

Do NOT change core visual algorithms unless broken.
Prioritize Batch 1 shaders first (all 10 are drift cases).
```

#### Codex Prompt (Per-shader completion)

```
Completion pass for generative shader: SHADER_ID

Read:
  - public/shaders/SHADER_ID.wgsl
  - shader_definitions/generative/SHADER_ID.json
  - agents/CLOUD_UPGRADE.md §2

Checklist:
  [ ] acesToneMap applied before final write
  [ ] alpha is NOT hardcoded 1.0
  [ ] textureStore(dataTextureA, ...) present
  [ ] textureStore(writeDepthTexture, ...) present
  [ ] bass_env in extraBuffer[0] if audio-reactive
  [ ] JSON features match WGSL (upgraded-rgba only if ACES present)
  [ ] Standard 7-line header comment
  [ ] naga validates clean
  [ ] No if-chains in hot paths — use select/mix/step

Do NOT change the core visual algorithm unless it's broken.
```

---

### kimi-cli — Orchestration / audit / CI

**Best for:** Scripted batch dispatch, audit reports, PR assembly, validation runs.

**Today's assignment:** Run post-batch validation, regenerate batch files.

#### kimi-cli Prompt (Batch 2 generation — already run)

Batch 2 was generated 2026-06-06 → `upgrade_batches/batch_2_generative.json`

#### kimi-cli Prompt (Post-batch validation)

```
After generative shader batch completes, run full validation:

  node scripts/generate_shader_lists.js
  node scripts/check_duplicates.js
  npm test -- --watchAll=false
  npm run build

For each shader in the batch:
  naga public/shaders/SHADER_ID.wgsl

Produce summary:
  - pass/fail per shader
  - lines changed
  - features added
  - any metadata drift remaining

Write report to: agents/swarm-outputs/batch-N-validation.md
```

#### kimi-cli Prompt (Generate Batch 3)

```
Audit generative shaders and produce upgrade_batches/batch_3_generative.json.

Criteria:
  - category = generative
  - lines < 160
  - has plasmaBuffer + dataTextureC + writeDepthTexture
  - missing acesToneMap
  - exclude shaders already in batch_1 or batch_2
  - score: no dataA write (+10), no chromatic (+5), hardcoded alpha (+3), metadata drift (+2)
  - deprioritize @workgroup_size(8, 8, 1)

Output: JSON batch file (top 10) + markdown summary.
```

---

## Batch 1 — ACES Completion (Easiest)

**File:** `upgrade_batches/batch_1_generative.json`  
**Agent:** Kimi Claw  
**Est. time:** ~10 min/shader (~2 hours total)  
**Status:** Ready to execute

| ID | Lines | Missing | Notes |
|----|------:|---------|-------|
| `gen-celestial-weave` | 93 | ACES | Cosmic weave — semantic alpha: weave density × depth |
| `gen-magnetic-kelp` | 93 | ACES | Magnetic kelp strands — strand density × depth |
| `gen-vortex-cathedral` | 93 | ACES | Vortex cathedral — vortex intensity × depth |
| `gen-luminous-cauldron` | 94 | ACES | Luminous cauldron — bubble glow × depth |
| `gen-neon-snowfall` | 94 | ACES | Neon snowfall — snow density × depth |
| `gen-bioreactor-bloom` | 95 | ACES | Bioreactor growth — growth density × depth |
| `gen-opal-circuit` | 95 | ACES | Opal circuit — circuit activity × depth |
| `holographic-crystal` | 95 | ACES | Holographic crystal — refraction intensity × depth |
| `spore-galaxy` | 98 | ACES | Spore galaxy — spore density × depth |
| `acoustic-string-theory` | 100 | ACES | Acoustic strings — string amplitude × depth |

All already have: chromatic aberration, `dataTextureC` reads, `dataTextureA` writes, audio reactivity.

---

## Batch 2 — ACES + Full Plumbing

**File:** `upgrade_batches/batch_2_generative.json`  
**Agent:** Kimi Claw (upgrade) + Codex (review)  
**Est. time:** ~20 min/shader (~3 hours total)  
**Status:** Ready to execute

| ID | Lines | Score | Missing |
|----|------:|------:|---------|
| `gen-protocell-division` | 137 | 18 | dataA-write, chromatic, hard-alpha |
| `gen-erosion-strata` | 138 | 18 | dataA-write, chromatic, hard-alpha |
| `atmos_volumetric_fog` | 140 | 18 | dataA-write, chromatic, hard-alpha |
| `gen-murmuration-phantom` | 149 | 18 | dataA-write, chromatic, hard-alpha |
| `neural-mandala` | 112 | 10 | chromatic, hard-alpha, metadata-drift |
| `coral-growth` | 116 | 10 | chromatic, hard-alpha, metadata-drift |
| `mycelium-network` | 124 | 10 | chromatic, hard-alpha, metadata-drift |
| `gen-mandelbox-explorer` | 125 | 10 | chromatic, hard-alpha, metadata-drift |
| `gen-cyclic-automaton` | 127 | 10 | chromatic, hard-alpha, metadata-drift |
| `gen-apollonian-gasket` | 129 | 10 | chromatic, hard-alpha, metadata-drift |

### Batch 2 Full Prompt (copy-paste)

```
You are upgrading generative WGSL shaders for Pixelocity to the upgraded-rgba standard.
Read these files first:
  - agents/CLOUD_UPGRADE.md
  - agents/WGSL_BUILTINS_GENERATIVE.md
  - upgrade_batches/batch_2_generative.json

Target shaders (upgrade ALL 10):
  gen-protocell-division
  gen-erosion-strata
  atmos_volumetric_fog
  gen-murmuration-phantom
  neural-mandala
  coral-growth
  mycelium-network
  gen-mandelbox-explorer
  gen-cyclic-automaton
  gen-apollonian-gasket

IMMUTABLE RULES:
  - DO NOT modify Renderer.ts, types.ts, or bind groups
  - DO NOT add/remove/rename bindings
  - DO NOT extend the Uniforms struct
  - Use @workgroup_size(16, 16, 1) unless shader already uses a different size for shared memory
  - Upgrade = visibly richer output, not just plumbing

REQUIRED ADDITIONS (every shader):
  1. Standard 7-line header (see CLOUD_UPGRADE.md §2.5)
  2. acesToneMap — copy from gen-conway-game-of-life.wgsl
  3. Semantic alpha — replace vec4(..., 1.0) with meaningful alpha
  4. Chromatic aberration — genChromaticShift or per-channel UV offset, scaled by bass/depth
  5. Audio reactivity — bass/mids/treble from plasmaBuffer[0].xyz modulating key params
  6. Temporal feedback — read dataTextureC, blend, write dataTextureA
  7. Depth write — textureStore(writeDepthTexture, ...) with procedural depth
  8. Chunk attribution — // ═══ CHUNK: name (from shader.wgsl) ═══

COPY VERBATIM from agents/WGSL_BUILTINS_GENERATIVE.md:
  - hash21, valueNoise, fbm (as needed)
  - acesToneMap, luma, genChromaticShift
  - temporal decay pattern from §9

TEMPLATE STRUCTURE (follow gen-conway-game-of-life.wgsl):
  - Bounds guard at top of main()
  - Read bass/mids/treble, depth, prev from dataTextureC
  - Effect computation (preserve core algorithm, enhance visually)
  - Temporal blend: mix(prev.rgb * decay, color, blend + bass * 0.01)
  - Chromatic shift before tonemap
  - acesToneMap(color * exposure)
  - Semantic alpha
  - Write writeTexture, writeDepthTexture, dataTextureA

JSON UPDATE (shader_definitions/generative/SHADER_ID.json):
  - Add "upgraded-rgba" and "audio-reactive" to features array
  - Only add upgraded-rgba if acesToneMap is in WGSL

VALIDATION (required before marking done):
  naga public/shaders/SHADER_ID.wgsl
  node scripts/generate_shader_lists.js

DELIVERABLES per shader:
  - public/shaders/SHADER_ID.wgsl
  - shader_definitions/generative/SHADER_ID.json (if features changed)
  - agents/swarm-outputs/kimi-notes/SHADER_ID.notes.kimi.md
    (changes made, wow factor, risks for polish)

ACCEPTANCE: Shader must look meaningfully richer than before.
A shader that compiles but renders the same picture is NOT upgraded.
```

---

## Today's Schedule

| Time | Task | Agent | Output |
|------|------|-------|--------|
| AM | Ship Batch 1 (10 shaders) | Kimi Claw | 10 WGSL + notes |
| AM (parallel) | Metadata drift fix (107 shaders) | Codex | JSON ↔ WGSL sync |
| Midday | Post-batch validation | kimi-cli | `batch-1-validation.md` |
| PM | Execute Batch 2 (10 shaders) | Kimi Claw + Codex review | 10 WGSL + notes |
| PM | Open GitHub issues | Human / kimi-cli | Epic + 6 child issues |
| EOD | Generate Batch 3 candidates | kimi-cli | `batch_3_generative.json` |

---

## GitHub Issues

Create as **epic + child issues**, not 273 individual issues.  
Labels: `shader-upgrade`, `generative`, `batch-N`  
Milestone: `Generative Upgrade Sprint — June 2026`

---

### Issue #0 — EPIC

**Title:** `[EPIC] Generative shader upgrade sprint — June 2026`

**Body:**

```markdown
## Overview

Upgrade generative WGSL shaders to the `upgraded-rgba` standard defined in `agents/CLOUD_UPGRADE.md`.

**Category:** generative (317 shaders)
**Current ACES coverage:** 44/317 (14%)
**Metadata drift:** 107 shaders tagged upgraded-rgba without ACES in WGSL

## Plan

See `composer.md` for full sprint plan, agent prompts, and batch definitions.

## Child Issues

- [ ] #1 Batch 1: ACES completion (10 shaders)
- [ ] #2 Metadata drift: false upgraded-rgba tags (107 shaders)
- [ ] #3 Batch 2: ACES + full plumbing (10 shaders)
- [ ] #4 Semantic alpha sweep — generative
- [ ] #5 dataTextureA write completion (128 shaders)
- [ ] #6 Tier-1 micro shader visual upgrades

## Acceptance Criteria (epic-level)

- [ ] Batch 1 and Batch 2 merged and validated
- [ ] Metadata drift reduced to 0
- [ ] `node scripts/generate_shader_lists.js` passes
- [ ] `npm test` passes
- [ ] `npm run build` passes

## References

- `composer.md`
- `agents/CLOUD_UPGRADE.md`
- `agents/WGSL_BUILTINS_GENERATIVE.md`
- `upgrade_batches/batch_1_generative.json`
- `upgrade_batches/batch_2_generative.json`
```

**Labels:** `epic`, `shader-upgrade`, `generative`

---

### Issue #1 — Batch 1

**Title:** `Batch 1: ACES completion for 10 generative shaders`

**Body:**

```markdown
## Summary

Complete ACES tone mapping + semantic alpha for 10 generative shaders that already have chromatic aberration, temporal feedback, and audio reactivity.

**Agent:** Kimi Claw
**Est. effort:** ~2 hours
**Batch file:** `upgrade_batches/batch_1_generative.json`

## Shaders

- [ ] `gen-celestial-weave` — weave density × depth alpha
- [ ] `gen-magnetic-kelp` — strand density × depth alpha
- [ ] `gen-vortex-cathedral` — vortex intensity × depth alpha
- [ ] `gen-luminous-cauldron` — bubble glow × depth alpha
- [ ] `gen-neon-snowfall` — snow density × depth alpha
- [ ] `gen-bioreactor-bloom` — growth density × depth alpha
- [ ] `gen-opal-circuit` — circuit activity × depth alpha
- [ ] `holographic-crystal` — refraction intensity × depth alpha
- [ ] `spore-galaxy` — spore density × depth alpha
- [ ] `acoustic-string-theory` — string amplitude × depth alpha

## Work Required

1. Add `acesToneMap` (copy from `gen-conway-game-of-life.wgsl`)
2. Replace hardcoded `vec4(..., 1.0)` with semantic alpha
3. Ensure JSON `upgraded-rgba` tag matches WGSL
4. Run `naga` validation per shader

## Prompt

See `composer.md` → "Kimi Claw Prompt (Batch 1)"

## Acceptance Criteria

- [ ] All 10 shaders have `acesToneMap` in WGSL
- [ ] No hardcoded alpha = 1.0
- [ ] `naga` passes for all 10
- [ ] `generate_shader_lists.js` passes
- [ ] kimi-notes written for each shader
```

**Labels:** `shader-upgrade`, `generative`, `batch-1`

---

### Issue #2 — Metadata Drift

**Title:** `Fix metadata drift: 107 generative shaders with false upgraded-rgba tags`

**Body:**

```markdown
## Summary

107 generative shaders have `"upgraded-rgba"` in their JSON features array but no `acesToneMap` / `toneMapACES` in the WGSL source. This causes incorrect UI tagging and AI VJ matching.

**Agent:** Codex
**Est. effort:** ~4 hours (can run parallel with Batch 1)

## Approach

For each drift shader, choose ONE:
1. **Add ACES** — if shader is otherwise complete (chromatic, dataA, semantic alpha)
2. **Remove tag** — if shader is not ready for upgraded-rgba

**Never** leave `upgraded-rgba` in JSON without ACES in WGSL.

## Priority Order

1. Batch 1 shaders (all 10 are drift cases)
2. Batch 2 shaders with metadata-drift flag (6 of 10)
3. Remaining ~91 shaders

## Sample Drift Shaders

- `gen-stardust-nebula`
- `gen-plasma-mandala`
- `gen-chromatic-singularity-loom`
- `gen-symbiotic-chrono-mycelium-engine`
- `multi-scale-evolutionary-cellular-gardens`

## Prompt

See `composer.md` → "Codex Prompt (Metadata drift)"

## Acceptance Criteria

- [ ] 0 shaders with upgraded-rgba in JSON but no ACES in WGSL
- [ ] `generate_shader_lists.js` passes
- [ ] No visual regressions (ACES addition only, no algorithm changes unless broken)
```

**Labels:** `shader-upgrade`, `generative`, `metadata`, `batch-1`

---

### Issue #3 — Batch 2

**Title:** `Batch 2: ACES + full plumbing for 10 generative shaders`

**Body:**

```markdown
## Summary

Full upgraded-rgba pass for 10 generative shaders missing ACES, chromatic aberration, semantic alpha, and/or dataTextureA writes.

**Agent:** Kimi Claw (upgrade) + Codex (review)
**Est. effort:** ~3 hours
**Batch file:** `upgrade_batches/batch_2_generative.json`

## Shaders

- [ ] `gen-protocell-division` (137L) — dataA + chromatic + alpha + ACES
- [ ] `gen-erosion-strata` (138L) — dataA + chromatic + alpha + ACES
- [ ] `atmos_volumetric_fog` (140L) — dataA + chromatic + alpha + ACES
- [ ] `gen-murmuration-phantom` (149L) — dataA + chromatic + alpha + ACES
- [ ] `neural-mandala` (112L) — chromatic + alpha + ACES + fix drift tag
- [ ] `coral-growth` (116L) — chromatic + alpha + ACES + fix drift tag
- [ ] `mycelium-network` (124L) — chromatic + alpha + ACES + fix drift tag
- [ ] `gen-mandelbox-explorer` (125L) — chromatic + alpha + ACES + fix drift tag
- [ ] `gen-cyclic-automaton` (127L) — chromatic + alpha + ACES + fix drift tag
- [ ] `gen-apollonian-gasket` (129L) — chromatic + alpha + ACES + fix drift tag

## Prompt

See `composer.md` → "Batch 2 Full Prompt"

## Acceptance Criteria

- [ ] All 10 have acesToneMap, chromatic, semantic alpha, dataTextureA write
- [ ] Output looks meaningfully richer than before
- [ ] `naga` passes for all 10
- [ ] JSON features include `upgraded-rgba` and `audio-reactive`
- [ ] kimi-notes written for each shader
```

**Labels:** `shader-upgrade`, `generative`, `batch-2`

---

### Issue #4 — Semantic Alpha Sweep

**Title:** `Semantic alpha sweep: generative shaders with hardcoded alpha = 1.0`

**Body:**

```markdown
## Summary

307 of 317 generative shaders hardcode `vec4<f32>(color, 1.0)`. This prevents proper alpha blending in multi-slot chains.

**Agent:** Codex
**Est. effort:** Ongoing (batch in groups of 20–30)

## Alpha Formulas (pick per shader semantics)

| Type | Formula |
|------|---------|
| Glow / particles | `clamp(luma(color) * 1.5, 0.2, 0.95)` |
| Density field | `clamp(intensity * 0.9, 0.1, 1.0)` |
| Depth compositing | `presence * (0.7 + depth * 0.3)` |
| Simulation | `clamp(heat * 0.08, 0.0, 0.9)` |

## Scope

Start with shaders already being upgraded in Batches 1–2, then expand to remaining generative shaders in line-count order (< 160 lines first).

## References

- `agents/WGSL_BUILTINS_GENERATIVE.md` §10
- `agents/CLOUD_UPGRADE.md` §2.1

## Acceptance Criteria

- [ ] No `vec4<f32>(..., 1.0)` in upgraded shaders unless fully opaque by design
- [ ] Alpha varies across the image (not static 0.5 or 1.0)
```

**Labels:** `shader-upgrade`, `generative`, `alpha`

---

### Issue #5 — dataTextureA Write Completion

**Title:** `Add dataTextureA writes to 128 generative shaders`

**Body:**

```markdown
## Summary

128 generative shaders read from `dataTextureC` but do not write to `dataTextureA`. Without the writeback, temporal feedback chains break in multi-slot mode.

**Agent:** Codex
**Est. effort:** Ongoing (batch in groups of 20–30)

## Required Pattern

```wgsl
let prev = textureLoad(dataTextureC, pixel, 0);
// ... effect computation ...
let decay = 0.97 - p4 * 0.02;
let trail = mix(prev.rgb * decay, color, 0.2 + bass * 0.1);
textureStore(dataTextureA, pixel, vec4<f32>(trail, alpha));
```

## Priority

1. Batch 2 shaders (4 missing dataA write)
2. Shaders < 160 lines with existing chromatic/audio
3. Longer shaders last

## References

- `agents/WGSL_BUILTINS_GENERATIVE.md` §9
- `gen-conway-game-of-life.wgsl` (gold template)

## Acceptance Criteria

- [ ] Every generative shader that reads dataTextureC also writes dataTextureA
- [ ] `naga` passes
```

**Labels:** `shader-upgrade`, `generative`, `temporal`

---

### Issue #6 — Tier-1 Micro Visual Upgrades

**Title:** `Tier-1 micro generative shaders: scientific visual upgrades`

**Body:**

```markdown
## Summary

Upgrade the smallest legacy generative shaders with new visual algorithms, not just plumbing. These shaders are simple enough for fast iteration but currently produce basic output.

**Agent:** Kimi Claw
**Est. effort:** ~1 day
**Plan:** `shader_plans/generative_upgrades.md` Tier 1

## Priority Targets

| Shader | Size | Upgrade Path |
|--------|------|--------------|
| `gen_grokcf_interference` | ~188L | Modal synthesis / Chladni cymatics |
| `gen_julia_set` | ~170L | Newton fractal or Buddhabrot |
| `gen_psychedelic_spiral` | ~142L | Fourier epicycles / superformula |

## Also apply full upgraded-rgba stack

ACES, semantic alpha, audio, chromatic, dataTextureA, standard header.

## Prompt

See `composer.md` → "Kimi Claw Prompt (Tier-1 micro visual upgrades)"

## Acceptance Criteria

- [ ] Output looks meaningfully different (not just tonemapped version of same pattern)
- [ ] Full upgraded-rgba compliance
- [ ] `naga` passes
- [ ] kimi-notes with before/after description
```

**Labels:** `shader-upgrade`, `generative`, `visual-upgrade`, `tier-1`

---

## Validation Checklist (Every Batch)

```bash
# Per shader
naga public/shaders/SHADER_ID.wgsl

# Repo-wide
node scripts/generate_shader_lists.js
node scripts/check_duplicates.js
npm test -- --watchAll=false
npm run build
```

## Success Metrics

| Metric | Current | Target (sprint end) |
|--------|--------:|--------------------:|
| ACES in WGSL | 44 | 64+ (Batches 1+2) |
| Metadata drift | 107 | 0 |
| Hardcoded alpha | 307 | < 280 |
| dataTextureA writes | 189 | 203+ |

---

*Plan version: 1.0 — 2026-06-06*