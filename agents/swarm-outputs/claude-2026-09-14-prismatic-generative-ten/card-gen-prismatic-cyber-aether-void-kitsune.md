SHADER: gen-prismatic-cyber-aether-void-kitsune
IDENTITY: Raymarched cybernetic kitsune (capsule body, hex-rune armor, octahedral shoulder crystals) with nine aether plasma tails, orbiting prismatic shard swarm, auroral torus rings, kaleidoscopic volumetric storm backdrop.
KEEP VERBATIM: SDF + 2D geometric libraries, map body/tails/shards/rings, calcNormal, adaptive raymarch, body/shard/ring shading, kaleido storm, glow bloom, vignette.
ADD (2 native ideas):
  1. Kitsune-bi fox-fire: nine teardrop onibi flames hovering at the tail tips (tip position from shared tailDir), rendered as analytic Gaussian line integrals along the camera ray, occluded by the SDF hit; blue-white core -> violet rim, per-tail treble flicker, bass gain; held mouse draws the flames toward the cursor.
  2. Nine-tail thin-film spectrum: nearest tail index encoded in mat id (2.0 + idx*0.1); each tail is a film of thickness 280+45*idx nm (rippling along z, mids gain) with interference colour from optical path 2*n*d*cos(theta_t), blended over the magenta/orange plasma by Fresnel.
FLOOR FIXES: Reinhard replaced with ACES (display gamma kept after ACES); audio clamped 0..1; mouse-held added (Current Warp pull x2.2 while held + onibi drift); click ripples added (u.ripples loop to min(config.y,50): thin-film fox-fire flare ring); alpha now semantic (SDF coverage on hit, emissive density of fox-fire/glow/ripples in the void) instead of luma*0.7+0.2; same RGBA to writeTexture and A; header replaced; uniforms comment lists slider names; material tests use floor(mat) instead of ==; JSON features key + params array added. No C/extraBuffer use (none needed).
FORBID: dataTextureB writes, extraBuffer reads, plasmaBuffer beyond [0].xyz, changing updatedParams.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x,y,z,w live
