SHADER: gen-image-pixel-detonation (2nd pass)
IDENTITY: photo's bright pixels/edges launch fireworks whose sparks carry source colour; picture dissolves into trails
KEEP VERBATIM: existing ideas (shock rings, depth-staggered launches), A packing, params, mouse barrage
ADD:
  3. Pixel-tile shrapnel — sparks drawn as hard-edged squares (Chebyshev) that grow slightly as they fall
  4. Launch craters — photo hollowed under a launching probe, healing as the burst fades
RESCUES:
  - apogee +0.6..0.9 short-axis units → nearly every shell burst above the frame; capped inside
  - fireworks mixed at 30% into the trail → now added on top (trail still records them)
  - probes spanned ±0.8×±0.6 → launched from off-frame clamped edges; now aspect-aware in-frame
  - period cycle*3 → shells idle >half the time; now cycle*1.6
Stats (256px, defaults): t=7 HEAD no visible burst (meanL .281) → shock rings + tile shrapnel (.311); click+audio .458.
Open: crater subtle on test image; ACES trail feedback re-tone-maps display C (pre-existing).
