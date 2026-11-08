# gen-chrono-kinetic-fractal-engine (2nd pass, rescue)
Bugs at HEAD: (1) Complexity slider range mismatch. JSON is 0.1..5 (default 1) but the code did i32(x*5)+2, so the default hit the 7-layer clamp. The camera then sat inside a space-filling SDF, giving flat grey (meanL 0.82). It now uses round(x)+2, and deeper layers shrink by 0.72^i so Complexity 5 stays readable. (2) Upside down: uv.y is flipped, and so is mouse y. (3) Wash: the fresnel*iridescence rim is now x0.45 and the orbit-trap glow 0.5→0.25.
Ideas: amber-past temporal depth haze (far layers fade to sepia; mids thicken it); time-dilation lens ring (a chromatic halo at the cursor, radius = Warp Strength, bass pulses it).
Stats (defaults 1,0.5,1,1): before meanL 0.815, std ~0 (flat) → after meanL 0.44, std 0.16. Complexity 5: meanL 0.47.
Concern: the default look changes a lot. HEAD's default was a flat grey screen, so there was nothing to preserve.
