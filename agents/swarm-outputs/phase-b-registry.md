# Phase B Agent Swarm Registry

**Status:** ✅ COMPLETE  
**Started:** 2026-06-28  
**Completed:** 2026-06-28 19:08 UTC  
**Goal:** Fix all broken complex shaders, refactor multi-pass pipelines, and produce advanced hybrid assets.

---

## Discovery Summary

- **Total WGSL shaders:** 1,262 (`public/shaders/*.wgsl`)
- **Total `naga` failures:** 29 shaders fail `naga 29.0.3` validation
- **Failures by size:**
  - 26 failures in 8–20KB complex-shader range
  - 3 failures below 8KB
- **Multi-pass shader families:** 8 families (26 individual pass files)
  - `rd-on-video` (3 passes)
  - `sim-fluid-feedback-field` (3 passes)
  - `quantum-foam` (3 passes)
  - `aurora-rift` + `aurora-rift-2` (2+2 passes)
  - `vortex` (2 passes)
  - `spectrogram-displace` (2 passes)
  - `liquid-optimized` (2 passes)
  - `liquid` (2 passes)
  - `digital-glitch` (2 passes)
- **Shaders with non-standard `@workgroup_size(8, 8, 1)`:** 77+ (pre-existing; Phase A fixed the smallest ones)

**Conclusion:** Phase B is focused on the highest-impact technical-debt items:
1. Fix all 29 `naga`-failing shaders (syntax/type/swizzle/keyword errors).
2. Refactor the largest multi-pass shader families for consistency and performance.
3. Create 2–3 advanced hybrid shaders.
4. Performance optimization pass on the largest shaders.

---

## Standards Checklist (apply to every upgraded shader)

- [ ] Fix the `naga` validation error(s) first.
- [ ] Keep the **13-binding canonical header** unchanged (binding numbers/types/order).
- [ ] Keep `struct Uniforms` layout unchanged (`config`, `zoom_config`, `zoom_params`, `ripples[50]`).
- [ ] Default `@workgroup_size(16, 16, 1)` where feasible; leave 8×8 only if algorithm requires it.
- [ ] Preserve incoming alpha for image/video effects; only set `alpha = 1.0` for pure generative backgrounds.
- [ ] Write both `writeTexture` (RGBA) and `writeDepthTexture` (R-only).
- [ ] Clamp/normalize zoom_params before use: `let x = mix(lo, hi, clamp(u.zoom_params.X, 0.0, 1.0));`
- [ ] Avoid swizzle assignment (`p.xy = ...`); assign components individually.
- [ ] Cast `global_id.xy` / `gid.xy` to `vec2<f32>` before mixing with float vectors.
- [ ] Avoid WGSL reserved keywords (`active`, `array`, `atomic`, etc.) as variable names.
- [ ] Validate with `naga <file> /tmp/out.wgsl` after each edit.

---

## Agent Assignments

### Agent 1b — Complex Shader Upgrade Specialist ✅
**Target:** Fix all 29 `naga`-failing shaders. Split into batches by error type and size.

**Batch 1 — Type-mismatch / swizzle / keyword errors (smaller/earlier in list):**
1. `public/shaders/dynamic-halftone.wgsl`
2. `public/shaders/data-slicer.wgsl`
3. `public/shaders/cyber-scan.wgsl`
4. `public/shaders/mouse-pixel-sort.wgsl`
5. `public/shaders/hex-lens.wgsl`
6. `public/shaders/soft-vignette-bloom.wgsl`
7. `public/shaders/gen-live-studio-tab.wgsl`
8. `public/shaders/gen-sonic-lava-flow.wgsl`

**Batch 2 — Swizzle-assignment generative shaders (set A):**
1. `public/shaders/gen-ethereal-cyber-aurora-hummingbird-core.wgsl`
2. `public/shaders/gen-radiant-quantum-plasma-kraken-core.wgsl`
3. `public/shaders/gen-hyper-bismuth-clockwork.wgsl`
4. `public/shaders/gen-quantum-aether-origami.wgsl`
5. `public/shaders/gen-cryogenic-frost-plasma-matrix.wgsl`
6. `public/shaders/gen-cymatic-quantum-silk-loom.wgsl`
7. `public/shaders/gen-quantum-singularity-forge.wgsl`
8. `public/shaders/gen-symbiotic-plasma-reef-matrix.wgsl`

**Batch 3 — Swizzle-assignment generative shaders (set B) + syntax errors:**
1. `public/shaders/gen-ethereal-quantum-hologram-bonsai.wgsl`
2. `public/shaders/gen-magnetic-ferrofluid-sculpture.wgsl`
3. `public/shaders/gen-chromatic-glass-lattice.wgsl`
4. `public/shaders/gen-hyper-dimensional-bismuth-matrix.wgsl`
5. `public/shaders/gen-resonant-crystal-canyons.wgsl`
6. `public/shaders/gen-tectonic-plasma-crucible.wgsl`
7. `public/shaders/gen-ethereal-glass-flora-terrarium.wgsl`
8. `public/shaders/gen-chronos-monolith-resonator.wgsl`

**Batch 4 — Type-mismatch / complex generative shaders:**
1. `public/shaders/gen-cosmic-web-filament.wgsl`
2. `public/shaders/gen-neuro-fluid-plasma-lotus.wgsl`
3. `public/shaders/gen-prismatic-quantum-fractal-nautilus-engine.wgsl`
4. `public/shaders/gen-prismatic-cyber-chrono-void-kitsune.wgsl`
5. `public/shaders/gen-resonant-quantum-plasma-dragon-eye.wgsl`

### Agent 2b — Multi-Pass Pipeline Architect ✅
**Target:** Refactor the 3 largest multi-pass shader families for consistency, performance, and correct dataTexture usage.

Families:
1. `rd-on-video` (3 passes)
2. `sim-fluid-feedback-field` (3 passes)
3. `quantum-foam` (3 passes)

For each family:
- Ensure all passes share the same canonical header and Uniforms layout.
- Verify `readTexture`/`dataTextureC` inter-pass reads are wired correctly.
- Ensure pass outputs write to the correct `writeTexture` / `dataTextureA` / `dataTextureB` slots.
- Add/update header comments describing the pass graph.
- Validate every pass with `naga`.

### Agent 3b — Performance Optimizer ✅
**Target:** Optimize 5 of the largest shaders for performance without changing visuals.

Candidates (largest non-failing shaders):
1. `public/shaders/gen-chronos-labyrinth.wgsl`
2. `public/shaders/gen-chromatic-metamorphosis.wgsl`
3. `public/shaders/gen-gravitational-strain.wgsl`
4. `public/shaders/spectral-bleed-confinement.wgsl`
5. `public/shaders/tensor-flow-sculpt.wgsl`

Focus areas:
- Reduce FBM/octave counts where overdriven.
- Hoist loop-invariant calculations.
- Replace expensive `pow`/`exp` chains with approximations.
- Add early exits for off-screen/zero-contribution pixels.
- Use 16×16 workgroups consistently.

### Agent 4b — Advanced Hybrid Shader Creator ✅
**Target:** Create 2 advanced hybrid shaders that combine multiple complex techniques.

Create:
1. `public/shaders/hyb-neural-voronoi-feedback.wgsl` — Voronoi + feedback-field distortion over input image
2. `public/shaders/hyb-spectral-fbm-displace.wgsl` — FBM-driven spectral displacement over input image

### Agent 5b — QA & Integration ✅
**Target:** Aggregate all changes, run `naga` on every touched shader, run `node scripts/generate_shader_lists.js`, and update this registry.

---

## Success Criteria

- All 29 `naga`-failing shaders pass validation after fixes.
- The 3 multi-pass families are internally consistent and validated.
- 5 large shaders receive measurable performance optimizations (validated by naga).
- 2 new advanced hybrid shaders compile and have JSON definitions.
- Shader lists regenerate successfully.

---

## QA Results — Agent 5b Final Verification

**Performed:** 2026-06-28 19:08 UTC  
**Tool:** `naga 29.0.3` (`naga <file> /tmp/out.wgsl`)

### Step 1 — Originally Failing Shaders
| Metric | Count |
|---|---|
| Total re-verified | 29 |
| Passed | 29 |
| Failed | 0 |

All 29 originally `naga`-failing shaders now pass validation.

### Step 2 — Multi-Pass Refactored Shaders
| Family | Passes | Status |
|---|---|---|
| `rd-on-video` | pass1, pass2, pass3 | ✅ 3/3 pass |
| `sim-fluid-feedback-field` | pass1, pass2, pass3 | ✅ 3/3 pass |
| `quantum-foam` | pass1, pass2, pass3 | ✅ 3/3 pass |

### Step 3 — Optimized Shaders
- `gen-chronos-labyrinth.wgsl` ✅
- `gen-chromatic-metamorphosis.wgsl` ✅
- `gen-gravitational-strain.wgsl` ✅
- `spectral-bleed-confinement.wgsl` ✅
- `tensor-flow-sculpt.wgsl` ✅

### Step 4 — New Advanced Hybrid Assets
- `public/shaders/hyb-neural-voronoi-feedback.wgsl` ✅ (naga pass)
- `public/shaders/hyb-spectral-fbm-displace.wgsl` ✅ (naga pass)
- `shader_definitions/hybrid/hyb-neural-voronoi-feedback.json` ✅ (exists)
- `shader_definitions/hybrid/hyb-spectral-fbm-displace.json` ✅ (exists)

### Step 5 — Shader List Regeneration
`node scripts/generate_shader_lists.js` completed successfully.
- 14 category JSON files generated.
- 1 pre-existing warning (out of scope for Phase B): `gen-showcase-nebula-core` reports unexpected `workgroup_size`.

### Remaining Issues
- None blocking Phase B completion.
- Pre-existing warning on `gen-showcase-nebula-core` workgroup size is unrelated to Phase B targets.

### Conclusion
All success criteria met. Phase B is **✅ COMPLETE**.
