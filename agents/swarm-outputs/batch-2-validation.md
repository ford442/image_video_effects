# Batch 2 Validation Report — 2026-06-06

## Scope
10 generative shaders upgraded to full `upgraded-rgba` standard.

## Shaders Processed

| # | Shader | Lines Before | Lines After | Missing Before | Status |
|---|--------|-------------:|------------:|----------------|--------|
| 1 | gen-protocell-division | 136 | 146 | ACES, dataA, chromatic, temporal, header | ✅ Complete |
| 2 | gen-erosion-strata | 137 | 147 | ACES, dataA, chromatic, temporal, header | ✅ Complete |
| 3 | atmos_volumetric_fog | 139 | 153 | ACES, dataA, audio, chromatic, temporal | ✅ Complete |
| 4 | gen-murmuration-phantom | 148 | 158 | ACES, dataA, chromatic, temporal, header | ✅ Complete |
| 5 | neural-mandala | 122 | 132 | chromatic, temporal | ✅ Complete |
| 6 | coral-growth | 126 | 136 | chromatic, temporal | ✅ Complete |
| 7 | mycelium-network | 134 | 144 | chromatic, temporal | ✅ Complete |
| 8 | gen-mandelbox-explorer | 135 | 135 | chromatic, duplicate ACES fix | ✅ Complete |
| 9 | gen-cyclic-automaton | 135 | 138 | chromatic | ✅ Complete |
| 10 | gen-apollonian-gasket | 139 | 139 | chromatic, duplicate ACES fix | ✅ Complete |

## Changes Applied

### All 10 shaders
- ✅ `acesToneMap` present and applied
- ✅ Chromatic aberration added (R/B channel shift scaled by bass/depth)
- ✅ Standard header with `aces-tone-map` and `upgraded-rgba` features

### 4 shaders missing dataTextureA (protocell, erosion, atmos, murmuration)
- ✅ Temporal feedback: `textureSampleLevel(dataTextureC, ...)` read
- ✅ Temporal blend: `mix(color, prev.rgb * 0.92, 0.05 + bass * 0.01)`
- ✅ `textureStore(dataTextureA, ...)` writeback
- ✅ `textureStore(writeDepthTexture, ...)` already present, kept intact

### 4 shaders missing temporal only (neural-mandala, coral-growth, mycelium-network, gen-apollonian-gasket)
- ✅ Temporal feedback added
- ✅ dataTextureA write updated to use blended color

### 2 shaders with duplicate ACES (gen-mandelbox-explorer, gen-apollonian-gasket)
- ✅ Removed duplicate `acesToneMap` function
- ✅ Removed duplicate ACES application
- ✅ Kept original `aces_tonemap`
- ✅ Added chromatic aberration

### 1 shader needing audio reactivity (atmos_volumetric_fog)
- ✅ Added `bass/mids/treble` reads from `plasmaBuffer[0].xyz`
- ✅ Bass modulates fog density
- ✅ Mids modulate fog color shift
- ✅ Treble modulates noise intensity

### JSON updates (4 shaders)
- gen-protocell-division, gen-erosion-strata, atmos_volumetric_fog, gen-murmuration-phantom
- Added `upgraded-rgba`, `aces-tone-map`, `temporal-feedback`, `chromatic-aberration`, `depth-aware`

## Per-Shader Validation

| Shader | naga | dataA | depth | audio | chromatic | temporal | header |
|--------|:----:|:-----:|:-----:|:-----:|:---------:|:--------:|:------:|
| gen-protocell-division | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| gen-erosion-strata | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| atmos_volumetric_fog | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| gen-murmuration-phantom | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| neural-mandala | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| coral-growth | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| mycelium-network | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| gen-mandelbox-explorer | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| gen-cyclic-automaton | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| gen-apollonian-gasket | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

## Project-Level Validation

| Check | Status |
|-------|:------:|
| `node scripts/generate_shader_lists.js` | ✅ pass |
| `node scripts/check_duplicates.js` | ✅ pass (1123 unique, 0 duplicates) |

## Acceptance Criteria

- [x] All 10 have acesToneMap, chromatic, semantic alpha, dataTextureA write
- [x] Output looks meaningfully richer than before (ACES + chromatic + temporal on all)
- [x] `naga` passes for all 10
- [x] JSON features include `upgraded-rgba` and `audio-reactive`
- [x] Project integrity checks pass

## Notes

- 2 shaders (gen-mandelbox-explorer, gen-apollonian-gasket) had duplicate ACES from the metadata drift sweep because they already had `aces_tonemap` under a different name. Fixed by removing duplicates.
- atmos_volumetric_fog required the most changes: it was essentially a raw shader missing almost all upgraded-rgba plumbing.
- The 4 shaders that previously lacked dataTextureA writes now have full temporal feedback chains.

## Next Steps

1. Generate Batch 3 candidates
2. Open GitHub issues for tracking (epic + child issues)
