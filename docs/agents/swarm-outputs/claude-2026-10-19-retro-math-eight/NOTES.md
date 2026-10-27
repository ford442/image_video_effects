# Claude retro-math-eight — Notes

2026-10-19. Eight shaders across retro-glitch, image, artistic, visual-effects, distortion and
interactive-mouse. Prelude migration (tile-twist only) ran first via `scripts/migrate_to_prelude.py`
and is header-only, in its own commit. Saved `params` are byte-exact in every JSON; no JSON was
edited.

| Shader | Kept verbatim | A packing | Ideas in the diff |
|---|---|---|---|
| digital-glitch | 4 params, spring, ripples, block shifts/tears, per-channel corruption loop + op set, propagateError, bit-depth + posterize chain, RGB split, inversion, scanlines, vignette, ACES | (errorMask, luma, intensity, alpha), unchanged | Idea 1 `nbMask`/`infection` (4 exact C taps 3 px away, frontier-only); Idea 2 `refreshPeriod`/`rowPhase`/`rowAge` → `applyDigitalDecay(…, age, …)` + `refreshLine` (also bounds HEAD's `time·decayRate`, which went permanently 1-bit after ~15 s); Idea 3 `busGroup`/`busStuck`/`busBit`/`busHigh` stuck bus lines |
| phosphor-decay | 4 params, decay constants, OkLab merge, burn-in, crackle/dust, vblank, click bloom, haze, blackbody, display chain | HDR phosphor RGB + burn-in, unchanged | Idea 4 `kHyp`/`hypDecay` hyperbolic afterglow; Idea 5 `ringLight` 8-tap C ring, display-only (after the A write) |
| vhs-chroma-bleed | 4 params + slot use, Ideas 1–3, bleed/jitter/tracking chain, post chain, ACES | display RGB + source alpha, unchanged | Idea 4 `headZone`/`headSkew` folded into `trackingOffset` + head line noise after grain; Idea 5 `yLeft`/`yRight` luma peaking on `ownYcc.x` |
| crt-tv | 4 params, spring, Ideas 1–3, curve, tube mask, horizontal split strength, beam, grille, halation, decay, vignette, glare, ACES | HDR phosphor RGB, unchanged | Idea 4 `misconverged()` (radial r² term, replaces `chromaticAberration`, same horizontal split); Idea 5 `apl`/`breath`/`breatheUV()` on `crtUV` and `nextUV` |
| poincare-tile | 4 params, Möbius chain, sector reduction, texUV, ripples, boundary, Ideas 1–2, ACES | display RGBA, unchanged | Idea 3 `parity`/`wMirror` reflection parity; Idea 4 `hypD`/`ringD`/`ring` equidistant rings |
| anaglyph-3d | 4 params, synthEye search, focal depth, Ideas 1–3, ghost, post chain, C persistence, ACES | display RGBA, unchanged | Idea 4 `leftRGB`/`rightRGB`/`duboisRGB` 50% Dubois (also reuses those fetches for crosstalk luma, −2 samples); Idea 5 `PARALLAX_BUDGET`·`tanh` in synthEye |
| complex-exponent-warp | 4 params, complex_pow, Ideas 1–3, overlays, fog, ACES | display RGBA, unchanged | Idea 4 `argLine`/`modLine`/`gridLine` + `gridFade`; Idea 5 `result_zR`/`final_uvR`/`dispRc` folded into `ca` |
| tile-twist | 4 params, grid/jitter/angle formula, warp, ridge, quilt, moiré, CA, hue rotate, sparkle | (bass env, trail RGB), unchanged | Idea 1 `plateRot`/`plateP`/`plateD`/`grout`/`bevel`/`rake`; Idea 2 `lissPrev`/`dAngle`/`arcA`/`arcB`/`arcW` (angle split into `lissajousAngle + angleRest`, same sum) |

## Deviations from the cards

- complex-exponent-warp Idea 5: only red gets its own exponent w·(1+δ); blue keeps HEAD's
  −0.7·ca tap, which now mirrors the red dispersion. One extra `complex_pow` instead of two.
- tile-twist Idea 1: plate half-size 0.5 with corner radius 0.06, so at rest only small corner grout
  shows; the grout opens as tiles twist.

## §12.2 formula use

| Shader | Rows |
|---|---|
| digital-glitch | none (§12.1 t6 history spread; t2 refresh; t5 stuck bus) |
| phosphor-decay | Halation (A, as a faceplate ring); rest §12.1 t2 |
| vhs-chroma-bleed | none verbatim (§12.1 t5 head switching; t1/t5 peaking) |
| crt-tv | none verbatim (§12.1 t5 misconvergence; t2 EHT breathing) |
| poincare-tile | none (§12.1 t5 reflection group; t3 metric) |
| anaglyph-3d | none (§12.1 t1 Dubois; t2 depth budget) |
| complex-exponent-warp | none (§12.1 t3 conformal grid; t1 per-channel exponent) |
| tile-twist | none (§12.1 t5 plate; t2 arc blur) |

No §12.2 row is used on more than one file.

## Closeout

- Floor: prelude include / 16×16 / exact C loads / A packing as documented / saved params exact.
- Gates: Naga 8/8 via `wgsl_precommit_gate.py`, `audit:extrabuffer` pass, `audit:dead-sliders` 0 new,
  `generate_shader_lists.js`, vitest, `SKIP_WASM_BUILD=1 npm run build`, `verify:toolchain-foundation`.
- Real-GPU visual QA: external. digital-glitch (refresh cycle replaces the unbounded decay) and
  tile-twist (grout) change the most.
