# Fork D Idea Cards (written before WGSL edits)

SHADER: scan-distort (second pass; 2026-09-28 ideas kept)
IDENTITY: CRT scanline bend around the cursor over a block-quantised codec picture, glitch pulses with a sync-tear band, DCT garble, MV arrows.
KEEP VERBATIM: scanline bend + ripples, quantise/edge-keep, block edges, MV arrow LK estimate, DCT garble, sync tear, C feedback smear, param roles, A packing (pre-ACES linear).
ADD:
  1. 4:2:0 chroma macroblock bleed — luma stays full-res but Cb/Cr are averaged over a 2x2 group of half-blocks, so colour spills past edges the way a subsampled codec does; coarser with fewer quant levels.
  2. P-frame macroblock skip — during a glitch pulse, blocks whose LK motion is near zero are "skipped" and copied whole from C (the decoder reuses the reference), leaving stale frozen tiles beside refreshed ones.
FORBID: interlace field shear (exists elsewhere), mosquito ringing (exists), generic spring/ripples beyond HEAD's.
A PACKING: pre-ACES linear display RGB + semantic alpha (unchanged).

SHADER: directional-glitch (RESCUE)
HEAD bugs: `dir` (and so Angle Bias) computed but never used — the "directional" glitch had no direction, aberration was radial from screen centre; whole-frame 80% kaleido echo from C via filtering sampler washed the picture to pastel (stdL 0.019); ACES-graded colour stored in A and re-graded every frame; alpha floor 0.15 outside the zone.
IDENTITY: SDF mouse zone where voronoi/fbm glitch blocks tear with chromatic split, audio palette, sparkle, kaleido echo.
KEEP VERBATIM: SDF mask + ring, curl+radial dir, domain-warp fbm + voronoi trigger, palette, temporal sparkle, kaleido echo (now local), param roles.
ADD:
  1. Directional block tear — glitch blocks slide along `dir` by a per-cell step snapped to multiples of the block pitch, with RGB split along the same axis (fixes dead Angle Bias).
  2. Compass-snapped cell headings — each voronoi cell rotates the heading by a hashed multiple of 45°, so neighbouring cells tear in related but different directions.
  3. Leading-edge overrun sliver — a thin bright line at each slid cell's leading edge along its heading (buffer overrun spill).
FORBID: new spring/ripples, replacing kaleido echo.
A PACKING: pre-ACES linear display RGB (was ACES — re-grade loop fixed); alpha = source alpha outside zone, glitch coverage inside.
