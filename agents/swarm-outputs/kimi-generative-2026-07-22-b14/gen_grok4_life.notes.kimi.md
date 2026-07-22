# gen_grok4_life — Algorithmist Notes (kimi, 2026-07-22, batch b14)

**Shader:** `public/shaders/gen_grok4_life.wgsl` (SmoothLife Predator-Prey)
**Brief:** `swarm-tasks/kimi-generative-briefs-2026-07-22-b14/gen_grok4_life.md`

## Line delta

- Before: 176 lines → After: **251 lines** (**+75**, within target 226–266 / +50–90).

## Key changes per technique

1. **WRAP BUG FIX (priority 1):** Replaced the hardcoded `(px + off + res) & vec2<i32>(2047, 2047)`
   bitmask with a resolution-aware `wrap_px()` helper: `((p % size) + size) % size` using the
   actual texture size derived from `u.config.zw`. Toroidal wrapping is now correct at ANY
   canvas size. The 9x9 annular two-ring convolution structure per species is fully preserved.
2. **Spectral ecosystem zonation:** New `zoneEnergy()` splits the screen into three vertical
   biomes (soft-blended at x≈1/3 and x≈2/3). Left third follows bass FFT bins
   (`plasmaBuffer[2..4].x`), middle follows mid bins (`[9..11].x`), right third treble bins
   (`[16..18].x`). Zone energy scales the Lotka-Volterra coupling (`mix(0.6, 1.5, zoneE)`),
   so predation pressure, predator growth, and predator birth all vary spatially → distinct
   ecological zones emerge across the canvas.
3. **Age-based prey ramp:** Prey color now interpolates cyan-white (young) → deep green (old)
   via `smoothstep(0.05, 0.6, newAge)` with a subtle residual hue-cycle shimmer, so colony
   generations read visually. Added an **extinction-event bloom pulse**: thread (0,0) coarsely
   samples a 4×4 grid, maintains a smoothed global population EMA in `extraBuffer[133]`, and
   on a sharp crash (drop > 0.08 from a pop > 0.15) sets a bloom pulse in `extraBuffer[134]`
   that decays ×0.975/frame; all pixels add a warm global flash scaled by the pulse.
   Persistent state confined to extraBuffer[133..134] (within the allowed [133..255] range).
4. **Slider wiring (4 params, contract unchanged):**
   - `timeStep` (x) → integration step `dt` (clamped 0.01–0.5).
   - `sharpness` (y) → SmoothLife birth/survival transition steepness.
   - `colorSpeed` (z) → hue-cycle rate AND age-advance rate (generational tempo).
   - `initDensity` (w) → reseed probability AND seed-blob radius (0.03 + 0.04·w).
   Existing mapping was already shader-specific; enhanced z/w to drive additional real
   constants of this shader's algorithm rather than generic boilerplate.

## Binding contract compliance

- Canonical 13-binding layout unchanged; no new/renumbered bindings; no historyTexture.
- `@workgroup_size(16, 16, 1)` preserved.
- `writeTexture`, `writeDepthTexture`, and `dataTextureA` written every frame.
- Sampler reads use `textureSampleLevel(..., 0.0)`; storage reads use `textureLoad`.
- **dataTextureA carries SIM STATE** (prey, predator, age, activity) — written raw, never
  clamped/saturated/tonemapped (the per-species `clamp(newX, 0, 1)` is the pre-existing
  simulation range guard, unchanged from the original algorithm).
- No WGSL reserved identifiers used.

## JSON

- `shader_definitions/generative/gen_grok4_life.json`: `updatedParams` (4 entries, index 0–3,
  mirroring existing params ids/names/defaults/min/max with step 0.01) and `"updated": true`
  present; nothing else changed. NOTE: when I opened the file to edit it, it already contained
  exactly this block (likely applied concurrently by another process) — verified it matches the
  brief's contract field-for-field and left it as-is.
- `python3 -c "import json; json.load(...)"` → **OK**.

## Gate result

```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen_grok4_life.wgsl
→ Passed: 1 | Failed: 0 | Warnings: 0  (naga OK, bindgroup compatible)  exit 0
```

## QA flags

- **No-GPU caveat:** this headless VM has no WebGPU adapter, so visual QA (zone emergence,
  age ramp readability, extinction bloom timing) is **deferred to real hardware**. Correctness
  validated via naga parse + bindgroup gate only.
- Extinction monitor: reads of `extraBuffer[133/134]` by non-writer threads may lag one frame
  (single-writer EMA) — visually benign, intentional.
- FFT bin indices 2–4 / 9–11 / 16–18 for zonation assume plasmaBuffer[1..k] are per-bin
  energies per engine convention; if bin count/layout differs, zone contrast may vary but
  nothing breaks (values are clamped).
