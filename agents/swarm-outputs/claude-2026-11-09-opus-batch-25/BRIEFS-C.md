# Fork C Idea Cards (written before WGSL edits)

SHADER: digital-glitch-explosion
IDENTITY: block-shifted, bit-flipped image with prismatic RGB split around the cursor and ripple shockwaves, smeared through C.
KEEP VERBATIM: block shift + scan tear, prismDisplace per channel, ripple chroma waves, randomBitFlip, posterize-decay, C smear, 4 param roles.
HEAD BUGS (rescue): posterize levels = 16 - time*decay → collapses to 2 levels forever after ~15 s (default looks like 8-colour primaries); plasmaBuffer[1..8] band tint is dead (only [0] uploaded); extraBuffer[133..138] spring is zeroed each frame (dead state).
ADD:
  1. Macroblock datamosh — corrupted blocks drop their "I-frame" and carry C forward along the block shift vector (P-frame smear), the classic codec failure behind block glitch.
  2. Bit-plane slice — some corrupted blocks show a single bit-plane of the byte (bitwise corruption made visible as a 1-bit stencil).
  3. Bass-onset shard explosion — blocks fly radially out from the cursor on bass, with prism dispersion scaling with block speed ("explosion" in the name).
FORBID: IQ palettes, spring cursor, holographic scanlines.
A PACKING: ACES display RGB + glitch energy (a), read back as smear colour + energy.

SHADER: crt-tv-stipple
IDENTITY: barrel-curved CRT with blue-noise jittered RGB triad stipple dots, scanlines, halation, vignette.
KEEP VERBATIM: curveUv, stippleGrille, scanlines, halationGlow, crtVignette, 4 param roles.
HEAD BUGS (rescue): phosphorDecay pow(b, 1/10)/pow(g,1/5) lifts every channel toward 1 → cyan-grey wash; bezel early return leaves A unwritten (stale C); dead extraBuffer spring.
ADD:
  1. Per-channel P22 phosphor persistence — exact C trail with red slow / green mid / blue fast decay (replaces the broken pow "decay").
  2. Rolling hum bar — a soft brightness band rolling up the tube (spatial version of the old uniform humBar).
  3. Convergence error — R and B stipple dots misregister radially toward the corners, scaled by barrel.
FORBID: ripple shockwaves upgrades, palettes, glitch tears.
A PACKING: ACES display RGBA (C read as phosphor colour).
