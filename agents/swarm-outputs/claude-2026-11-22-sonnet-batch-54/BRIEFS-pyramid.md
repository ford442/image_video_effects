# BRIEFS — pyramid-downsample-pass1 (coordinator-owned)

pyramid-bandprocess-pass2 and pyramid-composite-pass3: NOT modified. Both already read plasmaBuffer, have ACES on the final output, read C with textureLoad, and are clean on every gate. Pass 1 changes reach the picture through the blur they read from C.

SHADER: pyramid-downsample-pass1
IDENTITY: the Gaussian base of a Gaussian–Laplacian pyramid — a bilateral low-pass of the photo stored in B so passes 2/3 can form the Laplacian residual (orig − blur).
KEEP VERBATIM: shared-memory tile + workgroupBarrier in uniform flow; luma range weight (exp(−Δ²/σ²)) times spatial weight; High Freq Amp tightens range sigma; Low Freq Amp = temporal settle toward last frame's blur (C); B packing (blur RGB, range agreement); writeTexture = photo passthrough; depth passthrough; Mid Freq / ROI params still read.
ADD:
  1. Burt–Adelson generating kernel — the real pyramid REDUCE kernel is the 5-tap [.05 .25 .4 .25 .05] (a=0.4), not a 3-tap. Halo 1→2 (20×20 tile). Gives the residual a true band-pass cutoff; pass 2/3 consume it unchanged.
  2. Beat-opened range sigma — bass relaxes the bilateral range sigma, so the base blurs across mid edges on a hit and the Laplacian residual (neon edges in pass 2/3) flares with the beat. plasmaBuffer[0].x only; no overlay.
FORBID: springs, ripples, palettes, writing A, touching B packing.
A PACKING: unchanged — B = (bilateral blur RGB, range agreement); A not written.
HYGIENE (not an idea): passthrough alpha = source alpha instead of hardcoded 1.0.
