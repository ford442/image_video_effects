SHADER: hybrid-spectral-decomposed (1st idea pass)
IDENTITY: 4-band frequency decomposition, per-band pixel sorting, spectral palette tints, recomposed
KEEP VERBATIM: Gaussian ring sampling, palettes, hue shift, displacement, click pulse, ripples, beat glitch, A = band lumas
ADD:
  1. Audio-spectrum band EQ — low/midLow/midHigh/high gains ride bass/mids/mids+treble/treble
  2. Band-rotated sort axes — each band sorts at its own angle (0/45/90/135°), mids precess the fan
  3. Threshold-gated streak runs — sortBand walks ≤6 steps while the luma step stays above threshold (real sort streaks)
RESCUES:
  - "audio" read u.zoom_config.x (not audio) → plasmaBuffer[0].
  - Bands were divided by sample count, not weight sums (high band ≈ 0.036·L, dead); DoG used ×0.5 subtraction. Now normalized Gaussians + true DoG that reconstruct source.
  - Gains re-used the 4 sliders a second time and summed to ~5× luma, with no tone map → meanL 1.445 white wash. Now neutral gains + ACES (negatives clamped).
  - Idle mouse (0.5,0.5) painted a permanent colour blob; now 35% unless pressed.
Stats (256px, 20f, t=3, defaults): before meanL 1.445 (wash) → after .613; audio 1.442 → .708; max sliders+audio .719. No NaN.
Open: spectral palette tint is subtler at silence than HEAD's (which was washed out anyway); sort streaks only visible on real edges.
