SHADER: neon-pulse
IDENTITY: grid of blackbody plasma cells with Gaussian hotspots, heated by audio/cursor/clicks, T^4 cooling through C.
KEEP VERBATIM: blackbody(), cell grid, T^4 radiative cooling state in A.r, halo, flicker, shock rings, param roles.
RESCUE: per-cell FFT band read plasmaBuffer[1..8], which is never uploaded (only index 0) → every band 0, ownership dead; now derived from plasmaBuffer[0] bass/mid/treble by band index. Top-level JSON param names (Distortion/Pulse Speed/...) contradicted the real roles → renamed to x-meta names.
ADD:
  1. Cell-to-cell conduction — each cell reads its 4 neighbour cells' centre temperatures from C and relaxes toward their mean, so a hot cell bleeds heat across the array (heat fronts walk from the cursor).
  2. Arc breakdown — when a cell and its hottest neighbour both exceed a breakdown temperature, a jittering filament arc strikes between their centres (replaces the always-horizontal treble line, still treble-gated for brightness).
FORBID: ripples overlay, palettes, spring.
A PACKING: unchanged (T/20000, spot, luma, osc).
