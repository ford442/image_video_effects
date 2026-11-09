# BRIEFS — fork A (written before WGSL edits)

SHADER: scan-distort-gpt52
IDENTITY: FBM-warped barrel CRT image with three hashed jitter bands, roaming scan head, diagonal tear runner, chromatic tear, split-tone/palette grade.
KEEP VERBATIM: barrel bend, warpedFBM displacement, 3-band hashed jitter, scan head/tear runner/pointer band/click shocks, RGB tear, grade chain, 4 param roles.
ADD:
  1. Band-seam ghost echo — where two jitter bands overlap (b1*b2, b2*b3) the picture shows both bands' offsets as a faint double image; the seams of THIS effect's band split become visible.
  2. Warp-stretched scanline pitch — scanline frequency follows the local FBM warp gradient, so lines bunch/spread where the domain warp compresses/stretches the raster.
  3. Scan-head trailing phosphor wake — the roaming scan head leaves a one-sided exponential brightness wake behind its travel direction (stateless, from the same fract phase).
FORBID: springs, IQ palette additions, ripples beyond HEAD's.
A PACKING: none at HEAD (A unwritten) → add ACES display RGBA (C not read).
FLOOR: grain can go negative → clamp before ACES.

SHADER: chroma-vortex-coupled (2nd pass)
IDENTITY: mouse-centred RGB vortex twist whose sampling is displaced by a semi-Lagrangian fluid field stored in A.
KEEP VERBATIM: fluid advection + A packing [vel, vorticity, density], Cauchy ribbons, cavitation glints, strain birefringence, 4 param roles.
RESCUE: extraBuffer[133..138] spring is zeroed every frame → mouseVel≡0 → the pointer never stirred the fluid (only clicks did). Replace with stateless stirring.
ADD:
  1. Tangential vortex-eye injection — fluid gets circumferential momentum around the pointer (sign from Twist), so the field actually spins with the optical vortex.
  2. Bass-pulsed eye breathing — bass kicks inject density and radial pulse at the eye, flushing dye outward along the swirl.
  3. Low-pressure core lens — |vorticity|·density pinches the sample toward the eye and dims it slightly (vortex core rarefaction).
FORBID: new palettes, ripples rework, spring.
A PACKING: fluid transport state [vel.x, vel.y, vorticity, density] (unchanged).

SHADER: temporal-phosphor-burn (2nd pass)
IDENTITY: per-channel CRT phosphor persistence over C + history ring, with beam rows, halation and FBM mask.
KEEP VERBATIM: per-channel decay, history ring loop + age-softened afterglow, beam burn, click burns, halation, scanline bloom, mask, 4 param roles.
RESCUE: A stored the fully graded (bloom×mask×ACES) display and C fed it back → every frame re-graded → image washed to pinkish white in ~30 frames (meanL 0.49→0.65). Store pre-grade phosphor energy instead.
ADD:
  1. Static burn-in ghost — A.a holds a slow EMA of phosphor luma; long-held bright content leaves a faint warm worn ghost visible in dark areas (real CRT burn-in).
  2. High-voltage raster sag — bright bass hits make the raster bloom outward around the centre (EHT sag), scaling the live sample.
FORBID: generic overlays, new spring.
A PACKING: [phosphor energy RGB (pre-scanline/mask, linear 0..1.5), burn-in luma EMA].
