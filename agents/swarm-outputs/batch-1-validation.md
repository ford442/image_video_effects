# Batch 1 Validation Report — 2026-06-06

## Scope
10 generative shaders upgraded with ACES tone mapping + header standardization.

## Shaders Processed

| # | Shader | Lines Before | Lines After | Changes |
|---|--------|-------------:|------------:|---------|
| 1 | gen-celestial-weave | 93 | 103 | +acesToneMap, +ACES apply, header update |
| 2 | gen-magnetic-kelp | 93 | 103 | +acesToneMap, +ACES apply, header update |
| 3 | gen-vortex-cathedral | 93 | 103 | +acesToneMap, +ACES apply, header update |
| 4 | gen-luminous-cauldron | 94 | 104 | +acesToneMap, +ACES apply, header update |
| 5 | gen-neon-snowfall | 94 | 104 | +acesToneMap, +ACES apply, header update |
| 6 | gen-bioreactor-bloom | 95 | 105 | +acesToneMap, +ACES apply, header update |
| 7 | gen-opal-circuit | 95 | 105 | +acesToneMap, +ACES apply, header update |
| 8 | holographic-crystal | 95 | 105 | +acesToneMap, +ACES apply, +Upgraded date |
| 9 | spore-galaxy | 98 | 108 | +acesToneMap, +ACES apply, +Upgraded date |
| 10 | acoustic-string-theory | 100 | 110 | +acesToneMap, +ACES apply, +Upgraded date |

## Per-Shader Validation

| Shader | naga | hardAlpha | dataA | depth | audio | header |
|--------|:----:|:---------:|:-----:|:-----:|:-----:|:------:|
| gen-celestial-weave | ✅ | ❌ (semantic) | ✅ | ✅ | ✅ | ✅ |
| gen-magnetic-kelp | ✅ | ❌ (semantic) | ✅ | ✅ | ✅ | ✅ |
| gen-vortex-cathedral | ✅ | ❌ (semantic) | ✅ | ✅ | ✅ | ✅ |
| gen-luminous-cauldron | ✅ | ❌ (semantic) | ✅ | ✅ | ✅ | ✅ |
| gen-neon-snowfall | ✅ | ❌ (semantic) | ✅ | ✅ | ✅ | ✅ |
| gen-bioreactor-bloom | ✅ | ❌ (semantic) | ✅ | ✅ | ✅ | ✅ |
| gen-opal-circuit | ✅ | ❌ (semantic) | ✅ | ✅ | ✅ | ✅ |
| holographic-crystal | ✅ | ❌ (semantic) | ✅ | ✅ | ✅ | ✅ |
| spore-galaxy | ✅ | ❌ (semantic) | ✅ | ✅ | ✅ | ✅ |
| acoustic-string-theory | ✅ | ❌ (semantic) | ✅ | ✅ | ✅ | ✅ |

## Project-Level Validation

| Check | Status |
|-------|:------:|
| `node scripts/generate_shader_lists.js` | ✅ pass |
| `node scripts/check_duplicates.js` | ✅ pass (1123 unique, 0 duplicates) |

## Metadata Drift Impact

All 10 Batch 1 shaders were previously flagged as metadata drift (JSON had `upgraded-rgba` but WGSL lacked ACES). **This drift is now resolved** for these 10 shaders.

Remaining metadata drift: ~97 shaders (107 original - 10 fixed).

## Notes Written

All 10 shaders have corresponding notes in `agents/swarm-outputs/kimi-notes/`.

## Acceptance Criteria

- [x] All 10 shaders have `acesToneMap` in WGSL
- [x] No hardcoded alpha = 1.0 (all use semantic alpha)
- [x] `naga` passes for all 10
- [x] `generate_shader_lists.js` passes
- [x] `check_duplicates.js` passes
- [x] kimi-notes written for each shader

## Next Steps

1. **Metadata drift sweep** (Codex) — fix remaining ~97 shaders
2. **Batch 2** (Kimi Claw + Codex review) — 10 shaders needing full plumbing
