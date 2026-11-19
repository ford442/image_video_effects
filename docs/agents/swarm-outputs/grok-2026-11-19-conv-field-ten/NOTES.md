# Notes — conv / field ten (2026-11-19)

Idea Cards were written first in `BRIEFS.md`. Saved `params` were not renamed or re-defaulted. ACES stays on the display path. Raw fields stay raw.

Formulae: density-weighted grain (§12.2A) is new only on `film-gate-weave`. No other §12.2 row is new in this batch. No shared spring, shockwave, or palette was added.

`iso-hills` had a pasted binding header. It now `#include "_prelude.wgsl"`. That migration is not the upgrade. Its id was removed from `src/contracts/prelude_migration.json` `pending`.

## conv-non-local-means

- Kept: patch / search / h / overdrive, luma-vs-chroma SSD, tangent bias, self-weight, focus zone, ripple echo on h.
- Added: Gaussian window on the patch SSD (centre weight 1); centre-luma preselection multiplied into the existing weight.
- A packing: ACES display RGBA. Unchanged.

## film-gate-weave

- Kept: weave / dust / scratches / flicker, frame-line strip, scratch field in C.g, cue-dot cycle, splice and click flash. The extraBuffer[133..138] spring is still the HEAD no-op.
- Added: density-weighted grain (§12.2A) on the existing dye-cloud grain; one horizontal registration-pin offset per 24 fps frame, scaled by the weave slider.
- A packing: (rgb.r, scratch, 0, alpha). Unchanged.

## conv-morphological-erosion-dilation

- Kept: radius / blend / gradient boost / mouse influence, per-channel winning colour, top-hat, black-hat, SE-axis skeleton, mouse rotation of the disk.
- Added: parabolic penalty k·r² on the comparison only (stored colour is unpenalized); contact relief shading the existing gradient from the erosion and dilation offsets.
- A packing: ACES display RGBA. Unchanged.

## conv-frequency-domain-notch

- Kept: band count, bandwidth, boost/cut, mouse frequency, cosine kernel, gaussian envelope, notch response, residual cut, existing response palette.
- Added: 0.4 × cos(2ω) inside the same kernel; a Hann window across the kernel support.
- A packing: ACES display RGBA. Unchanged.

## conv-stochastic-stipple

- Kept: cell size, threshold, saturation, mouse resolution, blue-noise gate, bright-dot polarity, paper ground, gradient ellipse, local-mean colour.
- Added: one Lloyd step (hash site mixed toward the cell's luma centroid); a darker nib rim inside the existing ellipse.
- A packing: ACES display RGBA. Unchanged.

## conv-bilateral-grid-splat

- Kept: spatial sigma, intensity sigma, grid resolution, mouse detail zone, spatial × intensity × depth weights.
- Added: trilinear slice at the centre luma (replaces the constant 0.35 neighbour mix); residual add-back scaled by how coarse the bins are.
- A packing: ACES display RGBA. Unchanged.

## multi-turing

- Kept: DA, DB, DT, Sims weights, feed/kill maps, spot seeds, b coupling, mouse and ripple seeding. The solver is not retuned.
- Added, on the display only: substrate halo where scale-1 `a` has fallen and `b` has not; a membrane where |b1−b2| changes across a pixel. Bass shifts the display mix of the two scales and is 0.6/0.4 at silence.
- A packing: raw sim (a1, b1, a2, b2). ACES on the display write only. Alpha is pattern coverage, not 1.

## conv-bilateral-dream

- Kept: spatial sigma, colour sigma, hue shift (still zero at the default), mouse influence, joint depth in the range, ripple tightening.
- Added: chroma distance inside the existing range; the C hold is stronger where the bilateral barely moved the texel and weaker on the edge.
- A packing: ACES display RGBA. Unchanged.

## conv-spiral-blur

- Kept: tightness, arm count, sample count, mouse centre, Archimedean/log mix, golden arm offset, exp envelope, existing golden tint.
- Added: each station averaged with a sample along the tangent normal; the existing weight divided by the arc element r·dθ.
- A packing: ACES display RGBA. Unchanged.

## iso-hills

- Kept: contour steps, height scale, smoothness, haze, elevation palette, sine hachure, analytic normal, erosion and river carve.
- Added: every 5th contour is wider; fall-line ticks along the downhill vector, masked to the index contours, beside the sine hachure.
- A packing: raw relief (smoothHeight, contour, shade, alpha). ACES on the display write only. C is not read.

## Gates

Naga 10/10. Precommit on these ten passed. Dead sliders 0. Vitest 1944 passed, 1 skipped. `npm run build` succeeded.

`verify:shaders:fix` still fails on `cosmic-web-structure`, `gen_cyclic_automaton`, `mycelium-network`, and `phase-memory-weave`. This branch is four commits behind `origin/main`, and those four still paste a binding header in the diff against main. They were not edited here.

Real-GPU visual QA: external. The VM has no hardware GPU.
