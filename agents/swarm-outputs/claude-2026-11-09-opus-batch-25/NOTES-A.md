# NOTES — fork A

## scan-distort-gpt52 (1st Ideas pass)
Kept: barrel bend, warpedFBM displacement, 3-band hashed jitter (lineId now on unstretched baseLines so band identity is unchanged), scan head/tear runner/pointer band/click shocks, RGB tear, grade chain, params.
Ideas in diff: (1) band-seam ghost echo (seam12/seam23 → ghost sample mixed in); (2) warp-stretched scanline pitch (pitchStretch from domainWarp); (3) scan-head trailing wake (headWake, one-sided exp behind headPhase).
Floor: A was never written → ACES display RGBA now stored; grain-negative clamp before ACES.
Render (320px, defaults): meanL 0.625 (HEAD 0.618), meanA 0.985, no NaN; ghost double images visible at band seams.

## chroma-vortex-coupled (2nd pass)
Rescue: extraBuffer[133..138] spring is zeroed each frame → mouseVel≡0 → pointer never stirred the fluid. Removed; stirring is stateless.
Kept: advection, A packing [vel, vorticity, density], Cauchy ribbons, cavitation glints, strain birefringence, params.
Ideas in diff: (1) tangential vortex-eye injection (spin sign from Twist); (2) bass-pulsed eye breathing (eye dye + radial puff); (3) low-pressure core lens (corePressure pulls sample to eye, dims 25%).
JSON: features "spring-dynamics" (dead) → "audio-reactive".
Render (30 frames, mouse held, bass 0.6): core now churns with birefringence fringes/glints (HEAD core static); meanL 0.472 vs 0.477; meanA 0.79.

## temporal-phosphor-burn (2nd pass)
Rescue: A stored graded display (bloom×mask×ACES) that C decayed back in → re-grade loop, image washed toward pink-white (meanL 0.49 → 0.65 in 30 frames). A now = phosphor energy before scanline/mask/ACES → 0.52 with beam burn, colours hold.
Kept: per-channel decay, history ring + age-softened afterglow, beam/click burns, halation, scanline bloom, FBM mask, params.
Ideas in diff: (3) static burn-in ghost (wear EMA in A.a, stored as -(wear+0.001) sentinel so a previous shader's alpha isn't read as wear); (4) EHT raster sag on bass (sagUV).
Burn-in needs a long static hold followed by a dark scene — not verifiable in the minirender; real-GPU check pending.
A packing: [energy RGB 0..1.5, -(wear+0.001)].
