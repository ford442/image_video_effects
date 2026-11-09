# NOTES — fork C (2026-11-09)

Render: minirender_img.mjs with SRC=img (without it readTexture is black), 160px.

## cyber-glitch-hologram
- Ideas: swapped-macroblock seams; depth-slice contour lines; racer projector dropout.
- Rescue: plasmaBuffer[band+1] (indices 1..8 never uploaded) → treble×fringe sparkle.
- meanL 0.458 → 0.474 (audio 0.6/0.4/0.6), meanA ≈ 0.11 unchanged (HEAD alpha is pointer-local by design).
- A packing unchanged (linear smear + alpha). Params byte-exact.

## data-stream-corruption-hdr
- Ideas: glyph phosphor trails (A.g); white-hot packet glyphs + stream-light bloom; corruption frontier seam.
- Rescues: (a) packing lie — HEAD mixed C.rgb (=corruption,0,0) into the picture as "smear"; now A=[corruption, trail, 0, alphaHistory]; (b) bloom thresholded LDR source at >1.0 → slider dead; now gathers C.g emission (bloom 0→1: meanL 0.458→0.465); (c) plasmaBuffer[1..8] dead → treble on frontier.
- JSON: added audio-reactive + upgraded-rgba features, real description. Params byte-exact.
- Both pass naga (prelude expanded). Frontier gradient scaled by resolution.y so seam width is resolution-independent.
