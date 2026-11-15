# Notes — trace-grade ten (2026-11-15)

Second pass. Each file kept its kernel and its saved params. The two new ideas are the lines marked `// ── Idea` in the diff. Earlier ideas were left in place.

Prelude migration (`rgb-iso-lines`, `mirror-drag`, `green-tracer`) is infrastructure. It is not one of the ideas.

## hex-circuit

- Kept: axial hex cell, edge and via distances, the four slider roles, mouse pulse, via pad, C.a edge persist.
- Idea 1, edge-aligned trace: `trace` weights the hex wall by how well its normal faces the photo gradient (`dRx`, `dUy`).
- Idea 2, joule heating: `heat` from `persist` shifts the pulse color toward copper. Idle alpha stays below the 0.16 floor.
- A packing: ACES display RGBA. C.a is still the persist.
- Formula: none from §12.2.

## rgb-iso-lines

- Kept: R at +offset, G at uv, B at −offset, thickness / frequency / parallax / background, wavelength alpha, runners, ridge ticks, click fronts, hsv slick.
- Idea 1, index contours: `indexWeight` (every fifth iso) draws `indexWidth` on top of the same `isoLine` test.
- Idea 2, downslope ticks: forward difference of green, ticks along that gradient, gated by the line mask and by slope.
- Packing correction: A used to store `(lineR, lineG, lineB, alpha)` while C was mixed as color. A is now the linear composite. ACES is on `writeTexture` only, so the 0.22 mix is not tonemapped twice. The JSON description now says so.
- Formula: none from §12.2.

## mirror-drag

- Kept: `mix(uv.x, 1−uv.x, mirror)`, drag offset, chromatic R/B delays, trail decay, shard quantization, click fronts, the existing spectral glow.
- Idea 1, hinge crease: one extra sample of the unflipped drag (`plainUV`). The difference is drawn on the fold, scaled by Mirror Amount.
- Idea 2, facet shade: `facetLit` from the existing `shardAngle`, scaled by Shatter Amount. At shatter 0 the multiply is 1.
- A packing: linear trail RGBA. ACES on `writeTexture` only.
- Formula: none from §12.2.

## chroma-depth-tunnel

- Kept: tunnel base (angle, inverse radius, helix, flight), throat ring, ribs, runners, click shocks, the existing palette, the history streak, all four slider roles.
- Idea 1, Cauchy path split (§12.2F): `cauchyScale` skews the existing ±path offsets. Blue’s lead is larger. Chroma 0 still collapses the split.
- Idea 2, wall Fresnel (§12.2F): Schlick on the bore angle, multiplied by the existing fog so the throat stays dark.
- A packing: ACES display RGBA. Unchanged.
- The two `pow(..., 2)` calls that could see a negative base are now squares. The rib `pow` base stays in 0..1.

## gen-islamic-geometric-tiling

- Kept: star, interlace, girih dart, rosette loop, over-under mask, gold glints, glaze, gilded waves, raw HDR in A.
- Idea 3, grout joint: mortar on the pre-rotation cell edge. Width follows Line Width. Mixed to a dark mortar so the joint reads on the midnight ground.
- Idea 4, strap bevel: outer lip of the star stroke gains gold, inner lip darkens.
- A packing: raw HDR display RGBA. ACES on `writeTexture` only. Unchanged.
- Formula: none from §12.2.

## green-tracer

- Kept: trail fade from Trail Length, edge gate, motion threshold, green tint, grain, glow. A.rgb is still the untinted trail so the tint does not compound.
- Idea 3, phosphor strike: `trailGain` is yellow-green on a fresh edge and deep green on the rested trail. Display only.
- Idea 4, phosphor bloom: four `textureLoad`s of C, green-weighted, scaled by Glow Intensity. Not the film halation constants.
- A packing: trail RGB in A.rgb. A.a is coverage (it was a hardcoded 1). ACES on `writeTexture` only. C.rgb is the trail.
- Formula: none from §12.2.

## ascii-shockwave

- Kept: the shader’s slider roles, not the JSON display names. x is ascii amount, y is wave speed, z is cell count, w is dot size. Dot / cross / box / fill, held amount, click fronts, conveyor, packets, the 0.28 trail mix. Params were not renamed.
- Idea 1, mid-ramp bar: a horizontal stroke mixed into the cross band.
- Idea 2, cell-average luma: four corner taps plus the center sample choose the glyph. Color still comes from the center.
- A packing: linear display RGBA. ACES on `writeTexture` only.
- Formula: none from §12.2.

## analog-film-degrade

- Kept: per-channel seeds, weave, hairlines, dust, sepia constants (`1.2 / 0.9 / 0.6`, `0.5` and `0.3` fades), `0.10 * fade` print-through, vignette.
- Idea 1, density-weighted grain (§12.2A): `sqrt(L(1−L))` multiplies the existing `gR/gG/gB`. Grain Intensity is still the amplitude.
- Idea 2, halation (§12.2A): four taps of clipped highlight, red `(1, 0.35, 0.10)`, core bleached toward `srcLuma`, amount from Fade.
- A packing: ACES display RGBA. Unchanged.
- This is the worked second pass in `docs/SHADER_UPGRADE_BATCH.md` §12.6.

## color-blindness

- Kept: the three matrices, the 0–2 type mix, severity, the split at pointer x, the seam, the assist amount. The slider is still named Unused.
- Idea 1, luminance restore: after the mix, scale so simulated luma matches source luma.
- Idea 2, type-aligned hatch: the same hatch amount, along an axis that is nearly horizontal for protan, diagonal for deutan, vertical for tritan.
- A packing: ACES display RGBA. C is not read.
- Formula: none from §12.2.

## glitch-ripple-drag

- Kept: the spring in `extraBuffer[133..138]`, direction quantization, held strobe, velocity-scaled chroma, click displacement, exact C loads. A.a still means “history is valid”.
- Idea 3, scanline tear: `bandY` is constant across a row. While `bandWave` is up, displacement mixes toward one horizontal `rowOff`.
- Idea 4, dropout tail (§12.2B): `wake` is an exponential just off the existing ring, longer as Glitch Factor rises.
- A packing: ACES display RGBA. Unchanged.
- The click-front `pow` of a possibly negative base is now a square.
- JSON: `upgraded-rgba` added. The shader already had ACES and the earlier ideas.

## Formula use in this batch

| Row | File |
|---|---|
| Density-weighted grain (§12.2A) | analog-film-degrade |
| Halation (§12.2A) | analog-film-degrade |
| Cauchy (§12.2F) | chroma-depth-tunnel |
| Fresnel–Schlick (§12.2F) | chroma-depth-tunnel |
| Dropout tail (§12.2B) | glitch-ripple-drag |

No row is on more than one file.
