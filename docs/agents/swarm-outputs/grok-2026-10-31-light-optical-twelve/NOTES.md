# Notes — light / optical twelve (2026-10-31)

Second pass on files that already named ideas, except `light-leaks` and `spec-spherical-harmonics-light`, which did not have an idea-bearing upgrade. Saved `params` arrays were not edited. Eleven pasted headers were migrated to `#include "_prelude.wgsl"` before the visual edits.

## Per shader

- **divine-light** — kept the 16-step march, HG phase, depth occlusion, decay/density/threshold/intensity. Added phase-warmed shaft tint and aerial veiling of the source under `rayLuma`. A packing unchanged: ACES display RGBA.
- **neon-light** — kept blackbody, Schlick, tube tangent, thermal fog, and raw phosphor in A. Added a dim bore plus sheath shoulder, and leftover phosphor recolored toward 1200 K. ACES stays on `writeTexture` only.
- **volumetric-god-rays** — kept the 48-step march, luma occluder, Mie phase, sun disk, density/decay/weight/exposure. Added dust Beer–Lambert on the existing decay multiply (§12.2F) and a Cauchy R/B sample split along the ray (§12.2F), replacing the old scalar R-up/B-down tint. A packing unchanged: ACES display RGBA.
- **light-leaks** — the on-disk shader was a halftone that did not implement Intensity, Warmth, Leak Size, or Drift Speed. Restored the mouse blob, two drifting blobs, white core, and screen blend those params name. Added a rebate streak from the edge facing the pointer, a magenta dye fringe, and red halation with a bleached core (§12.2A). A packing: ACES display RGBA. C is not read.
- **kimi-spotlight** — kept size/softness/darkness/boost, the desaturate-outside mix, the spring at `extraBuffer[133..138]`, click rings, beam rim, and hotspot. Added soft inverse-square inside the smoothstep gate (§12.2F) and Airy rings on the hotspot (§12.2F). ACES on display. C is not read as a field.
- **alpha-aurora-bands** — kept the five altitude layers, emission lines, folds, and green-line shimmer. Added lower-border brightening and a Rayleigh blue limb under the curtain (§12.2F). A packing unchanged: ACES display RGBA.
- **aurora_borealis** — kept ribbon count/speed/width/glow, curl, crest corona, and the bass envelope in A.a. Added an equatorward red proton arc under the first ribbon and star occultation by coverage. A packing unchanged.
- **pp-bloom** — kept soft-knee hue-preserving extract, quality tap counts, and the horizontal streak. Added an energy-conserving composite (§12.2F) and a Cauchy fringe on that streak (§12.2F). A packing unchanged: ACES display RGBA.
- **velvet-scatter-bloom** — kept the scatter loop, dark mask, nap direction, held crush, and edge bloom. Far taps now weight red and near taps weight blue (§12.2F Beer–Lambert per channel). A dark trough sits beside the existing sheen. A packing unchanged: ACES display RGBA.
- **neon-pulse-edge** — kept threshold, glow radius, pulse speed, cycle, HSV rim, and treble sub-harmonic. A.r now stores `max(edge, 0.86·previous edge)` so the halo trails, and the core pulse travels along the Sobel tangent. ACES stays on `writeTexture`.
- **interactive-film-burn** — kept radius/speed/grain/glow, the burn-center spring, click brands, conveyors, oil-slick fire, and A = `[hole, fire, smoke, alpha]`. Added a blister warp in the glow ring, upward smoke, and scar/cooling reads of C.r and C.g. Stopped mixing those masks into the photo as color. ACES on `writeTexture` only.
- **spec-spherical-harmonics-light** — kept the 9 coefficients, depth normal, held-pointer nudge, and the four slider roles. L1 is scaled by 2/3 and L2 by 1/4 against an unchanged L0. Specular aims along the L1 luminance. Fresnel–Schlick (§12.2F) rides that specular. A packing is now ACES display RGBA; C was not read, and the old raw `shLight`/`spec` store was unused by this shader.

## Formula use this batch

| Formula | Files |
|---|---|
| Beer–Lambert | volumetric-god-rays, velvet-scatter-bloom |
| Cauchy | pp-bloom, volumetric-god-rays |
| Energy-conserving bloom | pp-bloom |
| Soft inverse-square | kimi-spotlight |
| Airy | kimi-spotlight |
| Fresnel–Schlick | spec-spherical-harmonics-light |
| Rayleigh | alpha-aurora-bands |
| Halation | light-leaks |

No new springs. No IQ palette.
