# Notes — mosaic / grid / voronoi twelve

Idea cards were written in `BRIEFS.md` before the WGSL edits. Saved `params` were not renamed or re-defaulted. Pasted binding headers were replaced with `#include "_prelude.wgsl"` (infrastructure, not the upgrade).

## hex-mosaic
- Kept: density, reveal radius, edge hardness, sat boost, two-lattice nearest centre, press bulge, grout, glint, vignette grain.
- Ideas in the diff: pointer-keyed bevel (`lightDir` from the cursor); neighbour-pane leak (rejected lattice centre mixed into the grout).
- Also: click rings no longer multiply by `ripples[i].w`, which the prelude documents as padding that is always 0, so the rings that were already in the file can show.
- A packing: ACES display RGBA. C is not read.
- Formula: none from §12.2.

## triangle-mosaic
- Kept: scale / rotation / twist / mix, skewed triangle grid, chromatic seam, grout, centroid tilt, C blend by `boundaryDist`.
- Ideas in the diff: vertex lead-came beads; second sample along the existing tilt, mixed inside the pane.
- A packing: ACES display RGBA. C is that history.
- Formula: none.

## mouse-voronoi-mosaic
- Kept: shatter / edge thickness / color shift / glass opacity, ripple Voronoi, rotate-shift-scale, cosine tint, mouse glow.
- Ideas in the diff: Brown–Conrady bow (§12.2B) on the cell-local vector; dark lead plus inner rim; age patina gated on a real click time.
- A packing: ACES display RGBA. C is not read. A is now written.
- Formula: Brown–Conrady (§12.2B).

## focal-pixelate
- Kept: pixel size / focus radius / softness / invert, block quantization, fringe-only warp, hex kernel, LOD bias.
- Ideas in the diff: aperture well from `fract` inside the block, only where `mix_factor` is already high; hex radius `coc / blocks` so defocus blur grows apart from the grid.
- A packing: unchanged. A is `(mix, 1/blocks, bass, alpha)`. B is the existing metadata. ACES on `writeTexture` only.
- Formula: none.

## pixelate-blast
- Kept: density / blast radius / edge glow / chromatic amount, cascade lattice, bevel tilt, R/G/B split along `blastDir`, linear-HDR C feedback.
- Ideas in the diff: seam darkened by blast energy under the existing edge glow; one extra sample along `blastDir`.
- A packing: linear pre-ACES RGB + semantic alpha.
- Formula: none (the existing chromatic split was not retuned into Cauchy).

## entropy-grid
- Kept: grid size / chaos / radius / invert, warped FBM from the cell id, Clifford kick, influence gate, audio on chaos.
- Ideas in the diff: sample mixes from the free UV toward the cell centre as chaos × influence rises; square-cell edges darken in that same region.
- A packing: ACES display RGBA. C is not read.
- Formula: none.

## chroma-shift-grid
- Kept: three modes, animation speed, lens `distortStr`, `chromaStr`, per-cell warp angle, Voronoi activity, spectral tint mix.
- Ideas in the diff: R/G/B offsets are the existing `smoothOffset` times Cauchy `n(λ)` (§12.2F); lens k and chroma amount rise near the pointer.
- A packing: ACES display RGBA. C is not read. A is now written.
- Formula: Cauchy dispersion (§12.2F).

## hex-pulse
- Kept: base size / pulse strength / wave decay / speed, hex SDF, sin wave from the pointer, neighbour interference, bio glow.
- Ideas in the diff: previous excitation (A.r / C.r) persists, damped by `waveDecay`; photo shaded by `cos(phase)`.
- A packing: raw `(excitation, edge, wave, alpha)`. ACES on `writeTexture` only.
- Formula: not the §12.2D stencil. It is persistence of the excitation this file already stores.

## ripple-blocks
- Kept: live slider roles — x grid scale, y domain-warp amount, z glow, w trail persistence. Not remapped onto the JSON labels (Grid Size / Wave Amp / Freq / Speed). Cymatic interference and audio bands kept.
- Ideas in the diff: out-of-cell pixels take a dim copy of that cell; trail is an exact `textureLoad` of C at the cell-centre pixel.
- A packing: ACES display RGBA. C is that image. The filtering sample of C is gone.
- Formula: none.

## voronoi-shatter
- Kept: density / force / rotation / gaps, outward displace, click shock, bass chatter.
- Ideas in the diff: stored angle in C.b coasts toward this frame's target; a stable fissure across the shard, width from the gap slider.
- A packing: raw `(m_dist, influence, coasted rot/pi, alpha)`. ACES on `writeTexture` only.
- Formula: none.

## interactive-voronoi-web
- Kept: thickness / scale / glow / pulse speed, nearest-site web, traveling pulse, synapse nodes, bass burst.
- Ideas in the diff: strand width tracks the pulse; the negative half of `pulseWave` darkens the photo under the strand.
- A packing: ACES display RGBA. C is not read.
- Formula: none.

## voronoi-light
- Kept: density / light radius / mode / pulse speed, tech and glass modes, the existing `extraBuffer[133..138]` spring, ripple photons, border glow, C feedback.
- Ideas in the diff: radius gate stays, core is `I/(d²+r0²)` (§12.2F); `cellDelta` dotted with the direction to the lantern shades both modes.
- A packing: linear pre-ACES RGB + semantic alpha. The old header said ACES in A; the store was already pre-ACES so the history would not double-tone-map. Header now matches the store.
- Formula: soft inverse-square (§12.2F).

## Formula de-duplication
Cauchy on chroma-shift-grid only. Inverse-square on voronoi-light only. Brown–Conrady on mouse-voronoi-mosaic only. No other §12.2 row is shared.

## Gates
Naga 12/12. extraBuffer audit pass. Dead sliders pass on these twelve. `npm run test:ci`: 180 files, 1532 passed, 1 skipped. `SKIP_WASM_BUILD=1 npm run build` succeeded. Real-GPU visual QA is external.
