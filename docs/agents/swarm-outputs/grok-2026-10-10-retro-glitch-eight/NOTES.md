# Notes — retro-glitch eight (2026-10-10)

Cards were written before WGSL. Each file kept its kernel and slider roles. Springs and click fronts stayed only where the file already had them. Headers moved to `#include "_prelude.wgsl"` in the same pass as the ideas.

## data-moshing

Kept: gradient flow into an accumulated offset, spring scrub, click-front corruption, block-hash events, quantize, four slider roles.
A packing: raw sim `(offset.xy, confidence, age)`. ACES is only on `writeTexture`.
In the diff: `macroblockMV` projects the offset onto one axis per block; `residualSpark` tints where that vector moved.

## data-moshing-diffusion

Kept: fp128 offset add, kappa loop, stream packets, held swirl, click fronts, four slider roles.
A packing: raw sim `(offset.xy, unused, alpha)`. The old mix of `C.rgb` into the picture is gone, because C is the offset field.
In the diff: `tangentDiffusion` scales the four coefficients along the contour; `packetWake` mixes an upstream sample by packet brightness.
Also fixed `max()` being called with three arguments inside `stream_packet`, which is why this id left `wgsl_validation.json` knownFailures (ratchet 35 → 34).

## digital-decay

Kept: block-hash displacement, bit flip, ghost mix, spring hotspot, four slider roles.
A packing: ACES display RGBA. C is the previous display frame.
In the diff: `blockTear` slides the lower half of a corrupting block; `stuckRow` latches that row to the ghost. The existing corruption-near-zero bypass still restores the photo.

## digital-waves

Kept: three-sine field, glitch blocks, pixelation mix, spring focus. Live roles stay x displacement, y speed, z scale, w detail. Saved param names were not retargeted.
A packing: raw diagnostic `(wave, depth, ripple, alpha)`. C is not read.
In the diff: `standingNodes` darkens cancellations; `crestScan` bunches the existing scanlines on positive crests.

## pixel-rain

Kept: three rain layers, column scroll, spring repulsion, four slider roles.
A packing: ACES display RGBA. C is the previous display frame.
In the diff: `glyphTail` inside `rainLayer`; `columnBlank` mixes a rare column back to the photo by the glitch slider.

## rgb-glitch-trail

Kept: intensity decay from C, radius add, warped-FBM offset, chaos streaks, four slider roles. This file has no spring, and none was added.
A packing: raw sim `(intensity, trailHue.rg, persistence)`. ACES is only on `writeTexture`.
In the diff: `channelLag` samples R and B along `warpDir`; `persistenceComet` reads upstream intensity from C.

## spectral-glitch-sort

Kept: luma gate, angle, spring epicenter, click tears, four slider roles, display history in A.
A packing: ACES display RGBA.
In the diff: `sortWalk` takes four steps and keeps the brighter sample; `chromaSort` offsets R and B on that axis by the noise slider.

## datamosh-brush

Kept: spring smear vector, macroblock edge, decay mix, four slider roles.
A packing: ACES display RGBA. C is the previous display frame.
In the diff: `dcHold` flattens a corrupting block toward its center sample; `mosquitoRing` flickers on the existing edge.

## Gates

Per-file `wgsl_precommit_gate.py`: 8/8 naga and bind-group pass.
`verify-naga-wasm --all`: 1400 valid, 34 known-bad, 0 new. `data-moshing-diffusion` left knownFailures (ratchet 34).
`audit:extrabuffer` pass (1428 files, 0 new writes into `[0..132]`).
`audit:dead-sliders` on these eight: 0 new dead sliders.
`npm test -- --watchAll=false --ci`: 133 suites, 1011 passed, 1 skipped.
`SKIP_WASM_BUILD=1 npm run build`: compiled successfully.
Real-GPU visual QA was not run. This VM has no hardware GPU adapter.
