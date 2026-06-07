# Batch 3 Generative Shader Upgrade — 2026-06-06

## Shaders Upgraded (7/7)

| Shader | ACES | Chromatic | Temporal | Semantic Alpha | Branchless | Notes |
|--------|------|-----------|----------|----------------|------------|-------|
| gen-verlet-cloth-wind | ✅ | ✅ | — | — | — | Inline ACES → canonical `acesToneMap` |
| gen-percolation-threshold | ✅ | ✅ | — | — | — | Inline ACES → canonical `acesToneMap` |
| gen-feedback-echo-chamber | ✅ | ✅ | — | — | — | Inline ACES → canonical; chromatic uses `audioOverall` |
| gen-topological-acoustic-knots | ✅ | ✅ | ✅ | ✅ | — | Full stack: hardcoded `alpha=1.0` fixed, `dataTextureA` write added, temporal feedback via `dataTextureC` read + decay blend |
| gen_kimi_nebula | ✅ | ✅ | — | — | — | Added `acesToneMap` + chromatic inside `applyGenerativePrimaryControls` wrapper; fixed `dataTextureA` to store final RGBA |
| gen_hyper_warp | ✅ | ✅ | — | — | — | Same pattern as nebula: ACES + chromatic via wrapper |
| gen-temporal-motion-smear | ✅ | ✅ | — | — | ✅ | Converted `if (trailAge > 0.1)` and `if (motionStrength < 0.001)` to branchless `select`/`mix`; moved depth read before chromatic block |

## Validation Results

- **naga 29.0.3**: All 7 shaders pass ✅
- **generate_shader_lists.js**: Pass ✅
- **check_duplicates.js**: Pass ✅ (1123 unique IDs, 0 duplicates)

## Metadata Updates

All 7 JSON definitions updated with feature flags:
- `upgraded-rgba`
- `aces-tone-map`
- `chromatic-aberration`
- `depth-aware` (where depth is now read)
- `temporal-feedback` (gen-topological-acoustic-knots)
- `audio-reactive` added to gen_kimi_nebula, gen_hyper_warp (now read `plasmaBuffer[0].x`)

## Sprint Total

**124 shaders upgraded** (117 previous + 7 Batch 3)
