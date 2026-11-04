# Notes — thermal / blackbody twelve

Second pass on files that already named ideas. The new pair is in the existing main path. Saved `params` were not renamed or re-defaulted. No new spring. Real-GPU visual QA is external.

Formula rows used: §12.2A local-contrast unsharp on thermal-vision only. §12.2F energy-conserving bloom on spec-blackbody-thermal only. §12.2F Beer–Lambert on heat-haze-gpt52 only. The heat-field stencil on sim-heat-haze-blackbody is a binomial 4/2/1 kernel, not the §12.2D Laplacian row.

## thermal-vision

- Kept: false-color ramp stops, blackbody only on the hot shoulder, split-tone, vignette, ACES then hue-preserve, IGN, Sensitivity / Color Range / Noise / Blur roles.
- Added: isotherms on `heat` (`isoSteps` from Color Range); detail unsharp `l - boxLuma` into heat while Thermal Blur still only mixes the box.
- A packing: ACES display RGBA. C is not read.
- JSON: dropped the false `mouse-driven` tag. The pointer is not read.

## thermal-vision-blackbody

- Kept: Kelvin range, contrast power, Color Shift scale, NUC bars, hot lag from C.a, 12-tap glow, held mouse heat.
- Added: narcissus on `viewT` only (A.a stores `storedT`); well overflow replaces the flat 0.3 glow mix.
- A packing: raw thermal RGB + normalized T.

## thermal-touch-blackbody

- Kept: halo, click rings, buoyant streak, ember tint, Original Blend, ambient mix.
- Added: same-pixel dwell from C.a under `mouseHeat`; scorch toward a dark oxide after ACES, before Original Blend.
- A packing: ACES display RGBA + tempNorm alpha.

## spec-blackbody-thermal

- Kept: depth conduction, isotherms, ember filaments, Wien fringe, chroma-by-tempNorm, persistent ember, glow loop gated by Ember Glow.
- Added: `emberDecay` drops with `tempGrad`; after the glow mix the core is pulled toward a dimmer luma (§12.2F).
- A packing: raw thermal HDR + tempNorm alpha. ACES on writeTexture only.

## sim-heat-haze-blackbody

- Kept: ground heat, source count, mouse heat, 0.98 cool, Schlieren, plume shear, Convection Speed on the photo displacement.
- Added: binomial weights on the same 3×3; temperature carried from smaller y (the ground) by Convection Speed.
- A packing: raw temperature in A.r.

## heat-haze-gpt52

- Kept: fbm warp, chromatic split, inferior mirage, boundary boost, held pool, filaments, packets, clicks, 22% C blend.
- Added: glitter on `groundY` masked by `pools`; Beer–Lambert veil from `(boundary - 1)`.
- A packing: display RGBA.

## honey-melt-blackbody

- Kept: hex metric, gravity, pull and swirl, click rings, Beer amber, packing velocity / thickness / temperature.
- Added: thickness thins with `length(velocity)`; cool thick cells mix toward a pale wax skin.
- A packing: raw sim. ACES on writeTexture only.
- JSON features: mouse-driven, audio-reactive, click-reactive, upgraded-rgba. Params unchanged.

## melting-oil-blackbody

- Kept: downhill and tangent flow, viscosity damping, mouse swirl, click fronts, ember bloom, packing velocity / temperature / molten.
- Added: Marangoni step toward the cooler neighbor after the viscosity multiply; meniscus lip where molten meets a less-molten neighbor.
- A packing: raw sim. ACES on writeTexture only.
- JSON features: mouse-driven, audio-reactive, click-reactive, upgraded-rgba. Params unchanged.

## warp-drive-blackbody

- Kept: sample loop, bow/mid/wake UVs, center glow, wall annulus, held hotspot. Brightness and Samples still also set the Kelvin range.
- Added: inside `bubbleR` the photo-to-thermal mix drops (`pocket`); outside the wall, mix toward last frame's C.a Kelvin when that alpha is already warm.
- A packing: raw HDR + avgTemp/15000. C.a is previous avgTemp.
- The wall gaussian uses a square instead of `pow(negative, 2)`.

## energy-shield-blackbody

- Kept: hashed whole-cell strikes, Faraday edge vs fill, click heat on the edge, `max(prev * Decay, activation)`.
- Added: a fraction of the trail one hex step away enters `newTrail`; fresh `cellHit` keeps the cyan, and the decayed trail adds a blackbody at Kelvin from `newTrail` (a small cyan remainder stays so the tail is still a shield).
- A packing: raw trail in A.r.

## gamma-ray-burst

- Kept: spring in extraBuffer[133..138], Lorentz beaming, jet core, magnetic spiral, the first click burst, synchrotron gaussian shape, Exposure flare. A stays `(burst, doppler, spiral, alpha)`.
- Added: blue then green fall off as `fract(time * 1.5)` advances; wings fade past `6/jetSpread`.
- Removed: a second click loop and an IQ clock-ring that redeclared `aspect` and `rippleCount`. That stamp did not compile (it was in `wgsl_validation.json` knownFailures). The spectrum `pow` squares are now multiplies of the same offsets.
- A packing: diagnostic fields. C is not read. ACES on writeTexture only.
- Known-failure ratchet: 22 → 21, id removed.

## gamma-ray-burst-blackbody

- Kept: 20-tap radial blur, bipolar lobes, ray density, core glare, afterglow add from C, raw RGB + energy. Intensity and Decay still also set the Kelvin range.
- Added: an expanding blast-wave shell in blackbody; the stored afterglow is multiplied by `(1, 0.46, 0.14)` before it is added.
- A packing: raw burst RGB + energy.

## Floor

Eleven pasted headers migrated with `migrate_to_prelude.py` (gamma-ray-burst already included the prelude). 16×16, exact C where C is read, A packing as above. `Upgraded:` dates moved because of the ideas, not because of the include swap.

## Gates

Naga 12/12. Precommit 12/12. extraBuffer 0 new. Dead sliders 0 new. Catalogs regenerated. Vitest 180 files / 1532 passed (1 skipped). `SKIP_WASM_BUILD=1 npm run build` succeeded. Real-GPU visual QA is external.
