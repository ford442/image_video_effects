# NOTES fork C — cyber-terminal-ascii, pixelation-drift (second pass)

## cyber-terminal-ascii
IDENTITY: scrolling phosphor glyph grid + hex decode lens. KEEP: glyph SDFs, hex font, typewriter row, bit-error flicker, params.
ADD: (4) line-buffer misalignment — a band of rows drifts down the screen (mids widen it, bass adds slip) and samples its picture a whole number of cells sideways, amber-tinted in green mode; glyph grid itself unchanged.
(5) reverse-video selection rim — ring of cells just outside the decoder lens draws inverted (filled cell, glyph cut out), wider while held.
Rescue: none found (HEAD renders fine). Cost: ALU only, no new taps.

## pixelation-drift
IDENTITY: drifting audio-sized mosaic with block average, palette quantisation, drift-lit bevel. KEEP all three + params.
ADD: (4) quadtree detail split — tiles whose 4-tap interior luma variance exceeds a threshold (treble lowers it) subdivide into nested half-size tiles; flat areas stay coarse.
(5) block-ordered dither — 4x4 Bayer threshold indexed by block on the coarse palette (dither=0 reproduces HEAD rounding).
Rescue: dead extraBuffer[133..138] mouse spring removed (zeroed every frame; gid 0 raced the other invocations) → direct pointer. Not fixed: C persistence mixes ACES-display prev into pre-ACES colour then re-tonemaps (small, 0.12 weight).
Cost: +4 taps always, +12 taps on split tiles.

Gates: verify-naga-wasm --files 2/2 valid; SwiftShader render @192, no NaN, no validation errors. Diff vs HEAD @192 (>12/255): cyber 3.8% (rim; band was off-frame in the capture), pixelation 22.3%.
Timing: load 10–14 (other forks running) made frameMs pure noise (head/new swung 16–143 ms in both orders); no reliable ratio. Coordinator should re-time on a quiet box.
JSON descriptions appended. Not done: real-GPU look, shader lists (coordinator).
