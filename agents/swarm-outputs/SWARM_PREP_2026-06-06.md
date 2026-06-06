# Swarm Preparation Report — 2026-06-06

## Environment Readiness

| Tool | Status | Version / Path |
|------|--------|---------------|
| `naga` | ✅ Ready | 29.0.3 at `/root/.cargo/bin/naga` |
| `node` | ✅ Ready | `v20.19.0` |
| `npm` | ✅ Ready | `10.8.2` |
| `generate_shader_lists.js` | ✅ Ready | `/root/image_video_effects/scripts/generate_shader_lists.js` |
| `check_duplicates.js` | ✅ Ready | `/root/image_video_effects/scripts/check_duplicates.js` |

## Reference Files Verified

| File | Status | Notes |
|------|--------|-------|
| `agents/CLOUD_UPGRADE.md` | ✅ Read | 448 lines — upgrade standard, scoring, workflow |
| `agents/WGSL_BUILTINS_GENERATIVE.md` | ✅ Read | 633 lines — canonical chunks, template, anti-patterns |
| `composer.md` | ✅ Read | 815 lines — full sprint plan with agent assignments |
| `public/shaders/gen-conway-game-of-life.wgsl` | ✅ Gold template | 136 lines, full upgraded-rgba stack |

## Batch 1 — ACES Completion (10 shaders)

**Status:** Ready to execute

| ID | Lines | ACES | dataA | depth | audio | hardAlpha | naga |
|----|------:|:----:|:-----:|:-----:|:-----:|:---------:|:----:|
| gen-celestial-weave | 93 | ❌ | ✅ | ✅ | ✅ | ❌ (uses `alpha` var) | ✅ |
| gen-magnetic-kelp | 93 | ❌ | ✅ | ✅ | ✅ | ❌ (uses `alpha` var) | ✅ |
| gen-vortex-cathedral | 93 | ❌ | ✅ | ✅ | ✅ | ❌ (uses `alpha` var) | ✅ |
| gen-luminous-cauldron | 94 | ❌ | ✅ | ✅ | ✅ | ❌ (uses `alpha` var) | ✅ |
| gen-neon-snowfall | 94 | ❌ | ✅ | ✅ | ✅ | ❌ (uses `alpha` var) | ✅ |
| gen-bioreactor-bloom | 95 | ❌ | ✅ | ✅ | ✅ | ❌ (uses `alpha` var) | ✅ |
| gen-opal-circuit | 95 | ❌ | ✅ | ✅ | ✅ | ❌ (uses `alpha` var) | ✅ |
| holographic-crystal | 95 | ❌ | ✅ | ✅ | ✅ | ❌ (uses `alpha` var) | ✅ |
| spore-galaxy | 98 | ❌ | ✅ | ✅ | ✅ | ❌ (uses `alpha` var) | ✅ |
| acoustic-string-theory | 100 | ❌ | ✅ | ✅ | ✅ | ❌ (uses `alpha` var) | ✅ |

**Key finding:** Batch 1 shaders already compute a meaningful `alpha` variable (not hardcoded 1.0). The upgrade task is **simpler than expected**: add `acesToneMap` + ensure alpha logic is preserved.

**Agent assignment:** Kimi Claw — bulk creative upgrades

## Batch 2 — ACES + Full Plumbing (10 shaders)

**Status:** Ready with one naming discrepancy

| ID | Lines | ACES | dataA | depth | audio | hardAlpha | naga |
|----|------:|:----:|:-----:|:-----:|:-----:|:---------:|:----:|
| gen-protocell-division | 136 | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ |
| gen-erosion-strata | 137 | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ |
| atmos_volumetric_fog | 139 | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ |
| gen-murmuration-phantom | 148 | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ |
| neural-mandala | 111 | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ |
| coral-growth | 115 | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ |
| mycelium-network | 123 | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ |
| gen-mandelbox-explorer | 124 | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ |
| gen_cyclic_automaton | 127 | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ |
| gen-apollonian-gasket | 128 | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ |

**⚠️ Naming discrepancy:** `gen-cyclic-automaton` in batch JSON is actually `gen_cyclic_automaton.wgsl` (underscores) on disk. Swarm agents must use the underscore filename.

**Key finding:** 4 shaders (`gen-protocell-division`, `gen-erosion-strata`, `atmos_volumetric_fog`, `gen-murmuration-phantom`) are missing `dataTextureA` writes. These need temporal feedback plumbing.

**Agent assignment:** Kimi Claw (upgrade) + Codex (review)

## Metadata Drift Sweep

**Current state:** 107 shaders tagged `upgraded-rgba` in JSON but lacking ACES in WGSL.

Batch 1 shaders are NOT currently tagged `upgraded-rgba` (confirmed via spot check of JSON files).

**Agent assignment:** Codex — precision completion passes

## Deliverables Structure

Per-shader output goes to:
- `public/shaders/SHADER_ID.wgsl` — upgraded WGSL
- `shader_definitions/generative/SHADER_ID.json` — updated features (if changed)
- `agents/swarm-outputs/kimi-notes/SHADER_ID.notes.kimi.md` — change notes

## Validation Pipeline (per batch)

```bash
# Per shader
naga public/shaders/SHADER_ID.wgsl

# Repo-wide after batch
node scripts/generate_shader_lists.js
node scripts/check_duplicates.js
npm test -- --watchAll=false
npm run build
```

## Ready to Launch

1. **Batch 1** can start immediately — all files exist, naga passes, plumbing is complete. Only ACES + header updates needed.
2. **Batch 2** can start immediately — same, plus note the underscore naming on `gen_cyclic_automaton`.
3. **Metadata drift** can run in parallel with Batch 1.
