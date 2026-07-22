# holographic-crystal — Optimizer Notes (2026-07-22, batch b11)

**Role:** Optimizer
**Files touched:**
- `public/shaders/holographic-crystal.wgsl` (148 → 219 lines, **+71**)
- `shader_definitions/generative/holographic-crystal.json` (added `updatedParams` + `"updated": true` only)
- `swarm-outputs/kimi-generative-2026-07-22-b11/holographic-crystal.notes.kimi.md` (this file)

## Key changes

- **Per-pixel hash phase dither (anti-moire):** added canonical `hash21` dither
  (`DITHER_AMP = 0.9` rad) injected into `holoPhase` and the moire sine args to
  kill residual banding/aliasing on high-frequency interference fringes,
  on top of the existing LOD-based `moireAttenuate`.
- **Worley facet-normal perturbation:** added canonical `hash22`-based 3×3
  Worley F1 field (`WORLEY_FREQ = 2.6`, slowly time-drifting). Two decorrelated
  taps form a per-facet pseudo-normal; dot with a light direction yields
  `facetShade` (0.55–1.45 multiplier) so facets catch light unevenly like cut
  glass. Applied to both the holographic RGB and the interior sheen.
- **Treble facet glint:** razor-sharp sparkle highlights — `pow(edgeGlow, 12)`
  edge-proximity mask × `pow(twinkle, 24)` per-facet temporal twinkle, driven by
  `plasmaBuffer[0].z` (treble), tinted warm-white (`GLINT_GAIN = 1.35`). Glint
  also feeds `presence`/alpha and nudges depth so sparkles composite correctly.
- **Slider rewiring (same ids/defaults/mappings — preset contract preserved):**
  - `facets` (x) → facet ring density (unchanged, already meaningful).
  - `tilt` (y) → widened tilt-angle range (0.8 → 1.1 rad) AND reorients the
    worley catch-light direction (`lightAngle`), so the slider visibly
    relights the lattice, not just rotates it.
  - `interference` (z) → holographic edge-fringe amplitude (unchanged,
    already meaningful).
  - `dispersion` (w) → rewired to true chromatic phase spread: it now scales
    the R/G/B HOLO phase offsets (low = near-monochrome, high = full rainbow)
    in addition to its existing moire color weight.
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, writeTexture /
  writeDepthTexture / dataTextureA written every frame (incl. early-exit
  background branch), `textureSampleLevel(..., 0.0)` for the sampler read,
  no reserved keywords, no binding 13 (shader doesn't use a history ring).

## Line count delta

148 → 219 lines (**+71**, within the required +50…+90 window; target 198–238).

## Gate result

`python3 scripts/wgsl_precommit_gate.py --files public/shaders/holographic-crystal.wgsl`
→ **PASS** (exit 0): naga OK, bindgroup compatible, 0 warnings.

## QA flags

- All new constants (`DITHER_AMP`, `WORLEY_FREQ`, `GLINT_GAIN`, facetShade
  range, glint exponents 12/24, light-angle coefficients) are **eyeballed** —
  tuned by reasoning, not by rendered output.
- This VM has **no GPU adapter**, so visual QA (dither subtlety, worley
  shading balance, glint intensity/twinkle rate, dispersion spread feel) is
  **deferred** to a machine with WebGPU. Naga validation + gate pass only
  guarantee compile/binding correctness.
- `normalize(facetNormal + vec2<f32>(0.001))` guards the zero-length case;
  worst visual artifact if worley taps coincide is a flat-lit facet, no NaNs.
