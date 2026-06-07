# Metadata Drift Sweep Validation Report — 2026-06-06

## Scope
Reconciled 97 generative shaders that had `upgraded-rgba` in JSON but no ACES in WGSL.

## Approach
Automated sweep with targeted manual fallback for edge cases:
1. **Primary script**: Pattern-matched each shader's final `textureStore(writeTexture, ...)` pattern and applied ACES at the correct insertion point.
2. **Edge-case fix script**: Handled 10 shaders that failed the primary script due to complex expressions inside `vec4<f32>()` constructors or `let`-immutable variable reassignment attempts.

## Shaders Processed

All 97 drift shaders were successfully upgraded. Key patterns handled:

| Pattern | Count | Strategy |
|---------|------:|----------|
| Inline `vec4<f32>(color, alpha)` in `textureStore` | ~40 | Wrap color with `acesToneMap((color) * 1.1)` inside vec4 |
| Preconstructed `let finalColor = vec4<f32>(expr, alpha)` | ~30 | Wrap expr with `acesToneMap((expr) * 1.1)` inside vec4 |
| `applyGenerativePrimaryControls(out)` | ~19 | Modify helper return: `return vec4<f32>(acesToneMap(controlled * 1.1), color.a)` |
| Complex expressions (e.g., `mixed_color.rgb`, `gamma * alpha`) | ~8 | Wrap first vec4 argument with `acesToneMap((expr) * 1.1)` |

## Per-Shader Validation

| Metric | Count |
|--------|------:|
| Total drift shaders | 97 |
| Successfully upgraded | 97 |
| Naga failures | 0 |
| Drift remaining | 0 |

## Project-Level Validation

| Check | Status |
|-------|:------:|
| `node scripts/generate_shader_lists.js` | ✅ pass |
| `node scripts/check_duplicates.js` | ✅ pass (1123 unique, 0 duplicates) |

## Header & Date Updates

All 97 shaders received:
- `aces-tone-map` added to WGSL header features list
- `Upgraded:` date set to `2026-06-06` (added if missing, updated if present)
- `acesToneMap` function inserted before `@compute @workgroup_size(16, 16, 1)`

## Impact on Metadata Drift

**Before sweep:** 107 shaders with `upgraded-rgba` in JSON but no ACES in WGSL  
**After Batch 1:** 97 remaining  
**After metadata drift sweep:** 0 remaining

All generative shaders tagged `upgraded-rgba` in JSON now have ACES in WGSL.

## Next Steps

1. **Batch 2** (10 shaders) — full plumbing fixes for 4 shaders missing `dataTextureA` writes
2. **Batch 3 generation** — identify next set of generative upgrade targets
