# Notes — kaleido-chroma ten (2026-11-15)

Per shader: what stayed, the packing, and where each idea sits. Cloud VM has no GPU. These notes are structural. They are not visual QA.

## hybrid-noise-kaleidoscope

- Kept: value-noise fbm, the kaleidoscope fold, hueShift, bass on scale, mids on segments, treble on the split, the angle tint, the vignette. Params unchanged.
- The old `finalUV` / `rUV` / `gUV` / `bUV` path never sampled anything. Idea 2 replaces that dead split.
- Idea 1 after the first displacement: `warp2` from two more fbm taps, added as `domain`.
- Idea 2: `pR` / `pG` / `pB` sample `domain` shifted by `chromaticStrength * 18`.
- Idea 3: `seam` from `fract(foldAngle / segmentAngle + 0.5)`, darkens the colour.
- A packing: ACES display RGBA. This file did not read C. The previous A store was the pre-tone colour.
- Formula: none of the three is a §12.2 row.

## chroma-threads-gabor

- Kept: thread rows, mouse vibration, held gain, per-channel X offsets, Gabor at 0 / 45 / 90, the existing palette mix. Amplitude still sets frequency. Channel Split still sets sigma. Params unchanged.
- Prelude migration is infrastructure.
- Idea 1: `orient` from the three absolute responses. It phases the existing sine and adds `grain` to the three sample UVs.
- Idea 2: `core = smoothstep(0.42, 0.05, threadPattern)` brightens the centerline.
- A packing: ACES display RGBA. This file wrote no A before. C is not read.
- Formula: neither idea is a §12.2 row. No audio (the definition does not claim it).

## chromatographic-separation

- Kept: spun per-channel offsets, pointer prism focus, solvent-front `rf`, the tail samples, the alpha helpers. Params unchanged. The JSON viscosity names were not rewritten onto the shader.
- Prelude migration is infrastructure.
- Idea 3: `diffuse = 0.35 + traveled * rf * 0.4` replaces the constant 0.35 mix. Below the front, `rf` is 0 and the mix stays 0.35.
- Idea 4: `frontLine` on `abs(uv.y - solvent)` cools and darkens a wet line.
- A packing: ACES display RGBA, unchanged.
- Formula: neither idea is a §12.2 row.

## gen-symbiotic-neuro-lattice

- Kept: hashed grid nodes, smin, held gravity (same pull, now multiplied by `held` instead of an `if`), bass on the node radius, camera speed from Speed, metallic diffuse. Params unchanged.
- Idea 1: `linkCapsule` to the six neighbours. `sdCapsule` was in the file and never called.
- Idea 2: `fire` is `sin(time * Pulse Frequency - dot(cell, …))`. It swells the node and tints the shade. The old `pulse` local was computed and unused.
- A packing: ACES display RGBA. The previous A store was zeros. C is not read.
- Formula: neither idea is a §12.2 row. No step-count AO (the march is already 100 steps).

## breathing-kaleidoscope

- Kept: inhale vs exhale petal scale, held-breath freeze, FBM segment warp, jewel, axis glow, treble sparkle, film grain. Params unchanged.
- Idea 3: `cycle` / `rising` / `halfT` warp the phase so the positive half is 35% of the cycle. At phase 0 the wave is still 0, so a held pointer still rests.
- Idea 4: `midrib` where `sector` is near 0 (the wedge centerline), scaled by `breathAmp`.
- A packing: ACES display RGBA, unchanged.
- Formula: neither idea is a §12.2 row. No mirror hairline.

## hyb-iridescent-fbm-glow

- Kept: domain-warped fbm, scale / octaves / shift speed / glow mix, chromaticAberration, fresnelRim, oklabMix, ACES, IGN, bass on the warp and the glow. Params unchanged.
- Idea 1: `thinFilm` replaces the cosine `iridescence`. Thickness is `160 + noise * 640 + time * shiftSpeed * 48`.
- Idea 2: `spent` from `luma(glow)` darkens `ca` before the OkLab mix.
- A packing: ACES display RGBA, unchanged.
- Formula: thin-film (§12.2F) and energy-conserving glow (§12.2F). Only file in the batch for each.

## chromatic-focus-interactive

- Kept: strength / blur / focus radius / falloff, held squeeze, click shells, six-blade highlight, runners, packets, oil-slick, zone plate, wavelength absorption, history mix. Params unchanged.
- Idea 1: `lamUm` from `WAVELENGTH_RED/GREEN/BLUE`. `rOffset` and `bOffset` stay opposite; blue's gain is larger.
- Idea 2: `aperture = mix(0.62, 1.0, blades)` multiplies `blurRadius`.
- The held focus ring is the same grey add, written with `smoothstep` instead of two `if`s.
- A packing: ACES display RGBA. C is the previous display. ACES was missing despite the tag; it is floor.
- Formula: Cauchy (§12.2F). File 1 of 2.

## gen-kaleidoscopic-synapse-bloom

- Kept: sector fold, axon, branch, refractory wake, myelin beads, counter-rotating dendrites, bridges, vesicles, astrocyte web, click rings, exact-C smear. Params unchanged.
- Idea: `ranvier` is the gap of the existing `myelinPhase`, added beside the sheath glow.
- Idea: `sigma = 0.075 / (1 + radius * (0.85 + pulseSpeed))`. At radius 0 the width matches the old 0.075. The old `pow` of a signed front was replaced with `front * front`.
- A packing: ACES display RGBA, unchanged. C is colour history.
- Formula: neither idea is a §12.2 row.

## hyb-hex-voronoi-distort

- Kept: nearest hex, mortar gate, animated Voronoi, F2−F1 crack glow, audio and pointer falloff. Params unchanged.
- Idea 1: `cellTarget = mix(hexCenter, site, 0.42)` where `site` is `(voro.cell + voro.point) / density`.
- Idea 2: `seamDir * crack * distortAmount * 0.28` added to that pull.
- A packing: ACES display RGBA, unchanged.
- Formula: neither idea is a §12.2 row.

## interactive-fresnel

- Kept: annular bump, five-tap normal, held ring spacing, grout, packets, click displacement, specular, the view-angle fresnel mix, exact-C history. Params unchanged. Blue stays on the same side of the displacement as red.
- Idea 1: `nLam = 1 + dispersion / λ²`. Red scale is `1 + (nG - nR) * 4`. Blue scale is `max(1 - (nB - nG) * 4, 0.2)` so a hot treble cannot flip blue backward.
- Idea 2: `riser` steepens the inner half of the existing bump.
- A packing: ACES display RGBA, unchanged. C is the previous display.
- Formula: Cauchy (§12.2F). File 2 of 2. The second idea is the groove draft, not the iris blades.

## Floor

Bindings via `#include "_prelude.wgsl"` (two files migrated, eight already included). Workgroup 16×16. Exact `textureLoad` of C where C is read (chromatic-focus, synapse bloom, interactive-fresnel). Saved `params` not renamed or re-defaulted. `x-meta.upgrade.params` added for the noise kaleidoscope, the Gabor threads, the neuro-lattice, and the iridescent glow, matching the saved params. No new springs. No new `extraBuffer` writes.

## Gates

Naga 10/10. `verify:shaders:fix` 11/11. Dead sliders 0. extraBuffer audit pass. `npm run build` succeeded. Vitest full run: 1811 passed, 11 failed, all timeouts while the suite was loaded (setup and environment were several minutes). A quiet re-run of those files except the two numpy models passed 81/81. physarum and sph_fluid were not re-run. Real-GPU visual QA is external.

`verify:shaders:fix` also removed pending prelude ids whose files on this branch already include `_prelude.wgsl` (the other uncommitted batches). That ledger edit is the migration ratchet, not an idea.
