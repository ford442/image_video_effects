# 2026-05-31 — Kimi Batch B Execution Plan (Unclaimed Shader Upgrade Track)

**Date**: 2026-05-31  
**Agent**: Kimi Code CLI (Batch B — follow-up to primary v2 pilot)  
**Focus**: Expand 8 small-but-promising unclaimed shaders (70–86 lines) to 120–150 lines with advanced techniques, meaningful alpha, and audio/depth integration.  
**Mode**: Local `kimi-cli --no-stream` only  
**Constraint**: ZERO overlap with Kimi Batch A, Claude, Grok, or Copilot shader lists.

---

## Exclusion List (DO NOT TOUCH)

**Kimi Batch A (8 shaders)**: `gen-superfluid-quantum-foam`, `plasma`, `kaleido-scope-grokcf1`, `velocity-field-paint`, `pixel-sand`, `temporal-rgb-smear`, `liquid-tensor-vortex`, `depth-chromatic-bloom`

**Claude (7 shaders)**: `aurora-rift-pass1`, `aurora-rift-pass2`, `quantum-foam-pass1`, `tensor-flow-sculpting`, `hyperbolic-dreamweaver`, `gen-chronos-labyrinth`, `volumetric-god-rays`

**Grok (6 shaders)**: `ambient-liquid-coupled`, `alpha-reaction-diffusion-rgba`, `alpha-multi-state-ecosystem`, `gen-abyssal-chrono-coral`, `gen-auroral-ferrofluid-monolith`, `alucinate-hdr`

**Copilot (10 shaders)**: `_hash_library`, `adaptive-mosaic`, `aero-chromatics`, `aerogel-smoke`, `analog-film-degrade`, `anamorphic-flare`, `artistic_painterly_oil`, `ascii-flow`, `alpha-hdr-bloom-chain`, `ambient-liquid`

---

## Batch B — 8 Shaders (All Unclaimed)

| # | Shader ID | Category | Current Lines | Upgrade Theme | Target Lines | Primary Role |
|---|-----------|----------|---------------|---------------|--------------|--------------|
| B1 | `luma-melt-interactive` | liquid-effects | 70 | Curl-noise flow field + depth-aware viscosity + temporal feedback trails | 130 | Algorithmist → Interactivist |
| B2 | `concentric-spin` | image | 74 | Chromatic ring dispersion + audio-orbital count + depth parallax zoom | 125 | Visualist → Algorithmist |
| B3 | `polka-wave` | image | 76 | CMYK halftone separation + mouse ripple expansion + bass dot inflation | 130 | Visualist → Interactivist |
| B4 | `neon-pulse-stream` | image | 78 | 3D tube lighting model + fluid advection + treble sparkle injection | 135 | Visualist → Algorithmist |
| B5 | `pixel-stretch-interactive` | image | 78 | Chromatic directional stretch + audio-reactive stretch length + depth intensity | 125 | Interactivist → Visualist |
| B6 | `vhs-tracking-mouse` | interactive-mouse | 81 | Full VHS suite: tracking noise, chroma bleed, horizontal hold, scanline dropouts | 140 | Interactivist → Visualist |
| B7 | `cyber-lattice` | image | 81 | Holographic interference fringes + 3D perspective grid + audio lattice warp | 130 | Algorithmist → Visualist |
| B8 | `spectral-brush` | image | 86 | Temporal spectral painting + hue-preserve clamp + ACES tone map + bass bloom | 135 | Visualist → Optimizer |

**Why these 8?**
- All are **small** (70–86 lines) with proven JSON definitions and existing WGSL skeletons.
- All are **unclaimed** by any of the 4 primary agents today.
- They span **5 categories** (liquid-effects, image, interactive-mouse) for good library coverage.
- Most already have `mouse-driven` and/or `audio-reactive` flags — we are **elevating** existing features, not adding from scratch.
- Every single one can absorb **2+ of the 12 Kimi Graphical Tactics** without changing its soul.

---

## Upgrade Direction per Shader

### B1 — `luma-melt-interactive`
**Current**: Simple vertical luma-driven melt with mouse heat + bass speed.  
**Upgrade**: Make the melt a true 2D curl-noise flow field. Depth controls viscosity (foreground melts slower). Mouse leaves persistent heat trails in `dataTextureA` that decay over time. Bass increases turbulence; mids increase melt speed.

**Tactics to inject**: `warpedFBM`, `curl2D`, `bass_env`, `premultiplied writeback`

**Differentiate from**: `liquid-lens` (spherical refraction) — this is flow, not lensing.

---

### B2 — `concentric-spin`
**Current**: Concentric rings rotate in alternating directions. Mouse = center. Audio = rotation speed.  
**Upgrade**: Each ring gets chromatic dispersion (RGB channels orbit at slightly different radii). Audio bass adds new rings; treble compresses ring spacing. Depth shifts ring center via parallax.

**Tactics to inject**: `kaleido`, `bass_env`, `hue_preserve_clamp`, `anti-moiré LOD`

**Differentiate from**: `astral-kaleidoscope` — no symmetry folding, pure orbital chromatics.

---

### B3 — `polka-wave`
**Current**: Halftone dots sized by image brightness + mouse ripples.  
**Upgrade**: True CMYK halftone separation (4 dot grids at different angles). Mouse creates expanding ripple that temporarily inverts dot polarity. Bass inflates all dots; treble adds micro-dot noise.

**Tactics to inject**: `bass_env`, `IGN dither`, `anti-moiré LOD`, `aa_step`

**Differentiate from**: `dynamic-halftone` — this is print-native CMYK with interactive ripple.

---

### B4 — `neon-pulse-stream`
**Current**: Video luminance drives neon trails; mouse injects flow.  
**Upgrade**: Trails become 3D tubes with proper Fresnel rim lighting. Fluid advection uses curl noise for divergence-free flow. Treble injects sparkle particles along high-luminance paths.

**Tactics to inject**: `curl2D`, `warpedFBM`, `bass_env`, `premultiplied writeback`

**Differentiate from**: `neon-strings` — this is fluid advection, not string physics.

---

### B5 — `pixel-stretch-interactive`
**Current**: Slit-scan stretch from mouse to screen edge.  
**Upgrade**: Chromatic stretch (R/G/B stretch at different intensities). Audio bass elongates stretch length. Depth makes background stretch more than foreground.

**Tactics to inject**: `depth-aware fog`, `bass_env`, `hue_preserve_clamp`

**Differentiate from**: `temporal-rgb-smear` (Kimi A — do not touch) — this is spatial, not temporal.

---

### B6 — `vhs-tracking-mouse`
**Current**: Single tracking bar with RGB split and noise.  
**Upgrade**: Full VHS degradation suite — tracking bar, chroma bleed, horizontal hold wobble, scanline dropouts, tape hiss noise (IGN dither), and occasional "tracking loss" white flash on treble spikes.

**Tactics to inject**: `IGN dither`, `bass_env`, `hue_preserve_clamp`, `aa_step`

**Differentiate from**: `analog-film-degrade` (Copilot today) — this is tape/deck degradation, not film grain.

---

### B7 — `cyber-lattice`
**Current**: 2D holographic grid reacting to mouse.  
**Upgrade**: 3D perspective grid with vanishing point. Holographic interference fringes (thin-film colors). Audio bass warps grid lines like a wind field. Mouse click spawns a lattice disruption pulse.

**Tactics to inject**: `warpedFBM`, `bass_env`, `hue_preserve_clamp`, `ACES`

**Differentiate from**: `cyber-lattice-bilateral` (unclaimed but larger) — this is the tighter, interactive version.

---

### B8 — `spectral-brush`
**Current**: Mouse paints spectral colors; bass affects brush size. Temporal via `dataTextureC`.  
**Upgrade**: Spectral colors use physical blackbody radiation curve. Temporal feedback uses `hue_preserve_clamp` + ACES tone mapping. Bass creates bloom around brush strokes. Depth makes background strokes more diffuse.

**Tactics to inject**: `hue_preserve_clamp`, `ACES`, `IGN dither`, `bass_env`, `depth-aware fog`

**Differentiate from**: `digital-mold` — this is spectral/blackbody painting, not organic growth.

---

## Execution Protocol (v2 — Same as Batch A)

For each shader:

1. **Read current `.wgsl`** from `public/shaders/`
2. **Read current `.json`** from `shader_definitions/<category>/`
3. **Feed Kimi** the exact prompt template from `KIMI_CLI_SWARM_UPGRADE_PLAN.md` v2 with:
   - Creative brief (from above)
   - Differentiation block
   - Output contract (×3)
   - Immutable 13-binding contract
   - Current source
   - Role toolkit excerpt
   - 12 Kimi Graphical Tactics
   - Line budget (target ±15%)
4. **Run guard** (manual or `scripts/kimi-output-guard.js` if available):
   - Exactly one ` ```wgsl ` block, zero bytes after closing fence
   - All 13 bindings present
   - Standard Hybrid Header present
   - At least 2 tactics used
   - No naive `vec4(..., 1.0)` final write
5. **On pass**: Write WGSL, write `swarm-outputs/kimi-notes/<shader-id>.notes.kimi.md`
6. **On fail**: Move to `swarm-outputs/kimi-rejects/`

---

## Output Locations

- Upgraded WGSL → `public/shaders/` (hot-swap overwrite)
- JSON updates (if any) → `shader_definitions/<category>/`
- Kimi notes → `swarm-outputs/kimi-notes/<shader-id>.notes.kimi.md`
- Rejects → `swarm-outputs/kimi-rejects/`

---

## Post-Batch Validation

```bash
node scripts/generate_shader_lists.js
node scripts/check_duplicates.js
```

---

## Success Criteria

- All 8 shaders expanded from 70–86 lines to 120–150 lines.
- ≥ 6 of 8 use at least 2 of the 12 graphical tactics.
- ≥ 6 of 8 have meaningful alpha (not `vec4(rgb, 1.0)`).
- ≥ 6 of 8 integrate depth (`readDepthTexture`) in a visually meaningful way.
- All 8 have clean Standard Hybrid Headers with proper `Chunks From` attribution.
- Zero overlap with the 31 shaders claimed by other agents today.

---

**This is Batch B: the unclaimed reserve force. While the primary agents handle their flagship shaders, we sweep through the promising small effects and turn them into library standouts.**

— Kimi (Batch B Swarm Operator), 2026-05-31

---

## Session Log (fill during/after run)

**Shaders completed:**
**Guard pass rate:**
**Biggest surprise:**
**Patterns to codify:**

---

## Session Log (completed 2026-05-31)

**Shaders completed:** 8/8  
**Guard pass rate:** 100% (manual review — all 8 passed on first write)  
**Biggest surprise:** The `polka-wave` CMYK halftone with polarity inversion landed even better than expected — the Risograph aesthetic is genuinely distinct from every other halftone in the library.  
**Patterns to codify:**
1. `curl2D` + `fbm` pair is reusable across liquid/fluid shaders — consider extracting to a shared snippet.
2. Blackbody radiation curve (`blackbody` function) should become a standard tactic for any "heat" or "spectral" shader.
3. The "depth controls intensity/viscosity/stretch" pattern works in 6 of 8 shaders — it should be a default consideration for all image-space effects.

**Validation:** `generate_shader_lists.js` and `check_duplicates.js` both passed cleanly.

**Output artifacts:**
- 8 upgraded `.wgsl` files in `public/shaders/`
- 8 updated `.json` definitions in `shader_definitions/`
- 8 `.notes.kimi.md` files in `swarm-outputs/kimi-notes/`

**Ready for Claude polish pass:** Yes — especially `luma-melt-interactive` (curl2D performance) and `spectral-brush` (ACES desaturation check).
