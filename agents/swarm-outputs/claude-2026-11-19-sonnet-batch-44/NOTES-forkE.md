# NOTES fork E — conv-gabor-texture-analyzer, conv-difference-of-gaussians-cascade (second pass)

## conv-gabor-texture-analyzer
SHADER: conv-gabor-texture-analyzer
IDENTITY: 4-orientation Gabor bank colouring texture by orientation, mouse-rotated bank, psychedelic palette
KEEP VERBATIM: gaborResponse kernel loop, 4 orientations, palettes, grain, CA, ripple bursts, params, A packing
ADD:
  3. orientation coherence — (max−min)/(max+min) over the 4 responses; isotropic regions fall toward muted source luma (floor 0.5), oriented texture keeps full hue; mids scale it
  4. line-vs-edge phase classing — gaborResponse now returns the (even, odd) pair; at the dominant orientation, even-dominant = light/dark ridge, odd-dominant = bipolar edge relief; treble scales it
FORBID: springs, new palettes, non-Gabor overlays
A PACKING: ACES display RGBA (unchanged)
RESCUE: HEAD was near-uniform grey (stdL 0.029 at 192 synthetic): it blended the four phase-shifted palettes linearly by magnitude, which averages to grey → weights raised to the 4th power (normalised by the max) so the dominant orientation's hue wins. stdL is now 0.079.
Diff vs HEAD @192: 84% px >12/255 (mostly from the rescue).
Timing (load 12, min-of-drained, 3 interleaved rounds): 0.78/0.66/0.84 → ≤1.0× (the extra odd term is already computed by HEAD; it was discarded in sqrt).

## conv-difference-of-gaussians-cascade
SHADER: conv-difference-of-gaussians-cascade
IDENTITY: 4-scale DoG edge glow with palette colouring, XDoG ink, zero-crossing ridges
KEEP VERBATIM: gaussianSample/dog, scale chain, emphasis/mouse focus-pull, XDoG, zero-cross, CA, params, A packing
ADD:
  3. scale-selected blob polarity halos — argmax |dog_i| picks the characteristic scale (coarser = softer gain), sign = polarity: light blobs warm, dark blobs cool; bass swells it
  4. DoG-gradient relief — gradient from the dogN/dogE that HEAD already samples, lit from the pointer direction (mids scale it); no extra samples
FORBID: springs, palettes, generic glow
A PACKING: ACES display RGBA (unchanged)
RESCUE: none (HEAD renders).
Diff vs HEAD @192: 4.6% px >12/255 (edge/blob-localised by design).
Timing (load 13, 4 interleaved rounds): 0.96/1.17/0.87/1.33 → median ≈1.07×. The `if` argmax was switched to `select`s (first read 1.25–1.55× with the ifs, noisy).

## Gates
verify-naga-wasm --files: 2/2 valid. audit_dead_sliders: no hits. JSON: descriptions appended only, params byte-exact. Not done: real-GPU look, upgrades:record and shader lists (coordinator). Not committed.
