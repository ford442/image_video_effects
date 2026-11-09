# retro_phosphor_dream — Idea Card (opus/batch-23, fork B)
Identity: CRT phosphor filter (triads, scanlines, barrel, afterglow, degauss click). Kept.
Rescue: degauss trigger stored in extraBuffer[133] (does not persist) -> click dead; now dataTextureA texel (0,0).a. Mouse read zoom_config.xy/px (x=time) -> curvature crept with time; now .yz uv.
1. P22 split-decay trails — per-channel persistence (G 0.93, R 0.86, B 0.74), green-amber trails behind motion.
2. Beam halation bleed — over-threshold energy from previous frame bleeds ±8 px horizontally through the faceplate.
3. Phosphor burn-in ghost — per-texel alpha integrates long-run luma (~20 s); worn phosphor shows as brown-amber ghost.
Dropped: degauss purity blotch (collides with crt-scanline-damage).
