# Upgrade Notes: temporal-rgb-smear (Interactivist, 2026-07-21)

## Line-count delta
- Original: 220 lines → Upgraded: 296 lines (**+76**, within the +50…+90 target; final 296 inside the 270–310 target band)

## Changes by domain

### Interactivity / mouse (primary role focus)
- Added a **spring-damper mouse tracker** with persistent state in `extraBuffer` (slots 0–6: smoothed mouse xy, velocity xy, previous raw mouse xy, init flag), following the established `cyber-rain.wgsl` pattern. `dt` comes from `u.config.y`, clamped to `[0, 0.1]` for first-frame/tab-switch safety; first frame initializes smoothly to the cursor via an init flag.
- **Mouse Spring slider** (`zoom_params.y`) scales stiffness (18→90) and damping (5→14): low = loose/floaty, high = tight/snappy.
- **Velocity-driven smear lean**: normalized spring-head velocity bends `smearDir` (up to 65% blend via `smoothstep(0.15, 1.4, velMag)`), so fast flicks drag the RGB smear along the pointer direction and it settles smoothly when the mouse stops.
- Mouse speed also stretches smear length up to +35% for gestural feel.
- Mouse-proximity treble sparkle now measures distance to the **smoothed** pointer instead of the raw one (consistent with the spring).

### Feedback stability
- **Pre-write clamp**: `history` is clamped to `[0, Feedback Clamp]` before both tone mapping and the `dataTextureA` store, so the temporal feedback loop can never run away (luma-echo-warp lesson). Ceiling is the slider `zoom_params.w` clamped to `[1.0, 2.0]`, default 1.2 per brief.
- Removed the unused `hC` luminance read (dead code from the original gradient block).

### Audio reactivity
- New `sparkleGrain()` helper: full-frame fine animated grain — two decorrelated time-stepped `hash21` samples interpolated at 24 Hz, intensity follows `treble` (`plasmaBuffer[0].z`), scaled by the **Sparkle Grain slider** (`zoom_params.z`, ×0.35). Added to history before the clamp so it feeds the trails.

### Slider rewiring (4 params, index 0–3, per brief `updatedParams`)
- `x` (0): Smear Length — unchanged semantics (`mix(0.01, 0.25, p1)`), now also mouse-speed modulated.
- `y` (1): Mouse Spring — **new** (was Smear Decay).
- `z` (2): Sparkle Grain — **new** (was Chromatic Split).
- `w` (3): Feedback Clamp — **new**, range 1.0–2.0 (was Turbulence).
- Displaced roles kept at legacy defaults as constants: smear decay 0.776 (= `mix(0.3, 0.98, 0.7)`), chromatic split 0.025 (= `mix(0.0, 0.05, 0.5)` base), turbulence 0.3 — preserving the shader's look at default settings.

### Preserved (soul / hard rules)
- Canonical 13-binding layout untouched; no binding 13 added; `@workgroup_size(16, 16, 1)` kept.
- Core algorithm intact: curl-noise flow direction, domain-warped drift, Halton-jittered RGB channel split sampling, per-channel feedback decay, ACES tone map, 5-layer `compositeAlpha` (luma key, edge preserve, effect intensity, depth layer, accumulative trails) — all unchanged.
- All sampler reads use `textureSampleLevel(..., 0.0)`; writes to `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame; no reserved-keyword identifiers.

## QA flags
- **Eyeballed constants** (not GPU-tuned): spring stiffness/damping ranges (18–90 / 5–14), velocity lean thresholds (0.15–1.4, 65% blend), mouse-speed length boost (0.35), grain temporal rate (24 Hz) and amplitude (×0.35), treble shimmer mapping (0.35 + 0.65·treble·0.5).
- **No-GPU caveat**: validated with naga via `scripts/wgsl_precommit_gate.py` (exit 0, bindgroup compatible) only — the headless VM has no WebGPU adapter, so visual behavior (spring feel, grain intensity, clamp ceiling) has NOT been eyeballed on real hardware. Recommend a quick on-GPU pass of the Mouse Spring and Sparkle Grain sliders.
- **extraBuffer race note**: all threads write identical spring-state values (uniform inputs), matching the existing `cyber-rain.wgsl` convention — benign in practice.
- **Naga gotcha hit & fixed**: `mix(0.3, 0.98, 0.7)` with all-abstract-float args fails naga ("couldn't convert to concrete type"); replaced with the precomputed literal `0.776`.
- **JSON**: parses clean; brief version written verbatim — `params[]` still documents legacy mappings while `updatedParams[]` (index 0–3) carries the new slider semantics, matching the brief exactly.
