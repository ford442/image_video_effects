# gen-navier-stokes-ink upgrade notes

## Changes
- Added a second Jacobi pressure-projection iteration using neighbor divergence estimates.
- Replaced simple perturbation with curl-noise velocity perturbation (FBM-based).
- Added domain-warped FBM semi-Lagrangian advection.
- Added anisotropic density diffusion aligned to local flow direction.
- Added procedural dye SDF layer: orbiting ink drops + stretched filament at the mouse.
- Added vorticity confinement for tighter swirling.
- Refactored all per-pixel branching to branchless `select()` / `mix()` / `smoothstep()` operations.
- Updated `dataTextureB` to store pressure, curl, divergence, and speed for downstream passes.
- Updated JSON definition description and `features` list.

## Files touched
- `public/shaders/gen-navier-stokes-ink.wgsl`
- `shader_definitions/generative/gen-navier-stokes-ink.json`

## Final line count
246 lines

## Validation
1. `python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-navier-stokes-ink.wgsl` → ✅ passed
2. `node scripts/generate_shader_lists.js` → ✅ completed
3. `node scripts/check_duplicates.js` → ✅ no duplicate IDs
