# Notes — glass / crystal eleven (2026-11-20)

Idea Cards were written first in `BRIEFS.md`. Saved `params` were not renamed or re-defaulted. ACES is on the display path. Where A is a raw field, that write was left raw.

Formulae, each new on one file: deep-water dispersion and Cauchy scales on `luma-refraction`; Snell and Airy disc on `refractive-bubbles`; wet edge on `alpha-paint-thickness`; Beer–Lambert on `hybrid-reaction-diffusion-glass`. No other §12.2 row is new. No shared spring, shockwave, or palette was added. Springs and click paths that were already in a file were left in place.

Eight shaders had a pasted binding header. They now `#include "_prelude.wgsl"`. That migration is not the upgrade.

## luma-refraction

- Kept: Wave Speed, Mouse Force, Damping, Refraction, the 5-point wave step, luma-scaled speed, mouse stir, click raindrops, audio rain, drizzle, R/G/B offsets, dispersion glint. State stays out of the display.
- Added: deep-water dispersion (§12.2D) — `localSpeed` divided by `(1 + |laplacian|)`; Cauchy scales (§12.2F) — `n(λ)` relative to green multiplies the existing normal. Neighbor state is `textureLoad`.
- A packing: raw `(h, v, 0, 1)`. ACES on the refracted display only.

## mouse-time-crystal

- Kept: Growth Rate, Crystal Density, Age Color Speed, Glow Intensity, the stick test, ripple seeds, age palette, mouse heat.
- Added: growth-face glint from the luma gradient the stick test already uses; cooling rim (flatter image gradient cools faster); density veins from the stored density. Bass scales the existing growth step.
- A packing: raw `(age, branchID, density, temperature)`. ACES on display only. C is `textureLoad`.

## refractive-bubbles

- Kept: Bubble Size, Refraction Index, Bubble Count, Wobble Speed, the orbit, sphere normal, ball-lens core, thin-film wall, contact wall, Fresnel, the existing absorption, point specular.
- Added: Snell rim (§12.2F) with a reflect fallback on total internal reflection; Airy disc (§12.2F) on the existing specular cosine.
- A packing: ACES display RGBA. C is unread.

## alpha-paint-thickness

- Kept: Brush Size, Paint Saturation, Specular Power, Drying Rate, pigment plus thickness, hue brush, splatters, gradient specular, palette-knife ridge, canvas tooth.
- Added: wet edge (§12.2C) from the four thickness taps already loaded; directional impasto shadow along the existing light. The uniform thick-shadow stays.
- A packing: raw pigment.rgb + thickness.a. ACES on display only.

## gen-protocell-division

- Kept: Cell Count, Surface Tension, Iridescence, Division Rate, smin lobes, furrow envelope, mitotic nuclei, film hue, mouse attract, the 5% color trail, premultiplied `writeTexture`.
- Added: division scar (the neck ring after the split, without the mid-split envelope); nucleolus where the nucleus distance is most negative.
- A packing: ACES display RGBA, straight color in A. `writeTexture` stays premultiplied.

## kaleido-portal-interactive

- Kept: Radius, Segments, Rotation, Hardness, the triangle fold, the spring in `extraBuffer[133..138]`, click spin phase in `[139]`, the soft-knee border.
- Added: portal lip (radial bend across the hardness band); spin smear (one extra sample along the tangent, weighted by Rotation and the click burst). Not the mirror-dimension bevel.
- A packing: raw portal tuple `(mask, border, segments/16, alpha)`. ACES on `writeTexture` only. JSON features now include `audio-reactive` and `upgraded-rgba`.

## bismuth-crystallizer

- Kept: Crystal Depth, Hopper Offset, Iridescence Freq, Metallic Mix, the hopper loop, oxide interference, metal Fresnel, terrace rim, tarnish well.
- Added: stair riser (dark band just inward of the lip); oxide graded by `terraceEdge` inside the existing interference phase.
- A packing: ACES display RGBA. C is unread.

## hybrid-reaction-diffusion-glass

- Kept: Feed, Kill, Glass Refraction, Depth Effect, the 9-point Laplacian, the cubic reaction, mouse deposit, click fronts, gradient refraction, palette mix, Fresnel, thickness IOR, divergence caustic.
- Added: Beer–Lambert (§12.2F) on the photo before the mix, scaled by Glass Refraction; a meniscus from `|laplacian|`.
- A packing: raw `(chem, |grad|, caustic, coverage)`. ACES on display only.

## reactive-glass-grid

- Kept: Tile Density, Refraction, Glow, Edge Smoothness, the spring in `extraBuffer[133..137]`, click shockwaves, per-tile FFT voice, chromatic taps, Fresnel rim, caustic hash.
- Added: a resting pillow lens from `localUV` that remains when influence is zero; grout darkening at the tile edge, under the existing glow.
- A packing: ACES display RGBA. C is unread. JSON features now include `audio-reactive` and `upgraded-rgba`.

## fractal-noise-dissolve-nlm

- Kept: Noise Scale, Radius, Edge Width, NLM Mix, the noise sum, patch SSD, the search loop, the similarity bias, the burn color.
- Added: similarity-scaled edge width; NLM residual put back on the survivor; ash under the burn. Bass flares the existing burn. Not the char cracks or ember lift from `fractal-noise-dissolve`.
- A packing: ACES display RGBA. This file did not write A; it now stores the display color. C is unread.

## quantum-wormhole

- Kept: Intensity, Speed, Scale, Detail as twist / flow / trail / persistence, `to4D`, `curlField`, HSV twist, oil slick, highlight burst, void invert, helix, click rings, the C trail.
- Added: frame drag as a tangential add on the curl; gravitational redshift of the existing HSV in the throat; an Einstein ring that resamples the photo from the far side. Not the additive photon ring from `cyber-physical-portal`.
- A packing: ACES display RGBA. C is the color trail.
