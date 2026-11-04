# Sonnet batch 17 — kaleidoscope and prism ten — NOTES (2026-11-01)

Cards: `BRIEFS.md` (written before any WGSL edit). Review: `COORDINATOR_REVIEW.md`.

**No GPU in this sandbox.** Checks are structural plus numeric experiments on SwiftShader. Nothing here claims an effect "looks right";
real-GPU visual QA is external and still required.

Comment labels: `2026-11 Idea n` / `Idea n (2026-11)` where HEAD already used numbered ideas (prismatic-mosaic, prism-displacement continue HEAD's 1–3 as 4–5); plain `Idea n` elsewhere.

## Deviations from the cards

1. **astral-kaleidoscope-morph: no `mouse-driven` any more.** The card did not say it, but HEAD's mouse reads were accidental (its mis-ordered struct made `zoom_params.*` the mouse). After the repair nothing reads the pointer, so `mouse-driven` was removed from the JSON features.
2. **Alpha clamp added to astral / gemini / grokcf1** (not on the cards): `alpha = mix(0.7, 1.0, luma)` extrapolates when the unbounded feedback pushes luma above 1; measured HEAD alpha max 1.13 (gemini) / 1.12 (grokcf1). Floor fix, `clamp(…, 0, 1)`.
3. spec-prismatic white balance, measured: card said (2.30, 0.74, 0.59) pre-ACES at default sliders (computed). A flat-white input through HEAD vs new on SwiftShader gives display channel means R/G 1.19 → 1.05 (B/G 0.97 → 0.99). The residual is the absorption tint (kept on purpose) and the other additive terms (sheen, glow).

## Pre-existing findings (flagged, not changed)

- **astral-kaleidoscope-gemini/grokcf1 feedback veil:** `max(color, prev·decay + shimmer)` settles at shimmer/(1−decay); measured on SwiftShader: history mean ≈ 0.99 (HEAD, 90 frames, default trails) with values up to 1.66. It is how the trail looks (a milky veil), so I left it; a human may want shimmer scaled by (1−decay).
- `astral-kaleidoscope-julia`: `morphSpeed`, `colorCycles`, `detail` still read mouse x / mouse y / mouse-down (bounded, left); only the unbounded time read was repaired.
- `liquid-prism`: the Aberration slider also sets `baseTransparency` (double role, HEAD).
- Remaining `struct-field-order` shaders in the prelude tracker: 4 (this batch removed one). `check_prelude_migration.py` fails with 17 stale `pending` entries on clean `main`; none of this batch's ids.

## Per shader

### astral-kaleidoscope
- **Kept verbatim:** 4 params; fold; parallax; chroma; HSL grade; trails; HEAD centre/seam glint/click overlay; A = pre-ACES feedback + 1.0.
- **A packing:** unchanged (read as C colour via exact `textureLoad`).
- **Ideas:** `2026-11 Idea 1` (`wedgeK`, `bounces`, `pow(rho, bounces)`); `2026-11 Idea 2` (`capR`, `rCap`, `capWeight`).
- **Repair/floor:** `round()` on the segment count (default 9 unchanged); exact C load; alpha clamp.

### astral-kaleidoscope-gemini
- **Kept verbatim:** HEAD warp swell, pointer epicentre, shimmer.
- **Ideas:** `Idea 1` eyepiece (`eyeFall`, `eyeStop`, display-only, f = 1.1); `Idea 2` defocus (`defocusR`, four taps).
- **Repair/floor:** integer segments; exact C load; alpha clamp.

### astral-kaleidoscope-grokcf1
- **Kept verbatim:** HEAD torque, grab, warp, shimmer.
- **Ideas:** `Idea 1` second chamber (`foldAngle`, `chamberAngle`, screen blend); `Idea 2` log-spiral (`logSpiral`).
- **Repair/floor:** integer segments; exact C load; alpha clamp.

### astral-kaleidoscope-julia
- **Kept verbatim:** 4 params; fold; DE; marching; mouse orbit; background chroma; A raw colour + alpha.
- **Ideas:** `Idea 1` photo reflection (`reflRay`, `schlick`, `envPhoto`); `Idea 2` mirror gap (`seamDist`, `seamGap`, `seamBevel`).
- **Repair:** zoom from engine time → 2.75; integer segments.
- **Formula row:** §12.2F Fresnel–Schlick.

### astral-kaleidoscope-morph
- **Kept verbatim:** fold; chroma; HSL grade; disc erosion/dilation/gradient/top-hat; trails; top-hat alpha; the four saved slider roles.
- **Ideas:** `Idea 1` radial line SE (`radialDirM`, `lineMax`); `Idea 2` gradient chroma (`caShift`, `caR/caB`).
- **Repair (own change):** hand migration (renamed bindings, swapped struct); sliders read from `zoom_params` in their saved roles; four non-slider reads → midpoints (1.0 / 0.01 / 0.075 / 0.75); exact C load; ACES on display (HEAD wrote linear to the display); removed from the prelude tracker's `struct-field-order` pending list.
- **A packing:** feedback colour + luma in A (pre-ACES), display ACES.

### kaleidoscope (rose)
- **Kept verbatim:** HEAD in full (spring pivot, rose, FBM, epicycloid, squircle, Gabor, hypocycloid, shockwaves, persistence, ACES).
- **Ideas:** `2026-11 Idea 1` diffraction fringes (`superellipseValue`, `fringeCol`); `2026-11 Idea 2` Cauchy split (R 0.57 / B 1.0).
- **Repair:** even integer segments (default 4.8 → 4); real FFT bins (`fftBand`).
- **Formula rows:** §12.2F diffraction/Airy-style fringes; §12.2F Cauchy weighting.

### prismatic-mosaic
- **Kept verbatim:** HEAD in full.
- **Ideas:** `Idea 4` facet glints (`facetN`, `facetSpec`); `Idea 5` Cauchy tile split (0.57 / 1.0).

### prism-displacement
- **Kept verbatim:** HEAD in full.
- **Ideas:** `Idea 4` Beer–Lambert (`glassTransmit`); `Idea 5` radial CA (`radialCA`; `lensR` moved up).
- **Formula row:** §12.2F Beer–Lambert.

### liquid-prism
- **Kept verbatim:** HEAD in full.
- **Ideas:** `2026-11 Idea 1` Jacobian caustic focusing (`jacDet`, `focusGain`); `2026-11 Idea 2` TIR (`critCos`, `tirWeight`).
- **Repair:** real FFT bin for the per-distance band.
- **Formula row:** §12.2F Snell / critical angle.

### spec-prismatic-dispersion
- **Kept verbatim:** HEAD in full.
- **Ideas:** `Idea 1` white-balanced reconstruction (`whiteResponse`); `Idea 2` AR-tinted ghost (`ghostUV`, `ghostTint`).

## Formula rows (batch)

| row / mechanism | files |
|---|---|
| F Cauchy weighting | kaleidoscope, prismatic-mosaic |
| F Fresnel–Schlick | astral-kaleidoscope-julia |
| F Beer–Lambert | prism-displacement |
| F Snell / critical angle | liquid-prism |
| F diffraction fringes | kaleidoscope |
| A cos⁴ vignetting | astral-kaleidoscope-gemini |
| none (tactic-derived) | astral-kaleidoscope, grokcf1, morph, spec-prismatic-dispersion |

## Gates

- naga-wasm (30.0): 10/10 valid; Tint (Chrome's compiler) via SwiftShader `createComputePipelineAsync`: 10/10.
- `wgsl_precommit_gate.py --skip-naga --files …`: 10/10, 0 pasted headers, 0 extraBuffer violations. `audit:extrabuffer`: 0 new. `audit:dead-sliders -- --files …`: 0 new.
- **SwiftShader execution harness** (throwaway, not committed): all 13 bindings, A→C ping-pong, moving mouse, held press, click ripples, synthetic image/depth, non-zero FFT bins; 90 frames at 128 px (10 at 64 px for the raymarched Julia). 10/10 ran: **0 NaN/Inf in display or A, no GPU validation errors.** Also: white-input comparison for spec-prismatic (above). Numeric sanity only.
- Saved `params` and `x-meta` byte-identical to HEAD in all ten JSONs.
- `generate_shader_lists.js`, `npm run test:ci`, `npm run build`: see PR.
