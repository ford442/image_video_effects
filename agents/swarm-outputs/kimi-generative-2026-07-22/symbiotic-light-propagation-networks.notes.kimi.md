# Notes: symbiotic-light-propagation-networks (Interactivist upgrade)

**Role:** Interactivist
**Shader:** `public/shaders/symbiotic-light-propagation-networks.wgsl`
**Date:** 2026-07-22

## Key changes

- **Mouse seeding ring:** mouse-down rising edge (tracked via `extraBuffer[9]`) plants a frame-stamped seed in `extraBuffer[5..8]` (uv, plant time, strength). Single writer thread at gid(0,0); all other threads read-only. Slots 0–4 untouched per reserved-buffer CAUTION.
- **Expanding growth ring:** ring radius grows at 0.22 uv/s from the seed point with a hashed jitter and an `exp(-age*0.45)` fade; a band around the front locally boosts both species' growth and adds a bright bioluminescent rim color, so seeds feel *planted* and propagate.
- **Bass glow as spatial wave:** replaced the flat mouse-centered pulse with a slow radial sine wave (`seedDist*7.0 - time*1.8`) emanating from the seed point with exponential falloff — beats now travel along the network.
- **Feedback clamp:** temporal light accumulation is clamped pre-tint at 1.2 (luma-echo-warp lesson) so glow trails stabilize instead of saturating; decay slightly deepened (0.9 → 0.92) and mix 0.1 → 0.12 to compensate.
- **Slider rewiring (was generic `applyGenerativePrimaryControls` boilerplate — removed):**
  - `zoom_params.x` (Network Growth) → base growth constant (0.003–0.030) **and** diffusion kernel weight (0.12–0.24).
  - `zoom_params.y` (Light Transmission) → chromatic channel gain (0.2–0.7) **and** dispersion reach multiplier (0.5x–1.5x).
  - `zoom_params.z` (Symbiotic Strength) → support coefficient (0.1–1.2) vs competition coefficient (0.55–0.05), cross-mapped so high symbiosis = mutual aid.
  - `zoom_params.w` (Mouse Seeding Power) → direct seed strength (0.2–1.4) and planted ring strength (0.3–1.5).
- **Light transport drift:** transport direction slowly oscillates (`sin(time*0.11)*0.5` rotation) for organic motion; previously-unused `hash12` is now used for ring jitter.
- Preserved: canonical 13-binding layout, `@workgroup_size(16,16,1)`, dataTextureA state layout `(s1, s2, lightG, totalDensity)`, ACES tone map, all core growth/transport math.

## Line count delta

- Before: 133 lines
- After: 185 lines (+52, within the +50…+90 / 183–223 target)

## QA flags

- **No GPU on this VM** — naga validation + bindgroup gate pass (exit 0, 0 warnings), but visual QA is deferred to a real-GPU run.
- Eyeballed constants to verify visually: ring speed 0.22, ring band width 0.07, ring fade `exp(-age*0.45)`, bass wave frequency 7.0 / speed 1.8 / falloff 1.6, glow clamp 1.2.
- `extraBuffer` cross-thread read/write race (writer at gid(0,0), readers everywhere) is benign by design — a one-frame lag in seed visibility is acceptable, but confirm no flicker on real hardware.
- Rising-edge detection depends on `extraBuffer[9]` persisting across frames; verify the engine does not clear extraBuffer between frames.
