# Sonnet batch 15 — fractal-set ten — NOTES (2026-11-01)

Cards: `BRIEFS.md` (written before any WGSL edit). Review: `COORDINATOR_REVIEW.md`.

**No GPU in this sandbox.** Checks are structural plus numeric experiments on SwiftShader. Nothing here claims an effect "looks right";
real-GPU visual QA is external and still required.

Comment labels: `2026-11 Idea n` (n = card number) wherever HEAD already used `Idea n` comments; plain `Idea n` elsewhere.

## Corrections to my own notes

- The BRIEFS first claimed `gen-mandelbox-explorer` declared `var dr` twice. **That was wrong**: an artifact of overlapping `sed` ranges when I printed the file (line 40 printed twice). The file declares it once; the card and finding are struck in BRIEFS. No change was made to that function.
- Likewise the duplicated `hash2` lines I saw in `gen_grok41_mandelbrot` were a printing artifact.

## Deviations from the cards

1. **gen_mandelbulb_3d thresholds were recalibrated** after a SwiftShader measurement (4085 hit pixels, default camera). The Mandelbulb DE is a Lipschitz bound, not an exact distance, so its Laplacian is biased positive: percentiles 2/10/50/90/98 = −841 / −27 / 35 / 98 / 142. My first constants (ridge 6..30) would have lit most of the surface and the 5-tap AO (`1 − 3·occ`) darkened everything ~25 % (occ median 0.084). Final constants: ridge 55..130, crevice 60, AO `1 − (occ − 0.075)·7` clamped 0.35..1 (`RIDGE_LAP_*`, `CREVICE_LAP`, `AO_*` in the file).
2. **gen_julia_set lace width** recalibrated: with `exp(−de·0.35)` over 10 % of pixels exceeded 0.8 (a flood); now `exp(−de·1.2)` with weight 0.35. Still ~10 % of pixels above 0.5 at c ≈ the default animated value, because that Julia set is dust-like and its boundary is dense; on a GPU look at it with the Exponent slider across its range.
3. Card for `multi-fractal-compositor` kept as written (staggered octave composite + zoom dispersion); the JSON description and features were rewritten because the old ones (Mandelbrot/Julia/Burning Ship/Newton blend) describe nothing in the code.

## Pre-existing findings (flagged)

- `multi-fractal-compositor` is not a fractal shader (same template as `particle_dreams_alpha`). Identity kept; a real fractal compositor would be a new shader.
- `gen_grok41_mandelbrot`: also keep in mind the sample loop is expensive (up to 40 MC samples × 64-iteration orbits per pixel); only the cardioid/bulb skip was added.
- `kimi_fractal_dreams` renders near-white at default sliders in my harness (display mean ≈ 0.86 at HEAD, 0.88 after); not a regression, flagged for a GPU look at the default colour balance.
- Tone curves kept as the look: `gen_mandelbulb_3d` (Reinhard-style), `gen-mandelbox-explorer` (Hable-style "acesToneMap").

## Per shader

### gen-julia-set (gen_julia_set.wgsl)
- **Kept verbatim:** 4 params; cpow orbit; smooth μ; traps incl. trap-mode interpolation; velocity trap; filament accumulator; 2-sample AA; chromatic mix; A raw HDR, ACES on writeTexture.
- **A packing:** unchanged.
- **Ideas:** `2026-11 Idea 1: DE filaments` (`logDz`, `deNorm`, `lace`); `2026-11 Idea 2: interior multiplier banding` (`multiplier`, `fatouBands`).
- **Formula:** derivative distance estimate (Julia); not a §12.2 table row.

### gen-mandelbox-explorer
- **Kept verbatim:** everything in HEAD; **A packing:** unchanged display RGBA.
- **Ideas:** `Idea 1: metallic environment reflection` (`reflDir`, `envCol`, Schlick `fresnel`); `Idea 2: fold-wall orbit trap` (`wallMin`, `wallLattice`).
- **Formula rows:** §12.2F Fresnel–Schlick; §12.2E orbit trap (different trap than HEAD's).

### gen_mandelbulb_3d
- **Kept verbatim:** DE, march, orbit-trap colour, soft shadow, fog, glow, Reinhard-style curve, vignette; A = final display colour.
- **Ideas:** `Idea 1: DE ambient occlusion` (`bulbAO`); `Idea 2: curvature edge wear` (`bulbCurvature`, `ridge`, `crevice`, `wear`).
- **Repair (required):** `mouse` defined; `hitAlpha` hoisted; exact `textureLoad` of C. Leaves the naga known-failures list.
- **Formula rows:** §12.2E step-count AO; §12.2E SDF curvature.

### spec-quaternion-julia
- **Kept verbatim:** quaternion algebra/DE, camera, palette, glow, dither, A raw HDR.
- **Ideas:** `Idea 1: hyperplane slice drift` (`w0`, DE signature gains `w0`); `Idea 2: DE cone soft shadow` (`shadow` loop).
- **Floor:** bounds guard added.

### hyperbolic-dreamweaver-julia
- **Kept verbatim:** Julia DE, hyperbolic helpers, disk mask, mouse orbit, albedo mix, horocycle fog, A = ACES display.
- **Ideas:** `Idea 1: hyperboloid-perspective rays` (`hypScale`); `Idea 2: Snell refraction + Cauchy split` (`rfR/G/B`, `photoR/G/B`).
- **Formula row:** §12.2F Snell + Cauchy.

### gen-audio-spirograph-julia
- **Kept verbatim:** ratios/harmonics, curve families, filaments, screen Julia overlay, C trail blend, ACES; A = col·0.95 + alpha.
- **Ideas:** `Idea 1: pen-driven Julia constant` (`ringC`); `Idea 2: ink tail` (`tailP2..4`, `tailStroke`, `inkTail`).

### gen-grok41-mandelbrot (gen_grok41_mandelbrot.wgsl)
- **Kept verbatim:** MC sampler, rainbow, comet, body, antenna, stars, spring state in extraBuffer[133..136], linear accumulation in A (ACES display only).
- **Ideas:** `Idea 1: Nebulabrot channels` (`nebula`); `Idea 2: smooth potential + binary-decomposition rays` (`muEsc`, `rayParity`; bailout 256).
- **Repairs (live controls):** Center X/Y sliders now drive the spring goal (`goalBase`). **Verified:** with the slider moved mid-run, HEAD output is identical for 0.2 and 0.8, the new output follows it (display mean 0.423 vs 0.358). Click pull uses real seconds and no padding `ripple.w`. Star bands via `fftBand()` (`extraBuffer[5+4k]`). Exact perf skip for cardioid/bulb.
- **Formula row:** §12.2E smooth iteration count.

### kimi-fractal-dreams (kimi_fractal_dreams.wgsl)
- **Kept verbatim:** params and second roles, spring c, layers, trap palette, filaments, creases, lake, A = ACES display.
- **Ideas:** `Idea 1: fold-parity checker` (`foldCount`, `foldParity`); `Idea 2: stripe-average colouring` (`stripeAcc`, `stripe`).
- **Repair:** per-layer treble bins read `extraBuffer[5+bin]` (was `plasmaBuffer[1+layer]`, always 0).
- **Formula row:** §12.2E fold count as material.

### multi-fractal-compositor
- **Kept verbatim:** 4 param ids/names/defaults; layer loop; layer speed mix(x, y); click vortex; fog (w); volumetric alpha; edge glow; no A/C.
- **Ideas:** `2026-11 Idea 1: staggered octave composite` (`layerPhase`, `layerZoom = 2^(2.32·phase)`, `layerWindow`, `ghostAcc` → `layered`); `Idea 2: zoom dispersion` (`uvTapR/B`).
- **Repair / floor:** slider z live (flow-warp amplitude `warpAmp`); bounds guard; `extraBuffer[0]` bass-as-UV-offset → `plasmaBuffer[0].x · 0.05`; ACES on display; JSON description + features rewritten to match.

### gen-3d-sierpinski-chaos
- **Kept verbatim:** all six HEAD ideas, die, projection, temporal accumulation; A = ACES display RGBA.
- **Ideas:** `Idea 1: IFS address colouring` (`prevPick`, `addressHue`); `Idea 2: perspective splat radius` (`perspScale`, `radiusEff`).

## Formula rows (batch)

| row / mechanism | files |
|---|---|
| E step-count AO / SDF curvature | gen_mandelbulb_3d (one file, two rows) |
| E orbit trap (fold walls) | gen-mandelbox-explorer |
| E smooth iteration count | gen-grok41-mandelbrot |
| E fold count as material | kimi-fractal-dreams |
| F Fresnel–Schlick | gen-mandelbox-explorer |
| F Snell + Cauchy | hyperbolic-dreamweaver-julia |
| derivative distance estimate | gen-julia-set |
| none | spec-quaternion-julia, gen-audio-spirograph-julia, multi-fractal-compositor, gen-3d-sierpinski-chaos |

## Gates

- naga-wasm (30.0): 10/10 valid; Tint (Chrome's compiler) via SwiftShader `createComputePipelineAsync`: 10/10.
- `wgsl_precommit_gate.py --skip-naga --files …`: 10/10, 0 pasted headers, 0 extraBuffer violations. `audit:extrabuffer`: 0 new. `audit:dead-sliders -- --files …`: 0 new.
- **SwiftShader execution harness** (throwaway, not committed): all 13 bindings, A→C ping-pong, moving mouse, held press, click ripples, synthetic image/depth, non-zero FFT bins. 10/10 ran: **0 NaN/Inf in display or A, no GPU validation errors**; frames: 6 (bulb, 48 px) to 60 (96 px). Numeric sanity only.
- Saved `params` and `x-meta` byte-identical to HEAD in all ten JSONs.
- `generate_shader_lists.js`, `npm run test:ci`, `npm run build`: see PR.
