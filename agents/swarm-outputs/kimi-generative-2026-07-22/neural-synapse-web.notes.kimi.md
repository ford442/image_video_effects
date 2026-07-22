# Notes: neural-synapse-web (Interactivist upgrade)

**Role:** Interactivist
**Date:** 2026-07-22
**Shader:** `public/shaders/neural-synapse-web.wgsl`
**JSON:** `shader_definitions/generative/neural-synapse-web.json`

## Key changes

- **Spring-damper mouse attractor (extraBuffer state):** attractor position/velocity
  persisted in `extraBuffer[133..136]`; integrated every frame with a damped spring
  (`springK = 18.0`, `damping = 7.0`, dt from `u.config.y` clamped to [0.001, 0.05]).
  The web now follows the mouse with damped overshoot — fast mouse moves make it
  lunge, then settle. Replaces the old raw `mouse * 0.15` offset.
- **Web lunge:** nodes lean toward the attractor proportional to attractor speed
  (`lunge = sat(length(newVel) * 0.35)`, pull factor `lunge * 0.12`), so fast flicks
  visibly drag the network before it relaxes.
- **Click pulse wave:** rising edge of `zoom_config.w` (mouse-down) stamps click
  origin + birth time into `extraBuffer[137..139]`. An expanding ring
  (radius `age * 1.4`, gaussian band width 90, amplitude decay `exp(-age * 1.1)`,
  3 s lifetime) boosts node glow (×1+2·ring), synapse brightness (×1+ring), and
  signal gain (×1+1.5·ring) as it sweeps past, plus a faint blue ring tint.
- **Treble-reactive synapse sparkle:** animated grain
  (`hash21(floor(p * 220) + floor(time * {23,17}))`, thresholded by
  `smoothstep(0.55, 0.95, grain)`) masked by `lineGlow * signal * treble`
  (via `plasmaBuffer[0].z`) — only actively firing synapses shimmer. Rendered as a
  white additive term and folded into `dataTextureA.z`.
- **Slider wiring (contract preserved):** kept the 4 existing params with identical
  ids/defaults/min/max/step/mapping — `nodeCount` → node count 3–16,
  `pulseSpeed` → pulse/signal travel speed 0.2–3.0, `connectivity` → edge probability
  0.1–1.0, `signalGain` → node/signal brightness 0.3–2.0. All four drive real
  shader-specific constants (unchanged semantics, now layered with ring/lunge boosts).
- **extraBuffer discipline:** `extraBuffer[0..4]` untouched (engine-reserved);
  FFT bins `[5..132]` untouched; state lives at `[133..141]`, well inside the
  256-float buffer. Writes happen only from thread (0,0) to avoid write races;
  all threads integrate the spring locally from the read state for consistency.
- Canonical 13-binding layout and `@workgroup_size(16, 16, 1)` preserved; writes to
  `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame; temporal
  feedback via `dataTextureC` retained; ACES tone map retained.

## Line count delta

- Before: **126** lines
- After: **205** lines (+79, within the +50…+90 / 176–216 target)

## Gate result

- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/neural-synapse-web.wgsl`
  → **PASS** (exit 0): naga OK, bindgroup compatible, 0 workgroup errors, 0 warnings.

## QA flags

- **No GPU in this VM** — visual QA deferred. Verify on real hardware:
  - Spring feel: `springK = 18.0` / `damping = 7.0` are eyeballed (slightly
    underdamped for visible overshoot). Tune if the lunge feels too loose/stiff.
  - Ring constants eyeballed: speed 1.4 units/s, band sharpness 90, decay 1.1/s,
    3 s life — confirm the sweep reads well at typical canvas sizes.
  - Sparkle grain scale 220 px⁻¹ and threshold 0.55–0.95 eyeballed; check it's
    shimmer, not noise, at high treble.
- **Benign cross-workgroup race:** non-(0,0) threads may read either previous- or
  current-frame attractor/click state (single-dispatch read-then-write, standard
  pattern in this codebase, e.g. `echo-trace.wgsl`). Worst case is a one-frame
  inconsistency across the screen; not visually significant, but noted.
- First frame: `STATE_INIT` flag (extraBuffer[141]) initializes attractor to the
  mouse and clickBirth to -1000 so no spurious ring fires on load.
- Mouse y-convention: `zoom_config.yz` (y=0 top) maps to p-space y directly
  (`mouseRaw = yz*2-1`, no flip) — matches original shader behavior; confirm
  attractor tracks the cursor direction correctly on GPU.
