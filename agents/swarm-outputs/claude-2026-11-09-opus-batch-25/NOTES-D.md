# Fork D notes

## scan-distort (second pass)
Kept verbatim: scanline bend, ripples, quantise, block edges, MV LK arrows, DCT garble, sync tear, feedback smear, params, A packing.
Ideas in diff: 4:2:0 chroma macroblock bleed (4-tap Cb/Cr average over half-block cells, full-res luma; quant slider coarsens); P-frame macroblock skip (inside glitch pulse, `blockStill` from LK residual + hashed pick copies C).
A packing: pre-ACES linear RGB + semantic alpha (unchanged). Render: meanL 0.44→0.44, meanA 1.0, no NaN.

## directional-glitch (RESCUE + ideas)
HEAD bugs: `dir`/Angle Bias computed but unused (radial-from-centre CA only); whole-frame 80% kaleido echo through filtering sampler → pastel wash (stdL 0.019, meanA 0.385); ACES stored in A and re-graded; alpha floor 0.15.
Fixes: exact textureLoad C, echo local to SDF mask (≤0.8, scaled by intensity) centred on mouse, A = pre-ACES linear, alpha = max(source a, coverage).
Ideas in diff: compass-snapped cell headings (voronoiCell + 45° hashed turns), directional block tear (block-pitch slide + RGB split along heading), leading-edge overrun sliver.
Render: stdL 0.019→0.082, meanA 0.385→1.0, intensity=0 ≈ source (meanL 0.475), no NaN. Unused chromaticAberration helper removed.
Gates: wgsl_precommit_gate ✅ both; audit:dead-sliders PASS.
