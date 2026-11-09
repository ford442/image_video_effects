# BRIEFS — fork C (written before WGSL edits)

SHADER: cyber-glitch-hologram
IDENTITY: pointer-local hologram over a block-swap + structure-tensor datamosh, two depth-parallax layers, fp128 interference fringes, racing scan carrier, C smear, click rings.
KEEP VERBATIM: block swap hash, structure-tensor mosh, parallax layers, fringe, racer, smear, click rings, alpha formula, 4 param roles.
RESCUE: plasmaBuffer[band+1] (bands 1..8) is never uploaded (only index 0) → spectral tint dead; drive it from treble × fringe instead.
ADD:
  1. Swapped-macroblock seams — blocks that swapped get a thin hologram-cyan outline at their block border, so the datamosh grid itself reads as a glitched hologram projection.
  2. Depth-slice contour lines — depth isolines (fract(depth·N)) drawn in the fringe's cyan/magenta, phase-scrolled by the scan, inside the pointer hologram (volumetric slicing look).
  3. Racer projector dropout — as the scan carrier passes, the hologram flickers: tint + alpha dip where racer·hash hits (projector losing lock), bass widens it.
FORBID: springs, palettes, new ripples.
A PACKING: linear smear RGB + alpha (unchanged, C read as colour).

SHADER: data-stream-corruption-hdr
IDENTITY: pointer-painted corruption field (C.r) unleashing column-block displacement, RGB split and green glyph rain, plus HDR bloom and click flashes.
KEEP VERBATIM: corruption brush + persistence, column/row glyph grid, packet heads, block displacement, RGB split, click flashes, 4 param roles.
RESCUE: (a) packing lie — C.rgb read as prevSmear colour while A stores (corruption,0,0,alphaHistory) → the "smear" mixed a red corruption mask into the picture; (b) bloom thresholded source at >1.0, never reached by an LDR input → bloom slider dead; (c) plasmaBuffer[1..8] dead.
ADD:
  1. Glyph phosphor trails — A.g stores decaying glyph emission; C.g re-emits as green trail behind falling glyphs (replaces the fake smear, fixes the packing lie).
  2. White-hot packet glyphs — glyph leading edges in hot packet columns burn near-white HDR; bloom gathers the stream emission field from C so the slider works.
  3. Corruption frontier seam — gradient of the corruption field (C.r neighbours) lights a cyan bit-flip edge where clean data meets corrupted.
FORBID: springs, new palettes.
A PACKING: [corruption, glyph trail energy, 0, alphaHistory].
