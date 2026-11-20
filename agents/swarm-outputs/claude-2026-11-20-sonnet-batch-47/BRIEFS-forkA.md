# BRIEFS — fork A (interactive-rgb-split, chromatic-swirl) — written BEFORE any WGSL edit

Both second pass. HEAD = `git show origin/main:public/shaders/<id>.wgsl`. HEAD audit: no defects found in either
file (all four sliders read, audio from `plasmaBuffer[0]`, no C reads, no extraBuffer, no illegal stores, no
negative-into-ACES, `pow` bases clamped) → **no rescues**. One hygiene nit in rgb-split: depth is sampled twice at the
same `uv` (`depth` and `d`); the second is reused, zero pixel change.

Formula claims (no row shared between the two files): **rgb-split = Brown–Conrady radial (§12.2B)**;
**chromatic-swirl = Cauchy dispersion (§12.2F) + Rayleigh scatter (§12.2F / WOLFRAM_SHADER_DATA)**. rgb-split's second idea
is tactic 1 (kernel), not a table row.

---

## SHADER: interactive-rgb-split

IDENTITY: mouse-localised chromatic split of the photo — three colour channels sampled along ONE displacement field
(radial/longitudinal about the pointer or directional/lateral), ripples perturb the field; reads as a lens/prism fringe.

KEEP VERBATIM: 4 params + roles (strength → overall amplitude, falloff → pointer localisation smoothstep, mode → radial
below 0.5 / directional above, angle → split direction + spectral tint wavelength); `field = smoothOffset + rippleOffset
+ jitter`; existing Ideas (per-channel scales 1.15 / 0.70 / 1.35 along `splitAxis`, lateral-vs-longitudinal mix);
`splitMix`, `spectralTint`, depth blend, Schlick edge, vignette, ACES; A = display RGBA (unchanged); writeDepth passthrough.

MECHANISM INTERROGATION
- Tactic 1 (kernel): the split is a 3-point spectral quadrature — one monochromatic tap per channel. A real lens
  integrates each sensor channel over a ~100 nm band, which is why real fringes are continuous gradients between
  colours and not three discrete ghost images. Next-better approximation of the *same* operator: integrate each
  channel over its own band.
- Tactic 2 (physics one step further): radial mode is lateral chromatic aberration of a lens whose optical axis is the
  pointer. HEAD offset = `(uv − mouse)·amount`, linear in radius. Seidel third-order lateral colour grows with r³; the
  Brown–Conrady polynomial `r(1 + k1 r² + k2 r⁴)` is the real shape. Zero at the pointer, fast growth outward.
- Tactic 3 (promote an intermediate): `dist` (aspect-corrected radius to the pointer) is computed and only used for the
  falloff mask and the Schlick edge — it is exactly the BC `r`. `length(field)` (already computed for `splitMix`)
  becomes the smear half-width so the band vanishes wherever the split vanishes.
- Tactic 6 (history): HEAD owns no C history and is not a history effect → deliberately none.

ADD
1. **Brown–Conrady radial growth (§12.2B)** — in radial mode `smoothOffset *= 1 + k1·r² + k2·r⁴`, r = `dist`.
   Fringes stay ~0 under the pointer and grow superlinearly toward the periphery of the lens, like a real uncorrected
   lens. Directional mode (a prism, no optical axis) keeps its uniform shift. Strength is still the overall amplitude.
2. **Spectral band smear (tactic 1)** — each channel is integrated over its band: 3 taps at `s_c·(1 − b)`, `s_c`,
   `s_c·(1 + b)` with 1-2-1 weights. The channel centroid stays exactly HEAD's scale (1.15 / 0.70 / 1.35), so the split
   geometry is unchanged; the hard triple-ghost becomes a continuous gradient. Smear width ∝ `|field|`.

FORMULA ADMISSION: BC row is in the distortion family ("lens distortion with a real two-term shape; k1 from the
existing strength param") and this file *is* a lens CA — one sentence why; consumes `dist`/`smoothOffset` the file
already has; deleting it leaves the exact HEAD linear split; keeping only it is still an RGB split. Band smear: same
three taps' worth of kernel, consumes `splitAxis`; deleting it leaves HEAD; keeping only it is still the same split.

FORBID on this file: replacing 1.15/0.70/1.35 with Cauchy (that would erase the existing idea; Cauchy is on the
sibling file), springs, new ripple system, IQ palette, chroma-delay, any new param.

A PACKING: display RGBA (unchanged).

---

## SHADER: chromatic-swirl

IDENTITY: the photo twirled about the pointer with R/G/B at different swirl angles (angular chromatic) and
wavelength-dependent Beer–Lambert transmittance; telemetry in A.

KEEP VERBATIM: 4 params + roles (swirl_strength, radius, aberration — also the angular split, animate → continuous spin);
`angle = percent²·swirlStrength (+ spin, ×2 on mouse-down)`; `extraTwist`; `angR/G/B = base·(1 + 2.8a / 1 / 1 − 2.2a)`;
`calculateChannelAlpha` law and the 650/550/450 nm constants; `baseCol = rgb·alpha`; bass/treble warm-cool grade;
`swirlGlow`; depth; ACES; A = telemetry (dist/radius, angle/12, aberration, alpha) — unchanged.

MECHANISM INTERROGATION
- Tactic 1 (kernel): not touched — one tap per channel is already the swirl's identity; a Jacobian-footprint filter
  would be a second multi-tap idea on a sibling file in the same fork, so it is left out.
- Tactic 2 (physics one step further): the file already models three wavelengths (650/550/450 nm) — but only for
  absorption. The first-order side effect of any wavelength-dependent medium is a wavelength-dependent index of
  refraction (Cauchy `n = A + B/λ²`), i.e. a per-channel radial magnification (lateral colour) on top of the angular
  split. Second: a real absorbing medium that is also turbid *scatters* part of what it removes, with a λ⁻⁴ spectrum.
- Tactic 3 (promote an intermediate): `WAVELENGTH_RED/GREEN/BLUE` (never used for geometry) feed Cauchy;
  `alphaR/G/B` (transmittance) already computed — `1 − α` is the extinction budget the file throws away; it is the
  scatter source.
- Tactic 6 (history): file owns no C reading; A is telemetry and nobody reads it → deliberately none.
- Tactic 8 (energy accounting): HEAD absorbs energy and returns nothing (core → black, then a fixed purple
  `swirlGlow`). Rayleigh in-scatter returns a fraction ω of the extinguished light, blue-weighted.

ADD
1. **Cauchy radial lateral colour (§12.2F)** — per-channel radial scale
   `s_c = 1 + K·(1/λ_c² − 1/λ_G²)` (λ in µm, from the file's own `WAVELENGTH_*`; `K ∝ aberration`, the existing
   slider). R image slightly larger/nearer, B slightly smaller → radial fringes that grow with distance from the pointer,
   composed with the existing per-channel swirl angles (applied to the offset before the rotation).
2. **Rayleigh in-scatter (§12.2F)** — `out_c += (1 − α_c)·ω·L·t_c`, `t_c = (λ_G/λ_c)⁴` normalised, L = luminance of the
   un-attenuated sample. The thick swirl core becomes a dim blue-weighted haze instead of dead black; energy
   accounted (ω < 1, never adds more than the removed fraction). Replaces nothing: `swirlGlow` stays.

FORMULA ADMISSION: both rows are in the lighting/optical table; this file *is* a dispersive absorbing volume
(wavelength-dependent index of the swirl = the existing angular split; wavelength-dependent absorption = existing
Beer–Lambert). Both consume quantities the file already has (offset vector, WAVELENGTH_*, `alphaR/G/B`, `aberration`).
Deleting either leaves exactly HEAD; keeping only either is still the same twirl.

FORBID on this file: new params, springs/ripples, IQ palette, chroma-delay, Brown–Conrady (sibling file), changing the
2.8 / 2.2 angular multipliers, changing `calculateChannelAlpha`, any change to the A telemetry packing.

A PACKING: telemetry (dist/radius, angle/12, aberration, alpha) — HEAD packing kept, nobody reads C.
