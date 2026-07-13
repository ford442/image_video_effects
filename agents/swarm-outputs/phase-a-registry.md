# Phase A Agent Swarm Registry

**Status:** ✅ COMPLETE  
**Started:** 2026-06-28  
**QA Completed:** 2026-06-28  
**Goal:** Finish remaining small-shader standardization work and produce new generative/hybrid assets.

---

## Discovery Summary

- **Total WGSL shaders at start:** 1,256 (`public/shaders/*.wgsl`)
- **Total JSON definitions at start:** 1,169 (`shader_definitions/**/*.json`)
- **Tiny tier (<2KB):** 0 (already upgraded)
- **Small tier (2-3KB):** 2
- **Smallest shaders (3-4.5KB):** ~20
- **Chunk library at start:** exists at `agents/swarm-outputs/chunk-library.md` (48 functions; now 57 after Phase A)
- **Validation tool:** `naga` 29.0.3 available; all 20 smallest shaders currently pass `naga` syntax validation

**Conclusion:** Original Phase A target of 61 tiny/small shaders is largely complete. Phase A is therefore pivoted to:
1. Standardize the ~20 remaining smallest shaders (alpha handling, headers, binding names, randomization safety).
2. Produce new generative shader pilots.
3. Create hybrid shaders from the chunk library.
4. Run randomization-safety validation.

---

## Standards Checklist (apply to every upgraded shader)

- [ ] Keep the **13-binding canonical header** unchanged (binding numbers/types/order).
- [ ] Keep `struct Uniforms` layout unchanged (`config`, `zoom_config`, `zoom_params`, `ripples[50]`).
- [ ] Default `@workgroup_size(16, 16, 1)`.
- [ ] Preserve incoming alpha for image/video effects; only set `alpha = 1.0` for pure generative backgrounds.
- [ ] Write both `writeTexture` (RGBA) and `writeDepthTexture` (R-only).
- [ ] Use `textureSampleLevel(..., 0.0)` consistently.
- [ ] Clamp/normalize zoom_params before use: `let x = mix(lo, hi, clamp(u.zoom_params.X, 0.0, 1.0));`
- [ ] Avoid variable-exponent `pow` and division/log by raw params; add epsilon guards.
- [ ] Add/update header comment with category and features.
- [ ] Validate with `naga <file> /tmp/out.wgsl`.
- [ ] If JSON definition exists, keep it in sync (no new files required for standardization-only work).

---

## Agent Assignments

### Agent 1a — Alpha Channel Specialist ✅ COMPLETE
**Target:** 20 smallest shaders, split into two batches.

**Batch 1 (first 10):**
1. `public/shaders/rd-on-video-pass3.wgsl`
2. `public/shaders/_template_canonical_compute.wgsl`
3. `public/shaders/rd-on-video-pass2.wgsl`
4. `public/shaders/rd-on-video-pass1.wgsl`
5. `public/shaders/interactive-voronoi-lens.wgsl`
6. `public/shaders/pixel-sort-explorer.wgsl`
7. `public/shaders/hex-mosaic.wgsl`
8. `public/shaders/ring_slicer.wgsl`
9. `public/shaders/luma-slice-interactive.wgsl`
10. `public/shaders/spectral-smear.wgsl`

**Batch 2 (next 10):**
1. `public/shaders/sim-fluid-feedback-field-pass2.wgsl`
2. `public/shaders/quantum-prism.wgsl`
3. `public/shaders/pixel-sort-radial.wgsl`
4. `public/shaders/luma-echo-warp.wgsl`
5. `public/shaders/kimi_spotlight.wgsl`
6. `public/shaders/mouse-ink-bleed.wgsl`
7. `public/shaders/motion-heatmap.wgsl`
8. `public/shaders/chronos-brush.wgsl`
9. `public/shaders/pixel-focus.wgsl`
10. `public/shaders/spectrogram-displace-pass2.wgsl`

### Agent 4a — Generative Shader Creator ✅ COMPLETE
**Target:** Create 3 new generative shaders in `public/shaders/` and matching JSON definitions in `shader_definitions/generative/`.

Candidate concepts (pick or invent):
- `gen-neural-dust.wgsl` — drifting luminous particles via FBM + glow
- `gen-holographic-fracture.wgsl` — iridescent cracked SDF planes
- `gen-bioelectric-pulse.wgsl` — reaction-diffusion-like organic pulses

### Agent 2a — Shader Surgeon / Chunk Librarian ✅ COMPLETE
**Target 1:** Refresh `agents/swarm-outputs/chunk-library.md` by scanning the 20 smallest upgraded shaders for any new reusable chunks. Add them with source attribution and compatibility notes.  
**Target 2:** Create 3 new hybrid shaders in `public/shaders/` and matching JSON definitions in `shader_definitions/hybrid/`.

Created hybrid shaders:
- `hyb-hex-voronoi-distort.wgsl` — hex grid + Voronoi distortion over input image
- `hyb-iridescent-fbm-glow.wgsl` — FBM + iridescence glow blended over input image
- `hyb-kaleidoscope-pulse.wgsl` — kaleidoscope + radial pulse over input image

### Agent 3a — Parameter Randomization Engineer ✅ COMPLETE
**Target:** Audit the same 20 smallest shaders for randomization safety. Produce a report at `agents/swarm-outputs/phase-a-randomization-report.md` listing any division-by-zero, log-of-negative/zero, pow-with-variable-exponent, sqrt-negative, or acos/asin-out-of-range risks, plus recommended fixes.

### Agent 5a — QA & Integration ✅ COMPLETE
**Target:** Aggregate all changes, run `naga` on every touched shader, run `node scripts/generate_shader_lists.js` to regenerate manifests, and update this registry with completion status.

---

## Success Criteria

- ✅ All 20 smallest shaders pass `naga` validation after changes.
- ✅ No shader has `alpha = 1.0` unless it is a pure generative background.
- ✅ 3 new generative shaders compile and have JSON definitions.
- ✅ 3 new hybrid shaders compile and have JSON definitions.
- ✅ Chunk library updated with newly extracted chunks (48 → 57 functions).
- ✅ Randomization report produced with zero unresolved critical issues.
- ✅ Shader lists regenerated successfully.


---

## QA Results — Agent 5a

**Run date:** 2026-06-28

### Naga Validation (`naga <file> /tmp/naga-out.wgsl`)
- **Passed:** 26 / 26
- **Failed:** 0

All 20 upgraded small shaders + 3 new generative shaders + 3 new hybrid shaders pass naga 29.0.3 syntax validation.

### Shader List Regeneration
- **Command:** `node scripts/generate_shader_lists.js`
- **Status:** ✅ SUCCESS (exit code 0)
- **Output:** 14 manifest files regenerated.
- **Note:** One pre-existing warning for `gen-showcase-nebula-core` (unexpected `@workgroup_size(8, 8)`); this shader was not touched by Phase A agents.

### New JSON Definition Validity
| File | Status |
|------|--------|
| `shader_definitions/generative/gen-neural-dust.json` | ✅ VALID |
| `shader_definitions/generative/gen-holographic-fracture.json` | ✅ VALID |
| `shader_definitions/generative/gen-bioelectric-pulse.json` | ✅ VALID |
| `shader_definitions/hybrid/hyb-hex-voronoi-distort.json` | ✅ VALID |
| `shader_definitions/hybrid/hyb-iridescent-fbm-glow.json` | ✅ VALID |
| `shader_definitions/hybrid/hyb-kaleidoscope-pulse.json` | ✅ VALID |

### New Generative WGSL Spot-Check
| Shader | Canonical Header | Uniforms Struct | @workgroup_size(16,16,1) | alpha=1.0 | Depth Write | No Texture Reads |
|--------|------------------|-----------------|--------------------------|-----------|-------------|------------------|
| `gen-neural-dust.wgsl` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `gen-holographic-fracture.wgsl` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `gen-bioelectric-pulse.wgsl` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### New Hybrid WGSL Spot-Check
| Shader | Canonical Header | Uniforms Struct | @workgroup_size(16,16,1) | Reads Input | Preserves Alpha | Depth Write |
|--------|------------------|-----------------|--------------------------|-------------|-----------------|-------------|
| `hyb-hex-voronoi-distort.wgsl` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `hyb-iridescent-fbm-glow.wgsl` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `hyb-kaleidoscope-pulse.wgsl` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### Unresolved Issues
None. The two division-by-zero risks identified in the original randomization audit were resolved by Agent 1a's clamp-normalization pass and are confirmed fixed in the current shader files.

### Agent Completion Summary
- Agent 1a (Alpha Channel Specialist): ✅ COMPLETE — 20 small shaders standardized and validated.
- Agent 4a (Generative Shader Creator): ✅ COMPLETE — 3 new generative shaders + JSON definitions.
- Agent 2a (Shader Surgeon / Chunk Librarian): ✅ COMPLETE — chunk library refreshed (9 new chunks added; function count 48 → 57) + 3 new hybrid shaders + JSON definitions.
- Agent 3a (Parameter Randomization Engineer): ✅ COMPLETE — randomization report produced and updated with resolved status.
- Agent 5a (QA & Integration): ✅ COMPLETE — naga 26/26 passed, shader lists regenerated, JSON valid.
