```
SHADER: gen-spectral-ferrofluid
IDENTITY (one sentence): a spectral-palette magnetic fluid whose iso-|B| contour bands and field-aligned FBM spikes
  wrap around a mouse pole plus three orbiting satellite dipoles, with viscous temporal memory.
KEEP VERBATIM: magneticField() radial+angular dipole kernel; mouse primary pole + 3 orbiting satellites
  (weights 1/0.4/0.3/0.2, radii 0.3/0.25/0.35); held-mouse polarity inversion; field-aligned fbm2/fbm3oct spikes;
  sin(fMag*12 - spikes*8) contour bands; ferroPalette/spikePalette; click-ripple disturbances; vignette, field-edge CA,
  gamma then ACES; the four slider roles and mappings (FieldStrength*3+0.5, Viscosity*0.3 memory, SpikeHeight*2+0.2,
  Turbulence); field-strength alpha; A/C raw-field packing.
ADD (native ideas):
  1. Archimedean flux spirals — the dipole kernel's radial(1/r^2):angular(0.5/r) ratio gives exact per-pole
     streamlines theta - 0.5 r = const. Superpose the four poles' stream functions (weights x10 = 10/4/3/2 integer
     windings, so atan2 seams vanish) and ink them as grooves crossing the existing iso-|B| contours: the orbit
     system and the line renderer finally couple into a woven field-line/iso-line net. Density-faded near poles;
     Turbulence slider wobbles the tubes.
  2. Cotton-Mouton birefringence (Michel-Levy tint) — "Spectral" made physical: field-induced delta-n ~ B^2
     (Langevin-saturated) gives optical path difference; per-RGB sin^2(pi*OPD/lambda) interference colours, times
     sin^2(2*alpha) between fieldDir and a slowly turning polarizer, so dark Maltese-cross isogyres sit on every pole.
     Uses the stored fieldDir that previously only drove a 3% chromatic nudge.
  3. Pole meniscus mounds — ferrofluid heaps over each pole (|B|^2 pull, so both polarities heap: held-mouse
     inversion keeps the mound). Analytic Lorentzian height -> analytic normal -> glossy black body + specular ring
     glint and Fresnel rim on the shoulder. Makes the header's "smooth specular normals" claim true (HEAD had none).
FORBID on this file: Rosensweig spike lattice, |psi|^2 filaments/contours (entangled-ferrofluid); labyrinth fingering,
  Taylor cones, dipole chain bridges, LIC iron filings, X-point null flash, Earnshaw wobble (shipped ferro/magnetic
  siblings); swarm/particle/silicate ideas (ferro-silicate-swarm); springs, extraBuffer state, IQ palette stamps.
A PACKING: raw field state, unchanged from HEAD — A = (fMag*0.25, fieldDir.x, fieldDir.y, alpha); C read exactly
  with textureLoad(dataTextureC, coord, 0) as fields. No ACES on A.

SILENT BUGS FIXED:
  - rms read plasmaBuffer[0].w, which the engine always uploads as 0 (audioDepth.ts writes [3]=0): orbit speed and
    turbulence rms terms were dead. Now rms = mean(plasmaBuffer[0].xyz) — identical at audio=0.
  - ripple loop bound u32(config.y) was the lifetime click count (unbounded) indexing ripples[50]: out-of-range reads
    after 50 clicks. Clamped to 50.
NOT CHANGED (noted): bass_env() is called with constant prev, so it is a fixed lerp, not an envelope — kept to preserve
  the look at the saved defaults.
```
