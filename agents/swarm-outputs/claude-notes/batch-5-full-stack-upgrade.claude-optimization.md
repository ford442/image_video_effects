# Batch 5 — Full-Stack Upgrade (Claude) (2026-06-07)

## Selection
Self-selected via `CLOUD_UPGRADE.md §5.1` discovery script: scanned `public/shaders/gen-*.wgsl`
≤200 lines, scored by missing `dataTextureA`/`audio`/`depth`/`upgraded-rgba`, filtered to
`score ≥ 12` with an existing JSON definition, sorted smallest-first, and cross-checked
against [[project_linear_active]] (no overlap with the Linear-claimed list).

12 shaders selected:
1. `gen-fractal-bioluminescence-spore-network` (170L, score 15)
2. `gen-kryonic-quantum-aether-fractal-core` (179L, score 15)
3. `gen-eldritch-quantum-fractal-eye` (187L, score 15)
4. `gen-hyper-dimensional-tesseract-labyrinth` (198L, score 15)
5. `gen-holographic-plasma-geode` (198L, score 15)
6. `gen-quasicrystal` (162L, score 12)
7. `gen-string-theory` (173L, score 12)
8. `gen-nebular-chrono-astrolabe` (167L, score 12)
9. `gen-graviton-plasma-lotus` (170L, score 12)
10. `gen-quantum-aether-origami` (172L, score 12)
11. `gen-voronoi-crystal` (173L, score 12)
12. `gen-xeno-botanical-synth-flora` (174L, score 12)

## Two Cohorts, Two Upgrade Depths

### Cohort A — full stack from scratch (5 shaders, score 15)
`gen-fractal-bioluminescence-spore-network`, `gen-kryonic-quantum-aether-fractal-core`,
`gen-eldritch-quantum-fractal-eye`, `gen-hyper-dimensional-tesseract-labyrinth`,
`gen-holographic-plasma-geode` — all were missing `writeDepthTexture`, `dataTextureA`,
real `plasmaBuffer` audio reactivity (used legacy `u.config.y` as a raw "audio" proxy
instead — an explicit CLOUD_UPGRADE.md anti-pattern), and had hardcoded `vec4(col, 1.0)`
alpha. For each:
- Replaced `let audio = u.config.y;` with `plasmaBuffer[0].xyz` → `bass`/`mids`/`treble`
  reads, and routed `treble` into a secondary visual accent (sclera sparkle, edge tint,
  hue nudge — kept each addition small/controlled per the anti-pattern table)
- Replaced hardcoded alpha with a luma + glow-derived `semantic_alpha` formula
- Added `let outDepth = clamp(t / <maxT>, 0.0, 1.0)` from the raymarch hit distance and
  wrote `writeDepthTexture`
- Added `textureStore(dataTextureA, coord, outColor)` for temporal feedback
- Rewrote headers to the standard 7-line `Features:` block; added/extended JSON
  `features` arrays with `generative, upgraded-rgba` (+ `raymarched`/`temporal` etc.)

### Cohort B — dataA + tag sync only (7 shaders, score 12)
`gen-quasicrystal`, `gen-string-theory`, `gen-nebular-chrono-astrolabe`,
`gen-graviton-plasma-lotus`, `gen-quantum-aether-origami`, `gen-voronoi-crystal`,
`gen-xeno-botanical-synth-flora` — already had `plasmaBuffer`-driven audio, depth
writes, and (mostly) semantic alpha from prior batches; only `dataTextureA` and the
`upgraded-rgba` tag were missing. For each:
- Added `let outColor = vec4<f32>(...)` (factored from the existing final-color
  expression) and `textureStore(dataTextureA, coord, outColor)`
- Added `upgraded-rgba` (+ any other accurate-but-missing tags like `temporal`,
  `depth-aware`, `chromatic-aberration`) to header `Features:` and JSON `features`
- One exception: `gen-quantum-aether-origami` had two `vec4(col, 1.0)` hardcoded-alpha
  branches (hit + background) despite a `// (alpha already semantic)` comment — fixed
  both to luma-derived semantic alpha as part of the sync pass

## Validation
- All 12: `naga {file}.wgsl` → **Validation successful**
- `node scripts/generate_shader_lists.js` → 1130 definitions regenerated; only the
  pre-existing unrelated `gen-showcase-nebula-core` workgroup_size warning remains
- `node scripts/check_duplicates.js` → 1130/1130 unique IDs, no duplicates

## Visual Notes
- Cohort A's `treble`-driven accents are intentionally subtle (≤0.5 weight) — they add
  shimmer/sparkle on cymbal hits without overpowering each shader's existing palette.
- `gen-quantum-aether-origami`'s background-glow branch previously had alpha pinned to
  1.0 even in near-empty space; the new `luma * 1.5` formula now lets the void read as
  translucent, which should composite more naturally in layer chains.

## Remaining Risks
- `gen-fractal-bioluminescence-spore-network`'s `outDepth = t / 20.0` and similar
  raymarch-distance-based depth values assume the existing `max_t`/break thresholds;
  if a future tweak changes march distance, the depth normalization divisor should be
  updated alongside it.
- None of the 12 received chromatic aberration (out of scope for this pass — `gen-string-theory`
  already had it). Could be a natural follow-on for a future polish batch.
