# bubble-chamber — Kimi Notes (Algorithmist)

**Role:** Algorithmist
**Batch:** kimi-generative-2026-07-22-b12
**Date:** 2026-07-22

## Key changes

- **Bragg-curve ionization falloff** — new `braggGain(t, prominence)`:
  decayed trail luma `t` drives a per-frame gain that is ~1.0 on the bright
  body of a track, has a Gaussian deposition bump at `t ≈ 0.16` (the Bragg
  peak where a particle dumps its remaining energy before stopping), and
  cuts off smoothly below `t ≈ 0.045` so dead tracks vanish. Trails now read
  as physical particle tracks with bright tail-end "stopping points" instead
  of uniform worms. Prominence is driven by Detail (`0.35 + 1.05 * p4`).
- **Mouse Lorentz deflection** — new `lorentzVortex()`: softened 1/r
  tangential point-vortex (divergence-free away from the softened core)
  centered on the cursor. Strength = `(0.0008 + 0.006 * mouse_down) *
  (0.4 + 0.6 * Intensity)`, so pressing the mouse visibly bends nearby
  tracks around the cursor like a magnetic pole.
- **Param double-duty cleanup (zoom_params.z)** — Scale now owns ONLY the
  spatial frequency of the chamber (`noise_scale = 1.2 + 4.2 * p3`, applied
  to the curl-noise domain, spawn-cell size, and warped-FBM drift domain).
  Spawn density moved to Intensity × Detail:
  `spawn_rate = 0.04 + 0.35 * p1 * (0.4 + 0.6 * p4)`.
- **Slider rewiring (ids/defaults untouched, saved-preset contract kept):**
  - p1 Intensity → field strength, spark brightness (`1.4 + 2.2 * p1`),
    spawn density, Lorentz strength.
  - p2 Speed → advection step length (`vel_scale = 0.30 + 1.45 * p2`) and
    flow evolution rate (`flow_time = time * (0.45 + 0.85 * p2)`). No
    longer backwards-mapped to decay.
  - p3 Scale → spatial scale only (see above).
  - p4 Detail → Clifford drift, chromatic channel rotation, turbulence
    amplitude, Bragg prominence.
- **Feedback safety (CAUTION honored):**
  - Divergence-free advection kept intact (curl noise + point vortex; the
    small Clifford perturbation is unchanged from the original).
  - Trail accumulation hard-clamped **pre-tint** at `TRAIL_CLAMP = 1.2`
    (`min(shifted_history, vec4(TRAIL_CLAMP))`) before the chromatic
    rotation re-injects energy — luma-echo-warp lesson.
  - Decay fixed at 0.962 (< 1/(1+prominence) at the Bragg bump), so the
    Bragg gain settles at a finite equilibrium instead of blowing out.
  - Advection sample UV clamped to [0,1] to avoid edge wrap artifacts.
- Core algorithm (curl-noise field + Clifford + gold-noise spawn +
  warped-FBM drift + max-composite feedback) preserved — upgrade, not rewrite.

## JSON

Added `updatedParams` (index 0–3, names/defaults/min/max/step exactly as
brief) and `"updated": true`. No other fields touched.

## Line delta

163 → **229** lines (**+66**, within the +50 to +90 target; inside the
213–253 target band).

## Gate

```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/bubble-chamber.wgsl
→ Passed: 1 | Failed: 0 | Warnings: 0  (naga OK, bindgroup compatible)  exit 0
```

## QA flags

- **No GPU in this VM** — `navigator.gpu` unavailable; visual QA deferred.
  Bragg-bump equilibrium, Lorentz bend visibility, and spawn density feel
  need an on-GPU pass. Constants are conservative (clamp 1.2, decay 0.962)
  so blowout risk is low.
- Bragg gain is applied to the decayed history every frame; at Detail = 1
  the tail-end equilibrium sits at ~1.2 luma (the clamp), which is
  intentional (bright "stopping points"), but worth eyeballing on GPU.
- `textureStore` to writeTexture / writeDepthTexture / dataTextureA every
  frame; canonical 13-binding layout; `@workgroup_size(16, 16, 1)`.
