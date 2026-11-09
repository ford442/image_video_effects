# opus/batch-25 — fork B Idea Cards (written before WGSL edits)

SHADER: holographic-edge-ripple (2nd pass; 2026-10-05 ideas kept)
IDENTITY: Laplacian edges lit as Fresnel thin-film iridescence with a pointer-held damped edge wave + click fronts.
KEEP VERBATIM: laplacian/sobel kernels, fresnelIridescence orders, grating streaks, depth-parallax layer, params, A packing (linear pre-ACES, 30% edge-gated C).
ADD:
  1. ±1 diffraction-order ghosts — a real hologram throws faint rainbow copies of the edge map to either side along the grating axis; axis rotates with pointer x, separation with Holographic Shift.
  2. Wavefront dispersion — the edge-wave displaced photo sample splits R/G/B with different wave gains (dispersion of the wave the effect already has).
  3. Coherent laser speckle — reconstruction speckle granulates the iridescence on edges; pattern slides with pointer (view angle).
FORBID: springs, palettes, scanlines, new ripple systems.
A PACKING: linear pre-ACES RGBA (unchanged)

SHADER: audio-reactive-temporal-decay
IDENTITY: feedback trails whose decay is driven by a selectable FFT bin range, cinema grade on top.
KEEP: params, fftBin/avgBins, decay formula, CA on trails, spectral overlay, bloom, grain, scanlines, vignette, LGG grade.
RESCUE: anamorphic streak was a fixed vertical line at x=0.5 (not from bright points); C read with filtering sampler on rgba32float; A stored the fully graded/vignetted/scanlined colour → re-grade loop darkens trails each frame; no ACES.
ADD:
  1. Real anamorphic streaks — horizontal 9-tap bright-pass smear along the row (bright points spill sideways like an anamorphic lens).
  2. Spectral persistence — the selected bin range is split into low/mid/high thirds; each third's energy sets R/G/B decay separately so trails fringe by frequency.
  3. Bass push — previous frame sampled with a small outward zoom scaled by bass, so trails bloom outward on kicks.
FORBID: springs, ripples, generic palettes.
A PACKING: linear trail RGBA (pre-grade blended history); display = graded + ACES.

SHADER: pixel-sort-glitch
IDENTITY: threshold-masked pixel sort along H / V / edge direction, melting bright pixels.
KEEP: params+modes, threshold mask, edge Sobel, flowSort branch, ripple tears, A packing (edgeDir, edgeMag, mask).
RESCUE: sortWindow did one bubble pass then returned the sample nearest the pixel's own luma (≈ identity, no sort visible); extraBuffer[133..136] spring is zeroed every frame (epicenter/threshold pinned near 0,0); plasmaBuffer[1..8] block voice is dead; alpha 0.24 over unsorted areas washed the picture.
ADD:
  1. Anchored span rank sort — pixels are grouped into spans along sortDir with a per-line hashed phase; each pixel outputs the k-th smallest luma of its span where k is its position → real sorted gradients.
  2. Spectral span length — FFT bin for the pixel's column band (extraBuffer[5..]) lengthens that band's spans (replaces dead plasmaBuffer[1..8]).
  3. Span-end channel slip — at the bright end of each sorted span the R and B channels slip along sortDir (classic sort-tear fringe).
FORBID: springs, palettes.
A PACKING: edgeDir.xy*0.5+0.5, edgeMag, mask (unchanged; C unread).
