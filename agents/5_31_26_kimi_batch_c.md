# 2026-05-31 — Kimi Batch C Execution Plan (Second Unclaimed Track)

**Date**: 2026-05-31  
**Agent**: Kimi Code CLI (Batch C — follow-up to Batch B)  
**Focus**: Expand 12 small-but-promising unclaimed shaders (67–91 lines) to 110–150 lines with advanced techniques, meaningful alpha, and audio/depth integration.  
**Mode**: Local `kimi-cli --no-stream` only  
**Constraint**: ZERO overlap with Kimi Batch A, Batch B, Claude, Grok, or Copilot shader lists.

---

## Exclusion List (DO NOT TOUCH)

**Kimi Batch A (8)**: `gen-superfluid-quantum-foam`, `plasma`, `kaleido-scope-grokcf1`, `velocity-field-paint`, `pixel-sand`, `temporal-rgb-smear`, `liquid-tensor-vortex`, `depth-chromatic-bloom`

**Claude (7)**: `aurora-rift-pass1`, `aurora-rift-pass2`, `quantum-foam-pass1`, `tensor-flow-sculpting`, `hyperbolic-dreamweaver`, `gen-chronos-labyrinth`, `volumetric-god-rays`

**Grok (6)**: `ambient-liquid-coupled`, `alpha-reaction-diffusion-rgba`, `alpha-multi-state-ecosystem`, `gen-abyssal-chrono-coral`, `gen-auroral-ferrofluid-monolith`, `alucinate-hdr`

**Copilot (10)**: `_hash_library`, `adaptive-mosaic`, `aero-chromatics`, `aerogel-smoke`, `analog-film-degrade`, `anamorphic-flare`, `artistic_painterly_oil`, `ascii-flow`, `alpha-hdr-bloom-chain`, `ambient-liquid`

**Kimi Batch B (8)**: `luma-melt-interactive`, `concentric-spin`, `polka-wave`, `neon-pulse-stream`, `pixel-stretch-interactive`, `vhs-tracking-mouse`, `cyber-lattice`, `spectral-brush`

---

## Batch C — 12 Shaders (All Unclaimed)

| # | Shader ID | Category | Current Lines | Upgrade Theme | Target Lines |
|---|-----------|----------|---------------|---------------|--------------|
| C1 | `pixel-reveal` | interactive-mouse | 67 | Chromatic pixelation + depth-aware block size + audio-driven pixel jitter | 120 |
| C2 | `fluid-grid` | distortion | 70 | Curl-noise flow field + audio turbulence + divergence-free advection | 125 |
| C3 | `signal-modulation` | visual-effects | 74 | AM/FM chromatic aberration + spectral band visualization + noise floor | 130 |
| C4 | `velvet-vortex` | interactive-mouse | 76 | Velvet SDF spiral + depth parallax vortex + audio arm count modulation | 125 |
| C5 | `magnetic-ring` | interactive-mouse | 78 | Magnetic field line orbits + audio-reactive polarity flip + particle trails | 130 |
| C6 | `reactive-glass-grid` | interactive-mouse | 78 | Caustic refraction through glass tiles + chromatic dispersion + Fresnel | 135 |
| C7 | `liquid-warp-interactive` | distortion | 82 | Proper fluid sim approximation + depth viscosity + temporal feedback | 130 |
| C8 | `kinetic-dispersion` | unknown | 82 | Velocity-based curl dispersion + audio shockwave + block scattering RGB | 125 |
| C9 | `sonar-pulse` | unknown | 87 | Multi-ring chromatic sonar echo + depth attenuation + interference beats | 130 |
| C10 | `hypnotic-spiral` | unknown | 87 | SDF spiral geometry + audio arm count + depth twist + hue cycling | 125 |
| C11 | `fractal-noise-dissolve` | image | 89 | Domain-warped FBM dissolve + audio-driven threshold + edge glow | 120 |
| C12 | `neon-topology` | unknown | 91 | 3D topographic neon lines + audio elevation + depth atmospheric haze | 135 |

---

## Success Criteria

- All 12 shaders expanded from 67–91 lines to 110–150 lines.
- ≥ 10 of 12 use at least 2 of the 12 graphical tactics.
- ≥ 10 of 12 have meaningful alpha.
- ≥ 8 of 12 integrate depth meaningfully.
- All 12 have clean Standard Hybrid Headers.
- Zero overlap with the 39 shaders claimed by other agents.

---

**Session Log:** (fill during/after run)

## Session Log (completed 2026-05-31)

**Shaders completed:** 12/12  
**Validation:** `generate_shader_lists.js` ✅ | `check_duplicates.js` ✅  
**Biggest surprise:** `reactive-glass-grid` caustics + Fresnel combination created a genuinely physical glass aesthetic that surpassed expectations.  
**Patterns to codify:**
1. Depth→viscosity mapping is now proven in 3 shaders (luma-melt, liquid-warp, kinetic-dispersion) — standardize the curve.
2. Chromatic dispersion per RGB channel is a reliable upgrade pattern for any distortion shader.
3. `curl2D` + `fbm` pair should be extracted as a reusable snippet for all fluid/flow effects.

**Output artifacts:**
- 12 upgraded `.wgsl` files in `public/shaders/`
- 12 updated `.json` definitions in `shader_definitions/`
- 12 `.notes.kimi.md` files in `swarm-outputs/kimi-notes/`

**Ready for Claude polish pass:** Yes — especially `fluid-grid` and `liquid-warp-interactive` (curl2D performance), `neon-topology` (haze curve tuning).
