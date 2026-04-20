# Phase C: Advanced Compute Techniques — Mouse-Responsive Swarm

**Phase Timeline:** Weeks 9-12 (post Phase B)
**Total New Shaders:** 14 (all mouse-interactive, mostly multi-pass)
**Goal:** Introduce compute-shader techniques that are currently **absent or under-utilized** in the library — FFT, Jump-Flood, full pressure-projection fluids, complex-number fields, Hough accumulators, Gabor wavelet banks, DLA aggregation, bilateral/anisotropic convolutions, marching-squares metaballs, and an HDR Mean-Shift painter. Every shader is driven by the mouse and designed for beauty, psychedelia, and artistic expression.

---

## Why Phase C

Phase A and Phase B built out a strong foundation of reaction-diffusion, Lagrangian particles, raymarched SDFs, flow fields, and multi-pass feedback. Phase C fills the remaining gaps identified in the `SHADER_AUDIT.md` / binding-compatibility reports:

- **Frequency-domain effects** (2D FFT, Gabor wavelets) — currently *zero* implementations.
- **Jump-Flood Voronoi / distance fields** — currently zero (Voronoi shaders brute-force all seeds).
- **True incompressible fluids** (pressure projection via Jacobi iteration) — current fluid shaders advect only.
- **Atomic voting** (Hough transform, HDR histogram equalization) — template exists but no production shader.
- **Complex-valued fields** (Schrödinger, phase maps) — never stored in `rgba32float`.
- **Multi-pass convolution** (separable bilateral, Perona-Malik, Canny cascade) — single-pass Sobel is the extent today.
- **Marching squares / iso-line extraction** — no shader produces contour geometry.
- **Diffusion-Limited Aggregation** — missing from the generative catalog.

All new shaders follow the existing **immutable 13-binding contract** (see `swarm-technical-reference.md`), reuse `u.zoom_config.yz` for mouse, and lean into `rgba32float` packing strategies documented in each agent file.
# Phase C: Advanced Compute Shader Artistry — Swarm Launch

**Phase Timeline:** Weeks 9-14  
**Total New Shaders:** ~60 (15 convolution + 15 mouse-interactive + 15 spectral/computation + 15 alpha artistry)  
**Goal:** Push WebGPU compute to its visual and computational limits with novel techniques not yet in the library

---

## Vision

Phase C is about **techniques that don't exist yet** in the Pixelocity library. Where Phases A and B upgraded existing shaders and created hybrids from known patterns, Phase C introduces:

- **Convolution methods never before implemented** (bilateral, morphological, Gabor, non-local means, guided filtering)
- **Mouse-responsive shaders with physically-inspired interaction models** (fluid coupling, electromagnetic fields, gravity lensing, quantum tunneling)
- **Novel WGSL computation patterns** (subgroup operations, cooperative matrix math, stochastic sampling, spectral rendering)
- **RGBA32FLOAT as a creative medium** — not just "add alpha" but use the full 128-bit-per-pixel pipeline as 4 independent high-dynamic-range data channels for effects impossible in 8-bit pipelines

---

## Quick Start

```bash
# Navigate to Phase C tasks
cd projects/image_video_effects/swarm-tasks/phase-c

# View agent tasks
cat agent-1c-spectral-domain.md
cat agent-2c-distance-fields.md
cat agent-3c-true-fluids.md
cat agent-4c-convolution-art.md
cat agent-5c-atomic-feedback.md
```

---

## Agent Task Summary

| Agent | Role | Shaders | Duration | Primary Techniques |
|-------|------|---------|----------|--------------------|
| **1C** | Spectral-Domain Architect  | 2 | 4-5 days | 2D FFT (Cooley-Tukey butterfly), Gabor wavelet bank |
| **2C** | Distance-Field Sculptor    | 3 | 5-6 days | Jump-Flood (JFA), Eikonal fast-sweeping, SDF CSG + raymarch |
| **3C** | True-Fluid Engineer        | 2 | 4-5 days | Jacobi pressure projection, vorticity confinement |
| **4C** | Convolution-Art Alchemist  | 3 | 4-5 days | Separable cross-bilateral, Perona-Malik anisotropic, workgroup mean-shift |
| **5C** | Atomic-Feedback Conjurer   | 4 | 5-6 days | Hough voting, DLA, marching-squares metaballs, Schrödinger complex field |

**Total:** 14 shaders, ~24 days sequential / ~6 days parallel with 5 agents.

---

## RGBA32FLOAT Packing Strategies Introduced

Phase C formalizes six new packing schemes that the existing shaders do not use. Each agent spec cites the scheme it depends on:

| Scheme | Layout (`.r, .g, .b, .a`) | Used by |
|--------|---------------------------|---------|
| **Complex field**   | `(Re, Im, prev_Re, prev_Im)` | 1C Spectral Mirror, 5C Schrödinger |
| **JFA seed**        | `(seed_x, seed_y, dist², seed_id)` | 2C Aurora Voronoi |
| **SDF + gradient**  | `(sdf, ∂x, ∂y, material_id)` | 2C Field Sculptor, 2C Lantern |
| **Stable-fluid**    | `(vx, vy, divergence, pressure)` | 3C Stable Fluid Painter |
| **Vorticity field** | `(vx, vy, ω, density)` | 3C Vorticity Smoke |
| **Hough bin**       | `(vote_count, θ, ρ, age)` | 5C Hough Cathedral |
| **Histogram bin**   | `(bin_0, bin_1, bin_2, bin_3)` atomically updated | 4C Mean-Shift Painter |

These keep every pass within the standard 13-binding contract (no new buffer types).

---

## Mouse Interaction Vocabulary

Phase C introduces richer mouse semantics, all decoded from the existing `Uniforms`:

| Gesture | Decoded From | New Meaning |
|---------|--------------|-------------|
| **Position**      | `u.zoom_config.yz` | Seed / source / cursor |
| **Press**         | `u.zoom_config.w`  | Inject / add / stamp |
| **Velocity**      | `u.ripples[last].xy` minus `u.ripples[last-1].xy` over dt | Momentum splats for fluids |
| **Ripple history**| `u.ripples[0..49]` | Wave sources, DLA seed history, Hough regions of interest |
| **Drag distance** | integrated from ripples | Brush length for Gabor, bilateral radius |
| **Click count**   | `u.config.y` | Mode switch (material ID, species index) |

---

## Output Locations

| Agent | Output | Location |
|-------|--------|----------|
| 1C | WGSL (multi-pass)         | `public/shaders/*-pass*.wgsl` |
| 1C | JSON definitions          | `shader_definitions/interactive-mouse/*.json` |
| 2C | WGSL + JSONs              | `public/shaders/*.wgsl` + `shader_definitions/interactive-mouse/` |
| 3C | WGSL + JSONs              | `public/shaders/*.wgsl` + `shader_definitions/simulation/` |
| 4C | WGSL + JSONs              | `public/shaders/*.wgsl` + `shader_definitions/artistic/` |
| 5C | WGSL + JSONs              | `public/shaders/*.wgsl` + `shader_definitions/advanced-hybrid/` |

---

## Execution Order

### Wave 1 (Days 1-6): Foundation & Proof-of-Concept
Launch in parallel:
- **Agent 1C:** Start with `spectral-mirror` (validates FFT butterfly in `extraBuffer`).
- **Agent 2C:** Start with `jfa-aurora-voronoi` (validates JFA with power-of-two step schedule).
- **Agent 3C:** Start with `stable-fluid-painter` (validates 20-iteration Jacobi).

### Wave 2 (Days 6-12): Fill Out
- **Agent 1C:** `gabor-wavelet-kaleidoscope`.
- **Agent 2C:** `sdf-field-sculptor`, `eikonal-lantern`.
- **Agent 3C:** `vorticity-smoke`.
- **Agent 4C:** All three convolution shaders (can run fully parallel, no cross-deps).

### Wave 3 (Days 12-18): Hybrids
- **Agent 5C:** `hough-cathedral`, `dla-crystal-garden`, `metaball-lava-lamp`, `schrodinger-conductor`.

### Wave 4 (Days 18-22): QA
Hand off to Phase B's Agent 5B pipeline for validation (`naga-scan-report.json`, param audit, bindgroup compatibility).

---

## Success Metrics

- [ ] 14 new mouse-responsive shaders produced.
- [ ] Each uses at least one compute technique not present in Phase A/B.
- [ ] All shaders respect the 13-binding contract (verified by `bindgroup_checker.py`).
- [ ] Each shader documents its RGBA32FLOAT packing in a WGSL header comment.
- [ ] Each has 4 user params wired to `u.zoom_params.xyzw` with sane 0-1 ranges.
- [ ] No shader exceeds 65 ms/frame at 1920×1080 on a mid-tier GPU (RTX 3060 reference).
- [ ] Multi-pass shaders (FFT, JFA, fluid, Canny) include a chain-order comment in every pass.

---

## Gate Criteria for Completion

Phase C complete when:
1. All 5 agents close out their shader lists.
2. `naga-scan-report.json` reports zero new validation errors.
3. `bindgroup_compatibility_report.json` shows all Phase C shaders compatible with the shared bind group.
4. `param_validation_report.json` confirms every new shader has 4 params.
5. Phase C shaders integrated into the shader-browser UI (update `shader_definitions/*/index.json` if needed).

---

## Related Reading

- `/home/user/image_video_effects/PLAN-ADVANCED-EFFECTS.md` — Section VI indexes Phase C.
- `/home/user/image_video_effects/swarm-technical-reference.md` — binding contract.
- `/home/user/image_video_effects/SHADER_COORDINATE_SYSTEM.md` — UV / pixel conventions.
- `/home/user/image_video_effects/swarm-tasks/phase-b/README.md` — preceding phase.
