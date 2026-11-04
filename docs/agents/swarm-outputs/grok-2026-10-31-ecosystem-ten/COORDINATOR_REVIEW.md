# Coordinator Review — 2026-10-31 Ecosystem Ten (10 Shaders)

## Scope & Contract Verification (`docs/SHADER_UPGRADE_BATCH.md`)

1. **Pre-WGSL Idea Cards (`BRIEFS.md`)**:
   - Written before editing WGSL with full §12.1 mechanism interrogation (state variables, packing in `dataTextureA`/`dataTextureC`, existing visual/simulation mechanisms, dead/half-wired paths, and 2–3 native ideas per shader).
2. **Identity & Saved Params Preservation**:
   - Every shader's core simulation, visual identity, `dataTextureA`/`dataTextureC` channel layout, and saved `params` array in `shader_definitions/**` remain byte-exact.
   - `bioluminescent` uses its previously unused `.g` channel in `dataTextureA` (`vec4(newGrowth, newLuciferin, 0.0, 1.0)`) while keeping `.r` (`prevGrowth`) untouched.
   - `bio-touch-em` keeps its `dataTextureA` write `vec4(color, n2)` and now reads `dataTextureC` on the next frame for ion-channel refractory glow and mitosis trail.
3. **Formula De-duplication (§12.4)**:
   - `isotropic 9-point Laplacian (§12.2D)` appears on 2 shaders (`cyber-organic-ecosystem`, `digital-moss-rgba`), within the ≤2 per batch rule.
   - All other 18 ideas are domain-specific to their respective ecological/biological/calligraphic mechanics.
   - Zero generic spring/ripple/vignette/IQ-palette stamps added.
4. **Plumbing Floor (§6)**:
   - `#include "_prelude.wgsl"` on all 10 files (0 pasted headers).
   - `@workgroup_size(16, 16, 1)` on all 10 files.
   - Exact `textureLoad(dataTextureC, ...)` on all `dataTextureC` reads (removed `textureSampleLevel(dataTextureC, u_sampler, ...)` from `cyber-organic-ecosystem`, `gen-xeno-botanical-ecosystem`, and `boids-rgba-ecosystem`).
   - ACES tone mapping on display `writeTexture` only; raw simulation state in `dataTextureA`.
   - Fixed the 2 baseline dead sliders in `boids-rgba-ecosystem` (`u.zoom_params.z` `diffusion`, `u.zoom_params.w` `toxinStrength`).

## Verification Summary
- `wgsl_precommit_gate.py`: 10/10 PASS
- `audit:dead-sliders`: 0 new, 0 baseline on batch (PASS)
- `audit:extrabuffer`: 0 new violations (PASS)
- `verify:shader-definitions`: 1411 valid (PASS)
- `verify:wgsl-include`: PASS
