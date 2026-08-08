# Batch 38 briefs — 2026-08-06 (tracker #340–347) — FAST MOTION batch

Next 8 smallest pending clean single-pass generative shaders. 4-agent swarm,
2 shaders each. All 8 already have 4 indexed `updatedParams` (saved-preset
contract: byte-exact).

| # | Shader | Lines | Agent |
|---|--------|-------|-------|
| 340 | gen-sonoluminescent-chrono-geode-matrix | 209 | Algorithmist |
| 341 | gen-abyssal-quantum-leviathan-skeleton | 210 | Algorithmist |
| 342 | gen-eldritch-tesseract-hive-mind | 210 | Visualist |
| 343 | gen-stellar-web-loom | 210 | Visualist |
| 344 | gen-neon-plasma-biomechanical-hive | 211 | Interactivist |
| 345 | gen-sentient-aether-flora-biosphere | 212 | Interactivist |
| 346 | gen-magnetic-dipole-field | 213 | Optimizer |
| 347 | gen-mycelium-network | 213 | Optimizer |

## ⚡ USER DIRECTIVE: FAST MOTION (this batch's theme)

The user explicitly asked to add FAST MOTION to generative shaders. Every
shader in this batch must gain a meaningful sense of speed appropriate to its
soul. Toolkit (pick what fits, at least 2 per shader):

- **Velocity-advected motion-blur trails** via rgba32float feedback (A/C,
  textureLoad only) — decaying history that streaks fast elements; CLAMP the
  HDR history (≤ 4.0–8.0) so speed never blows up the feedback (Batch 36
  topology-flow lesson).
- **High-speed dynamics with frame-rate-independent integration** — semi-
  implicit Euler with dt from a persistent prev-time slot or analytic
  closed-form trajectories; never per-frame fixed steps that change speed
  with fps.
- **Speed streaks / speed lines** — directional stretch along velocity
  (anisotropic kernels, line SDFs along motion direction).
- **Burst dynamics on audio transients** — bass kicks trigger
  launches/shockwaves with bounded exp decay (rising-edge detect ok).
- **Time-warp easing** — fast-in/smooth-out motion curves rather than linear
  time scaling; temporal-coherent noise for high-frequency flutter that does
  NOT strobe (smooth value/curl noise, no per-frame hash jitter).
- **Fast orbiting/swarming** — closed-form orbital motion, curl-noise
  advection at high flow speeds with clamped advection fetches.

Stability rules for speed: velocities clamped, feedback energy bounded,
no aliasing strobes (smooth, don't hash-jitter), mouse/audio stays reactive
at speed.

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
3. Output note `swarm-outputs/kimi-2026-08-06-b38/<id>.md`
