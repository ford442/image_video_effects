# gen_grid — Batch 19 Upgrade Notes (Kimi)

**Shader:** `public/shaders/gen_grid.wgsl` (id `gen-grid`, generative)
**Line delta:** 241 → 307 (+66 lines, target +50–90 ✅, within 291–331 band ✅)

## Changes

1. **Per-cell FFT moiré shimmer** — new `cellBin(cell)` helper hashes the warped
   grid cell id (`floor(warpedP * gridSize)`) into `plasmaBuffer[1..8]` (bins 1–8,
   read-only). Each cell's band energy (`binEnergy`) now drives the recursive
   moiré sub-grid: spin speed `time * (0.4 + binEnergy * 1.4)` plus a static
   phase offset, and intensity `0.35 + binEnergy * 0.9`. Neighbouring cells
   shimmer on different bands → spatially varied moiré.

2. **Click ripple warp pulses** — loop `for (ri < min(u32(u.config.y), 50u))`
   over `u.ripples`. Live ripples (age 0..3s) emit an expanding sine wavefront
   `sin(dist*24 - age*9) * exp(-dist*3) * life²` that displaces the sample
   point (`pulsedP = p + rippleWarp`) before domain warping — so the grid
   lattice itself bends outward from each click. A faint luminous ring
   (`rippleGlow`) rides the wavefront radius `age * 0.35` and is added to the
   composed color. All three domain-warp samples (main + chroma R/B) use
   `pulsedP`, so chromatic dispersion follows the pulse.

3. **Spring-damped gravity well** — `springStep()` (critically damped,
   `accel = ω²(aim−pos) − 2ω·vel`, ω=5.0, dt=0.016). State stored ONLY in
   `extraBuffer[133..136]` (pos.xy, vel.xy); single-writer guarded by
   `global_id.xy == (0,0)`. First frames (`time < 0.1`) snap pos to cursor and
   zero velocity (no separate init-flag slot needed, keeping writes strictly
   within 133..136 per spec). The attractor passed to `domainWarp` is the
   spring position, so the mouse gravity well glides with visible lag.

## Soul preserved
Domain-warped FBM (`domainWarp` unchanged), recursive mini-grid moiré,
chromatic dispersion edges, treble sparkle, vignette, ACES tonemap, temporal
feedback blur (`dataTextureC` mix with `warpAmount * 0.35` clamp 0..0.55) —
all untouched. `writeTexture` / `writeDepthTexture` / `dataTextureA` written
every frame as before.

## Slider wiring (unchanged — all 4 live)
| param | zoom_params | use |
|---|---|---|
| param1 Warp Amount | x | `warpAmount` (also scales feedback blur) |
| param2 Grid Density | y | `gridDensity` (warp scale + grid size) |
| param3 Line Thickness | z | `thickness` (lines, glow, dispersion, mini) |
| param4 Palette Shift | w | `shift` (palette phase) |

JSON: added `updatedParams` (4 entries, index 0–3, ids param1–4, same
names/defaults/min/max/step) and `"updated": true`. Nothing else touched.

## Binding compliance
Canonical 13-binding layout unchanged (0–12). `@workgroup_size(16, 16, 1)`.
No writes to extraBuffer[0..132]; reads of plasmaBuffer only. No WGSL
reserved keywords as identifiers.

## QA flags
- `wgsl_precommit_gate.py`: PASS (1 file, 0 failed, 0 workgroup errors,
  0 extraBuffer violations). NOTE: `naga` binary is not installed in this
  environment, so the naga validation step is skipped by the gate itself
  (environment limitation, not a shader warning). Bindgroup + workgroup
  checks ran and passed.
- `audit_extrabuffer.py`: **AUDIT PASS** (0 new violations, 0 dynamic writes).
- `audit_dead_sliders.py`: **AUDIT PASS** (0 dead sliders).
