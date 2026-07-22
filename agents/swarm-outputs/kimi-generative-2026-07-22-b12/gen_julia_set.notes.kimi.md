# gen_julia_set — Optimizer Notes (Kimi, 2026-07-22, batch b12)

**Role:** Optimizer
**Files touched:** `public/shaders/gen_julia_set.wgsl`, `shader_definitions/generative/gen_julia_set.json`

## Line delta
- Before: 169 lines → After: **254 lines** (**+85**, within the +50..+90 brief window; target 219–259 ✅)

## Key changes
1. **Audio c-morph (Lissajous):** Julia constant `c` keeps its cardioid orbit (`cR=0.7885`, golden-ratio winding) and now gets a slow Lissajous perturbation `lissAmp * (sin(0.71t), sin(1.13t + 1.31))` whose amplitude follows bass (`0.06 + bass*0.22`) — the set breathes with the music. **Mouse drag overrides**: when `zoom_config.w > 0.5`, `c` is taken directly from mouse UV (y-flipped into complex-plane orientation).
2. **Interior filaments:** non-escaping pixels are no longer a flat trap-color wash. A per-iteration filament accumulator bands the change of `|z|` between successive iterates (`0.5 + 0.5*sin(dz*22 + i*0.35)`), producing fine filament texture modulated by trap proximity in hue and value.
3. **Hash-jitter AA:** 2-sample rotated grid — canonical `hash21(pixel) * TAU` picks a per-pixel rotation angle; the pixel is evaluated at `baseP ± jOff` (sub-pixel radius in complex units) and averaged. Trap bands and filament edges are smoothed. Core iteration was refactored into a `juliaRender()` function returning a `JuliaSample` struct so both AA samples share identical math.
4. **Temporal clamp (luma-echo-warp lesson):** `finalColor` is clamped to `vec3(1.2)` **pre-tint** before the feedback mix, and the sampled history `prev.rgb` is also clamped to 1.2 — accumulation can no longer bloom to white.
5. **ACES tone map** added as the final color transform to keep trap-glow highlights from clipping.

## Preserved (per CAUTION)
- Smooth-iteration formula `μ = i − log₂(log₂|z|)` (`smoothIter`) — mathematically untouched.
- All 3 orbit traps (`circTrap`, `lineTrap`, `crossTrap`) — mathematically untouched.
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, writes to `writeTexture` / `writeDepthTexture` / `dataTextureA` every frame. No binding 13 added (shader doesn't use history ring).
- Param contract unchanged: `zoom_params.x/y/z/w` = Zoom / Exponent n / Trap Mode / Trap Scale, same ids, names, defaults, min/max; each drives a real shader constant (zoom range, z^n exponent, trap select, trap radius × bass boost).

## JSON
- Added `updatedParams` (indices 0–3, matching names/defaults) + `"updated": true` exactly as in the brief. No other fields changed. Validated with `json.load`.

## QA flags
- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen_julia_set.wgsl` → **exit 0, 0 warnings** (naga OK, bindgroup compatible).
- **No GPU in this VM** — WebGPU adapter unavailable, so visual QA (filament density, AA quality, Lissajous amplitude feel, bass response) is **deferred to a GPU-equipped machine**.
- AA doubles the per-pixel iteration cost (2 × 128 max iters); expected to be fine for a 2D fractal compute pass, but perf should be spot-checked on low-end GPUs.
- `dataTextureA` channel contract kept identical to the pre-upgrade shader (smoothed/maxIter, trapDist, iterNorm, 1.0).
