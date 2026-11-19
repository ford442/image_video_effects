# Notes — zoom / weave ten (2026-11-19)

Idea Cards were written first in `BRIEFS.md`. Saved `params` were not renamed or re-defaulted. ACES stays on the display path.

Formulae used once, both on `signal-noise`: chroma delay line (§12.2B) and dropout bursts (§12.2B). No other §12.2 row is new in this batch. No shared spring, shockwave, or IQ palette was added.

`gen-percolation-threshold` and `sacred-geometry-torus` had pasted binding headers. Both now `#include "_prelude.wgsl"`. That migration is not the upgrade. Their ids were removed from `src/contracts/prelude_migration.json` `pending`.

`gen-celestial-weave` stored its bass envelope in `extraBuffer[0]`. That scalar now lives at `extraBuffer[133]`, written only from `(0,0)`. The remap is not an idea.

## liquid-zoom

- Kept: four-layer parallax stack, ping-pong wrap, near/far speed, parallax, fog, per-layer FFT pair, click pulses, held pointer boost, in-place max streak.
- Added: three exact C taps stepped toward the zoom center, maxed with that streak; the existing radial RGB split scales with distance from the zoom center inside `sampleLayer`.
- A packing: ACES display RGBA. Unchanged.

## liquid-jelly

- Kept: Kelvin-Voigt modes, shear, lobe, soliton, tether, arrival-gated clicks, jiggle smear, candy-by-thickness, spring at `extraBuffer[133..138]`.
- Added: Poisson bulge from the sign of the tether (inward thickens, outward thins); capillary beads along the existing soliton, with a highlight on the bead peaks.
- A packing: ACES display RGBA. Alpha is still the thickness the slope reads.

## gen-celestial-weave

- Kept: fbm warp, four slider roles, thread glint, star parallax, constellation pulses, dust motes, gravity lens.
- Added: over-under shed (warm weft / cool warp on the brighter thread); fibers and knots occult stars and constellation links.
- A packing: ACES display RGBA. Unchanged.

## gen-cycloid-bloom

- Kept: hypotrochoid and epicycloid, coarse-plus-refine search, five layers, four slider roles, veins, stamen, crossings, cusp sparks, rolling circle, mouse pull, click waves.
- Added: one faint ring at the outer layer's fixed radius (0.88); a contact bead on the inner point of the existing rolling circle.
- A packing: ACES display RGBA. Unchanged. No new search loop.

## gen-luminous-fluid-chladni-resonator

- Kept: `chladni_multi`, modes N/M, curl fluidity, click flexural waves, sand grains, Faraday lattice, gradient flow, meniscus spec, blackbody mix.
- Added: sand and a pale highlight thicken where `|c|` and `|grad|` are both small; sand fades in the frame margin (free edge).
- A packing: ACES display RGBA. Unchanged.

## mouse-electromagnetic-aurora

- Kept: Coulomb E, B from pointer velocity, LIC filings, sign-coloured curtains, counter-charges anchored at the click, charge / field / distortion / hue sliders.
- Added: curtain probes step sideways along `sign(B)` perpendicular to E; faint log-spaced rings around the pointer, phase-crawling rather than expanding.
- A packing: ACES display RGBA, plus pointer state in texels `(0,0)` and `(1,0)`. Unchanged.

## gen-luminescent-singularity-loom

- Kept: folded thread SDF, smooth-min core, lensed march, shuttle beads, `threadPluck`, four slider roles, existing palette.
- Added: alternate threads offset in Y by a sine of loom speed (the shed); a cool glint on the fat half of the existing pluck.
- A packing: ACES+gamma display RGBA. C is unread. Unchanged.

## gen-percolation-threshold

- Kept: 80×60 lattice, epoch stamp, touch-left / touch-right, threshold and bass on `p`, zoom / bloom / grain, conduction pulses, red bonds, mass fade, opalescence.
- Added: a bar on the cell edge toward each occupied neighbor; a glow on the site whose index equals the cluster label, gated on a valid epoch stamp.
- A packing: lattice state in `[0..79]×[0..59]`; ACES display RGBA elsewhere. Unchanged.

## sacred-geometry-torus

- Kept: five knot taps, phi nodes, phyllotaxis, four slider roles, gold / emerald / sapphire, IQ hue mixed at 0.35, crossing bloom, 3% trail, disc cutoff.
- Added: the emerald ring retuned onto `r≈0.5` (the old `smoothstep` started at 0.55, outside the disc) with a round centerline; the brightest tap stays bright and the runner-up recedes where they separate.
- A packing: pre-ACES display RGB + alpha. The trail mixes before ACES, and A is read with `textureLoad`. Previously A stored `(pattern, ring, lattice, alpha)` while that mix treated C as color. ACES on `writeTexture` only.

## signal-noise

- Kept: fbm, head-switch, DCT block artifact, luma-shouldered noise, quantisation staircase, dot crawl, smear, spring, four slider roles, exact C history.
- Added: §12.2B chroma delay (U/V from a sample to the left, luma full-res, amount = chroma slider); §12.2B dropout (rare line streak, exponential tail, gated by VHS intensity). Head-switch band unchanged.
- A packing: ACES display RGBA. Unchanged.

## Not in this change

`bioluminescent-bloom`, `gen-luminescent-quantum-flora-symphony`, `gen-nebula-light-trail-swarm`, `gen-quantum-pollen`, `gen-velocity-bloom`, and `nebula-gyroid` already include `_prelude.wgsl` on `main`. An earlier pass migrated the older copies on this worktree. Those edits were dropped so this branch does not overwrite the versions on `main`.

## Gates

Structural only. No GPU, so no visual QA.

- Naga 10/10 on the batch, checked before this branch was retargeted onto `main`.
- On the pre-retarget tree, `verify:shaders:fix` passed schema, extraBuffer (0 new), dead sliders (0 new), workgroup, and catalog drift. `npm run build` succeeded. Vitest: 212 files, 1944 passed, 1 skipped.
- Ledger: the ten ids recorded as `upgraded` on top of `main`. The six header migrations are not in this branch.
