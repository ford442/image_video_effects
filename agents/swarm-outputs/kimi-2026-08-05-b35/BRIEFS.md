# Batch 35 briefs — 2026-08-05 (tracker #316–323)

Next 8 smallest pending clean single-pass generative shaders (no prior upgrade
marker, not in any completed batch). 4-agent swarm, 2 shaders each.

| # | Shader | Lines | Agent |
|---|--------|-------|-------|
| 316 | gen-bioluminescent-cyber-aether-void-seahorse | 153 | Algorithmist |
| 317 | gen-velocity-bloom | 169 | Algorithmist |
| 318 | gen-dragon-curve | 178 | Visualist |
| 319 | gen-fractal-chrono-dendrite-forge | 180 | Visualist |
| 320 | gen-raptor-mini | 184 | Interactivist |
| 321 | gen-bismuth-singularity-loom-engine | 186 | Interactivist |
| 322 | gen-3d-sierpinski-chaos | 192 | Optimizer |
| 323 | gen-astro-kinetic-chrono-orrery | 199 | Optimizer |

Notes:
- `gen-fractal-chrono-dendrite-forge` is the cohort fixer-upper: no
  `updatedParams` and a legacy `@workgroup_size(8, 8, 1)` — wire 4 indexed
  params and bring it to 16x16x1.
- All others have 4 indexed `updatedParams` already — that array is the
  saved-preset contract; keep it byte-exact.

## Non-negotiable contract (every shader)

- Canonical 13-binding header verbatim (agents/WGSL_BUILTINS_GENERATIVE.md §0);
  Uniforms struct EXACTLY `config, zoom_config, zoom_params, ripples`.
- `@compute @workgroup_size(16, 16, 1)` + resolution bounds guard on
  global_invocation_id.
- Write `writeTexture`, `writeDepthTexture`, and `dataTextureA` EVERY frame.
- Only `textureSampleLevel`/`textureLoad`/`textureStore`. No `textureSample`,
  `dpdx/dpdy`, no WGSL reserved words as identifiers.
- Uniform truth: config = [time, rippleCount, resW, resH];
  zoom_config = [time, mouseX, mouseY(top-down, 0=top), mouseDown].
  Guard ripple loops with `min(u32(u.config.y), 50u)`.
- extraBuffer: [0..4] engine-reserved, [5..132] engine FFT bins (read-only);
  persistent state ONLY in [133..138], single-writer guard
  (`gid.x==0u && gid.y==0u`) + arrayLength check.
- Audio ONLY from plasmaBuffer[0].xyz (bass/mids/treble) + FFT bins 1–8
  (guarded) — no hash-based fake spectrum.
- rgba32float feedback: reads via non-filtering `textureLoad`; A = primary
  state/display history (host copies B→C then A→C); writeTexture is
  presentation-only.
- Semantic alpha — never hardcode 1.0 unless opaque by design. Real generated
  depth (relief/hit depth), not flat-0.0 or copied source depth.
- Saved-preset contract: existing `updatedParams` arrays stay byte-exact;
  metadata additions (features, description) are additive and truthful.
- Preserve each shader's soul — upgrade, don't rewrite.

## Deliverables per shader

1. Updated `public/shaders/<id>.wgsl`
2. Updated `shader_definitions/generative/<id>.json` (only if additive changes
   are needed — params contract stays exact)
3. Output note `swarm-outputs/kimi-2026-08-05-b35/<id>.md` (changes, rationale,
   perf estimate)
