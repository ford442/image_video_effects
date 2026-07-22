# phase-memory-weave — Optimizer Notes (Kimi, 2026-07-22, batch 12)

**Role:** Optimizer
**Shader:** `public/shaders/phase-memory-weave.wgsl` (generative)

## Line delta
- Before: 165 lines → After: **233 lines** (+68, within the +50..+90 brief window; target band 215–255 ✓)

## Key changes
1. **Opalescent interface iridescence** — new `opalescentPalette()` (thin-film cosine palette, 120° hue offsets) keyed on the **local phase-gradient magnitude** computed from neighbor order-parameter samples (`gradR`/`gradI`). Mixed into `baseCol` at `opalMask * 0.3` so domain boundaries shimmer like opal while the fluid/crystal base palette stays dominant. Existing curvature-driven `thinFilmIridescence` retained.
2. **Memory-loop stability** — `MEM_CLAMP = 1.2` and `MEM_DECAY = 0.9985` constants. The multi-scale memory accumulation (`memoryBlend`, `newSlow`, and the new `memSheen` pre-tint term) is clamped at ±1.2 and the slow-memory buffer is multiplied by a tiny epsilon decay each frame so it cannot latch (luma-echo-warp lesson). Early-exit path uses the same latched-proof `newSlow` (computed once, hoisted above the exit).
3. **Mouse thermal pulse** — rising-edge detection via `extraBuffer[5]` (previous mouse-down state). On mouse-down edge, ring emission time and origin are latched into `extraBuffer[6..8]` (indices 0..4 untouched, per reservation). An **expanding gaussian heat ring** (`ringAge * ringSpeed` radius, gaussian width, `RING_LIFETIME = 2.5s` fade) forces phase change where it passes; sign follows click parity (`isHeat`) — heat pushes crystalline, cold pushes fluid.
4. **Slider rewiring (saved-preset contract preserved — ids/defaults/min/max/step unchanged)**:
   - `p1` Phase (zoom_params.x): replaced the generic exposure multiplier with a real **phase bias** — shifts the GL equilibrium amplitude (`equilibrium = 1.0 + phaseBias*0.4`) and the fluid/crystal mask crossover thresholds.
   - `p2` Memory Strength (zoom_params.y): drives memory kernel blend (`memStrength`), the **memory write rate** (`memLerp = 0.05 + p2*0.12`), and the memory-sheen tint strength. Removed its generic contribution to `mobility` (mobility is now purely mids-driven per the description: "mids control grain boundary mobility").
   - `p3` Turbulence (zoom_params.z): keeps GL interface energy `epsilon`, plus a new **fluid-gated chaotic jitter** term added to the order parameter.
   - `p4` Mouse Disturbance (zoom_params.w): keeps thermal blob amplitude and now also drives **ring speed, gaussian width, and ring forcing amplitude**.
5. Added the mandatory bounds guard (`gid >= res → return`) from the generative preamble.

## Preserved
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`.
- `fast_atan2` polynomial, branchless audio seeding / `select` thermal parity, early-exit for quiescent pixels, 4-sqrt curvature, TAU constant — all prior optimizations intact.
- Writes to `writeTexture`, `writeDepthTexture`, and `dataTextureA` on every path every frame.
- Core Ginzburg-Landau / Allen-Cahn algorithm unchanged (upgrade, not rewrite).

## JSON
- `shader_definitions/generative/phase-memory-weave.json`: appended `updatedParams` (indices 0–3, matching names/defaults/min/max/step from the brief) and `"updated": true`. No other fields touched. Validated with `json.load`.

## QA
- **Gate:** `python3 scripts/wgsl_precommit_gate.py --files public/shaders/phase-memory-weave.wgsl` → **exit 0** (naga OK, bindgroup compatible, 0 workgroup errors, 0 warnings).
- **Flags:**
  - No GPU adapter in this VM — **visual QA deferred** (opal shimmer strength 0.3 mix, ring forcing amplitude, and `memSheen` tint should be eyeballed on real hardware).
  - extraBuffer ring state is written unconditionally per-thread with identical values (benign race); rising-edge detection is per-frame global, not per-pixel.
  - `extraBuffer[6..8]` assume a zero-initialized buffer on first run; `ringFade` clamps garbage ages to zero forcing regardless.
