# Batch 37 briefs — 2026-08-06 (tracker #332–339)

Next 8 smallest pending clean single-pass generative shaders. 4-agent swarm,
2 shaders each. 7 of 8 already have 4 indexed `updatedParams` (saved-preset
contract: byte-exact); `gen-symbiotic-cyber-fungal-core-reactor` has none —
generate 4 indexed additive updatedParams from its existing JSON params
(Dendrite-forge precedent, effective defaults preserved).

| # | Shader | Lines | Agent |
|---|--------|-------|-------|
| 332 | gen-fireworks-fan-shell | 169 | Algorithmist |
| 333 | gen-fireworks-horse-tail | 170 | Algorithmist |
| 334 | gen-fireworks-ring-shell | 170 | Visualist |
| 335 | gen-fireworks-kamuro-gold | 173 | Visualist |
| 336 | gen-symbiotic-cyber-fungal-core-reactor | 184 | Interactivist |
| 337 | gen-evolutionary-cellular-gardens | 207 | Interactivist |
| 338 | gen-chrono-kitsune-prism-weaver | 208 | Optimizer |
| 339 | gen-quantum-fluorescent-aether-moth-swarm | 208 | Optimizer |

Known bug class to check: fireworks-family normalized-pointer mistakes
(Batch 23 precedent).

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
- Every declared slider must be LIVE, driving a shader-specific constant.
- Preserve each shader's soul — upgrade, don't rewrite.

## Deliverables per shader

1. Updated `public/shaders/<id>.wgsl`
2. Updated `shader_definitions/generative/<id>.json` (additive only)
3. Output note `swarm-outputs/kimi-2026-08-06-b37/<id>.md`
