# gen-liquid-crystal-hive-mind — Codex F1 Reference Upgrade

Date: 2026-06-07

## Scope

- WGSL: `public/shaders/gen-liquid-crystal-hive-mind.wgsl`
- JSON: `shader_definitions/generative/gen-liquid-crystal-hive-mind.json`
- Before: 326 WGSL lines
- After: 371 WGSL lines
- Delta: +45 lines

## What Changed

- Replaced the placeholder header with a synchronized F1 feature header.
- Added canonical `acesToneMap`, `huePreserveClamp`, and `bass_env` helpers.
- Moved audio control from raw `u.config.y` to smoothed `plasmaBuffer[0]` bass, mids, and treble.
- Routed smoothed audio into cell density, liquid turbulence, pulse timing, brightness, and chromatic shimmer.
- Added mouse field steering: cursor position offsets the camera and rotates/disrupts nearby hive cells.
- Added temporal state: `dataTextureC` reads previous smoothed audio and hive pulse; `dataTextureA` writes the next state.
- Added semantic alpha from membrane/glow presence and bass energy.
- Added depth output from ray hit distance, source depth, and membrane density.
- Added chromatic aberration before ACES and final alpha-aware compositing with the input texture.

## Acceptance Check

| Criterion | Status | Notes |
|-----------|:------:|-------|
| ACES | Pass | Single canonical `acesToneMap` on final color path |
| Chromatic | Pass | `chroma` offsets RGB before ACES |
| Temporal/dataA | Pass | Reads `dataTextureC`, writes `dataTextureA` |
| Semantic alpha | Pass | Alpha derives from membrane presence and bass |
| Audio via bass_env | Pass | Bass, mids, treble are smoothed before use |
| Mouse | Pass | Cursor drives camera offset and local B-field rotation/disruption |
| Depth | Pass | Writes ray/depth-aware `depthSignal` |
| Header/JSON sync | Pass | Feature lists synchronized |
| Naga | Pass | `naga public/shaders/gen-liquid-crystal-hive-mind.wgsl` |

## Validation

```bash
naga public/shaders/gen-liquid-crystal-hive-mind.wgsl
node scripts/generate_shader_lists.js
node scripts/check_duplicates.js
```

All three commands passed.
