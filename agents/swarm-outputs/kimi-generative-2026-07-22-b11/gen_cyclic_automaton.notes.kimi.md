# gen_cyclic_automaton — Upgrade Notes (Kimi)

**Role:** Algorithmist
**Date:** 2026-07-22
**Shader:** `public/shaders/gen_cyclic_automaton.wgsl`
**JSON:** `shader_definitions/generative/gen_cyclic_automaton.json`

## Key changes

- **Wavefront leading-edge tracer:** added `refractoryProgressOf()` helper; computes the refractoryProgress gradient (max/min span) across the 4 cardinal neighbors. Firing cells backed by a cooling trail (`leadingEdge`) plus very-early refractory cells (`earlyRefr`) get a thin bright `tracerColor` ring (warm white → cyan tinted by treble), so propagating wavefronts read as crisp rings instead of a uniform glow. Tracer gain scales with the Bloom slider.
- **Treble ignition sparks:** `plasmaBuffer[0].z` now drives a fine, fast hash-noise pattern (`sparkHash`, time-scrolled at 113.7/−91.3) that raises spontaneous-ignition probability — hi-hats seed scattered new wave centers. Sparks also add a brief pale flash on ignition.
- **Directional mouse painting:** previous mouse position + down-state persisted in `extraBuffer[5..7]` (indices 0..4 untouched, per CAUTION). While dragging, the radial mouse mask is weighted by `dot(pixelDir, motionDir)` (squared, gated by smoothed drag speed), biasing ignition along the stroke direction for cardiac-style wavefronts. Single writer thread (coord 0,0) updates the buffer.
- **Slider rewiring (all 4 wired via `u.zoom_params.x/y/z/w`, ids/defaults unchanged):**
  - `param1 States` → `numStates` (4–24, automaton depth) — unchanged.
  - `param2 Spontaneity` → `spontaneousBase` ignition probability — unchanged, now also scales treble-spark probability.
  - `param3 Bloom` → `bloomStrength`, now additionally drives tracer ring gain — more visible.
  - `param4 Cooldown` → was color-only; now also drives `cooldownCurve` (pow exponent 1.7→0.55 on refractoryProgress), visibly stretching/compressing the cooling tail, plus the existing color ramp.
- **State machine preserved:** resting=0 / firing=1 / refractory≥2 select-chain kept logically intact (verbatim); all upgrades are around the rule, not inside it.
- `dataTextureB` repurposed debug channels: `(cardFiring/4, tracer, mouseMask, motionGain)`.
- Depth and alpha now also respond to the tracer ring (wavefronts lift slightly in depth).
- Canonical 13-binding layout and `@workgroup_size(16, 16, 1)` preserved; no new bindings.

## Line count delta

- Before: 138 lines → After: **200 lines** (+62, within the +50..+90 budget; target band 188–228 ✓)

## QA flags

- `wgsl_precommit_gate.py`: **exit 0, 0 warnings** (naga OK, bindgroup compatible).
- Constants (spark rate ×9.0, motion gain ×45.0, tracer smoothstep edges 0.03/0.28, cooldown curve 1.7→0.55) are **eyeballed**, not visually tuned.
- **This VM has no GPU adapter** — visual QA (wavefront ring legibility, drag-direction feel, hi-hat spark density) is deferred to a GPU-equipped environment.
- extraBuffer read/write across threads is a benign one-frame tear risk (same codebase idiom as other generative shaders); single-writer guard used.
