# NOTES fork A — gen-vortex-cathedral, gen-celestial-aether-seraphim-wings (second pass)

## gen-vortex-cathedral
IDENTITY: spinning gothic arch vortex with sanctum light and god-ray shafts. KEEP: arch/rings/vault/godRays/params. FORBID: generic ripples/palettes.
ADD: (1) incense wisps — curling rising smoke lit only where godRayIntensity is high (haze/mids scale);
(2) votive pane flicker — per-pane hashed candle flicker (treble speeds it) on pier glass and arch/column terms.
Rescue: none (HEAD renders fine). Ablation @192: wisps 21% px >12/255; votive 3.5% single-frame (temporal effect).
Timing (load 30–46, noisy): 0.61–0.97× HEAD.

## gen-celestial-aether-seraphim-wings
IDENTITY: KIFS raymarched ascending fractal wings with lift/stall model. KEEP: map(), lift model, params.
ADD: (1) wing ocelli — iris rings on a 3D cell lattice over the surface, pupils dilate with bass;
(2) downwash wake — history also pulled from texel above (shift 2+bass*4 px), streaming glow below wings (max-combined, only adds).
Rescue: halo "above" was drawn below (screen y down) → centre (0,-0.6).
Timing (load 46, noisy): 0.66–1.52×, median ≈1.14×; added cost is 1 textureLoad + ~15 ALU.
Diff vs HEAD @192: 36% px >12/255.

Gates: verify-naga-wasm --files 2/2 valid. JSON descriptions appended. Not done: real-GPU look, shader lists (coordinator).
