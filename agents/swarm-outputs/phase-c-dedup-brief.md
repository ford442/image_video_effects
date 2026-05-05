# Phase C Deduplication Brief

**Generated:** 2026-04-18
**Purpose:** Prevent Phase C agents from duplicating existing Phase A/B shaders
**Existing shader count:** 724 unique WGSL files

---

## How to Use This Document

Each Phase C agent must read this file before creating shaders. If a planned shader name or concept matches an entry in the **SKIP** or **RENAME** tables below, follow the resolution action.

---

## SKIP List — Do Not Create These (Exact Concept Already Exists)

| Phase C Planned Name | Existing Shader | Reason |
|----------------------|-----------------|--------|
| `mouse-gravity-lensing` | `gravity-lens` | Gravitational lensing already implemented |
| `mouse-quantum-tunnel-probe` | `quantum-tunnel-interactive` | Quantum tunneling already implemented |
| `alpha-magnetic-field-sim` | `magnetic-field`, `hybrid-magnetic-field`, `gen-magnetic-field-lines` | Magnetic field simulation already exists in 3 forms |
| `alpha-navier-stokes-paint` | `navier-stokes-dye` | Navier-Stokes fluid sim already exists |
| `alpha-glass-refraction-layers` | `glass_refraction_alpha` | Glass refraction with alpha already exists |

**Action for agents:** Do not create these shaders. Choose an alternative from your backup idea list or invent a new variant that is visually distinct.

---

## RENAME List — Create With These New Names

| Phase C Planned Name | Existing Shader | Conflict Type | Approved New Name |
|----------------------|-----------------|---------------|-------------------|
| `alpha-cellular-automata-state` | `cellular-automata-3d` | Near-name + concept overlap | `alpha-multi-state-ecosystem` |
| `mouse-voronoi-shatter-interactive` | `voronoi-shatter` | Near-name | `mouse-voronoi-mosaic` |
| `mouse-wormhole-portal` | `quantum-wormhole` | Near-concept | `mouse-wormhole-lens` |

**Action for agents:** Use the "Approved New Name" for the WGSL file, JSON ID, and shader name field.

---

## KEEP List — Safe to Create (Different Enough)

| Phase C Planned Name | Existing Similar Shader | Why It's Safe |
|----------------------|------------------------|---------------|
| `conv-anisotropic-diffusion` | `anisotropic-kuwahara` | Kuwahara is a filter; diffusion is an iterative PDE. Completely different algorithms. |
| `mouse-mandelbrot-zoom-portal` | `gen-inverse-mandelbrot`, `gen_grok41_mandelbrot` | Existing are generative (no input). Phase C version is mouse-interactive with zoom portals on input image. |
| `mouse-julia-morph` | `gen-julia-set`, `julia-warp` | Existing are generative/static. Phase C version is mouse-driven real-time morphing. |
| `mouse-hyperbolic-navigator` | `gen-hyperbolic-tessellation`, `hyperbolic-dreamweaver` | Existing use hyperbolic math for pattern generation. Phase C version is Poincaré disk navigation of the input image. |
| `conv-reaction-convolution` | `gen-reaction-diffusion`, `chromatic-reaction-diffusion` | Existing are standalone simulations. Phase C version applies R-D as a convolution filter on the input image. |
| `alpha-reaction-diffusion-rgba` | `gen-reaction-diffusion`, `chromatic-reaction-diffusion` | Existing are 2-species. Phase C version is 4-species packed into RGBA with cross-inhibition. |
| `alpha-aurora-bands` | `aurora-rift*`, `aurora_borealis` | Existing are raymarched volumetric aurora. Phase C version is emission-line spectral simulation with altitude layers. |
| `conv-bilateral-dream` | *(none)* | Bilateral filter does not exist in the library. Safe. |
| `conv-morphological-erosion-dilation` | *(none)* | Morphological operators do not exist. Safe. |
| `conv-gabor-texture-analyzer` | *(none)* | Gabor filters do not exist. Safe. |
| `conv-non-local-means` | *(none)* | NLM does not exist. Safe. |
| `conv-guided-filter-depth` | *(none)* | Guided filter does not exist. Safe. |
| `mouse-electromagnetic-aurora` | *(none)* | EM field mouse interaction does not exist. Safe. |
| `mouse-fluid-coupling` | *(none)* | Viscous fluid coupling to mouse does not exist. Safe. |
| `mouse-chromatic-explosion` | *(none)* | Prism-based per-channel displacement does not exist. Safe. |
| `spec-prismatic-dispersion` | `gen-prismatic-bismuth-lattice`, `gen-prismatic-fractal-dunes` | Existing use "prismatic" as a visual description. Phase C version is physically-based spectral dispersion with Cauchy's equation. Distinct technique. |
| `spec-iridescence-engine` | *(none)* | Thin-film interference does not exist. Safe. |
| `spec-blackbody-thermal` | *(none)* | Blackbody radiation mapping does not exist. Safe. |
| `spec-temporal-path-tracer` | *(none)* | 2D path tracing with temporal accumulation does not exist. Safe. |
| `spec-quaternion-julia` | *(none)* | Quaternion Julia sets do not exist. Safe. |

---

## Existing Shader ID Master List (Excerpt)

The full library contains 724 shaders. Key categories:
- `image/`: ~405 shaders
- `generative/`: ~97 shaders
- `interactive-mouse/`: ~38 shaders
- `distortion/`: ~32 shaders
- `simulation/`: ~30 shaders
- `artistic/`: ~20 shaders
- `advanced-hybrid/`: ~10 shaders
- `hybrid/`: ~10 shaders

**Before creating any shader, verify the ID does not already exist by checking:**
```bash
ls public/shaders/YOUR_ID.wgsl
ls shader_definitions/*/YOUR_ID.json
```

---

## Naming Convention Rules for Phase C

1. **Agent 1C (Convolution):** Use `conv-` prefix (e.g., `conv-bilateral-dream`)
2. **Agent 2C (Mouse):** Use `mouse-` prefix (e.g., `mouse-electromagnetic-aurora`)
3. **Agent 3C (Spectral/Computation):** Use `spec-` prefix (e.g., `spec-prismatic-dispersion`)
4. **Agent 4C (Alpha Artistry):** Use `alpha-` prefix (e.g., `alpha-navier-stokes-paint`)
5. **Agent 5C (Crossover):** Use `hybrid-phase-c-` or `cross-` prefix

---

## Chunk Library Reference

Available reusable chunks: `swarm-outputs/chunk-library.md`
- hash12, hash22, valueNoise, fbm2, simplex noise
- Color utilities (hsv2rgb, rgb2hsv, tonemapping)
- SDF primitives
- UV transformations

Agents should attribute borrowed chunks per AGENTS.md conventions.

---

*Brief generated for Phase C swarm launch*
