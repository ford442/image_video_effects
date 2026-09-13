# Grok-2 batch — mid-complexity generative (10) — Idea Cards

Written **before** WGSL. Identity is the **current kernel**. Two native ideas each. No spring+ripple+IQ stamp. No new extraBuffer slots.

Date: 2026-09-13

---

SHADER: gen-hyper-bismuth-clockwork
IDENTITY: infinite grid of interlocking stepped-hopper bismuth crystals rotating as clockwork, iridescent metal, magnetic cursor, toothed click shocks
KEEP VERBATIM: complexity / clock_speed / iridescence / grid_density; sdBismuthStep + KIFS + gear boxes + frames; magnetic pull; gearShock clicks; ACES display A; no extraBuffer writes
ADD (2 native ideas):
  1. Hopper terrace ridges — extra iridescent specular on the boolean step-cuts inside sdBismuthStep (real hopper crystals are terrace-faced)
  2. Escapement mesh flash — neighboring-cell gear teeth spark when gearPhase crests (clockwork meshing, not a generic sparkle)
FORBID on this file: extraBuffer springs; replacing hopper/clockwork with a different crystal; IQ palette as the look
A PACKING: ACES display RGBA in A (HEAD)

---

SHADER: gen-hyper-dimensional-bismuth-matrix
IDENTITY: hopper-step bismuth lattice with KIFS cores, quantum mouse disruption, volumetric fog, bass envelope
KEEP VERBATIM: crystal_complexity / iridescence_shift / growth_rate / disruption_radius; extraBuffer[133] bass envelope; hopper + KIFS + stairs + frames; click crystalShock; ACES display A
ADD (2 native ideas):
  1. Twin-boundary misfit — glow where hopper SDF ≈ KIFS SDF (crystal twin plane at the smin blend)
  2. Stair-riser rainbow — iridescence phase keyed to the hopper stair floor index (each riser a different film thickness)
FORBID on this file: new extraBuffer slots; springs; rewriting as clockwork
A PACKING: ACES display RGBA in A (HEAD)

---

SHADER: gen-hyper-dimensional-tesseract-labyrinth
IDENTITY: flying through a domain-repeated 4D-rotated box-frame labyrinth with glassy faces and emissive edges
KEEP VERBATIM: tesseract_complexity / edge_glow / warp_field / fly_speed; rotate4D XW+YZ; foldShock clicks; fly camera; ACES display A
ADD (2 native ideas):
  1. W-slice ghost — a fainter second box-frame offset by the unused 4th coordinate (the tesseract’s W shadow)
  2. Cell-face corridors — extra glow on the three midplanes of the projected cube (Escher corridor lines)
FORBID on this file: springs; replacing tesseract with gyroid (that is gen-hyper-labyrinth)
A PACKING: ACES display RGBA in A (HEAD)

---

SHADER: gen-hyper-refractive-rain-matrix
IDENTITY: falling capsule raindrops that smin-merge, refract the sky, mouse-repel, click caustics
KEEP VERBATIM: rainDensity / dropSpeed / fluidViscosity / stormIntensity; capsule + neighbor smin; raw HDR A, ACES on write only
ADD (2 native ideas):
  1. Rain-streak tail — a thinner capsule behind each primary drop (real rain has a fall streak)
  2. Primary bow caustic — angular rainbow ring around the drop at ~42° (rain optics, not a costume palette)
FORBID on this file: springs; replacing rain with a different fluid; writing ACES into A
A PACKING: raw HDR refractive rain display RGBA in A (HEAD)

---

SHADER: gen-hyperbolic-crystal-symbiosis
IDENTITY: competing crystals on a Poincaré-disk {p,q} tiling with jewel iridescence and growth fronts
KEEP VERBATIM: growthSpeed / competition / curvature / mutation; Möbius translate; hyperbolicTiling + crystalFacet; HDR A
ADD (2 native ideas):
  1. Horocycle growth rings — concentric bands of hyperbolic distance (true hyperbolic circles, not Euclidean rings)
  2. Species takeover — mix jewel hue toward the rival seed when competition is high and the facet border is thin
FORBID on this file: springs; Euclidean Voronoi rewrite; extraBuffer
A PACKING: raw HDR crystal + advected trail RGBA in A (HEAD)

---

SHADER: gen-gravitational-strain
IDENTITY: N wells RK4-lens a starfield; tidal emission; Einstein rings; accretion; held strain runners
KEEP VERBATIM: well-count / well-mass / bend-strength / emission-scale; RK4 geodesics; A = (depth, raySpeed, emEnergy, alpha)
ADD (2 native ideas):
  1. Photon-sphere caustic — thin bright ring at 1.5 Rs (distinct from the existing Einstein ring)
  2. Tidal stretch of background — sample the star field displaced along ∇Φ (tidal deformation of the sky)
FORBID on this file: writing display RGBA into A; extra springs; replacing RK4 with a different lens
A PACKING: potential depth, ray speed, emission energy, semantic alpha (HEAD raw)

---

SHADER: gen-gravito-phononic-accretion
IDENTITY: audio-band point masses accrete blackbody disks and Einstein-lens an FBM gas field
KEEP VERBATIM: mass-scale / body-count / lens-strength / gas-density; per-band bodies + mouse mass; temporal ACES A
ADD (2 native ideas):
  1. Relativistic beaming crescent — disk brighter on the orbital approaching side (Doppler beaming)
  2. Phononic spiral density waves — extra spiral modulation of the FBM gas from the audio phase
FORBID on this file: springs; replacing accretion with a different cosmic shader
A PACKING: tone-mapped temporal display RGB + semantic alpha (HEAD)

---

SHADER: gen-graviton-plasma-lotus
IDENTITY: KIFS-folded lotus petals around a glowing core, sprung gravity lens, click pulses
KEEP VERBATIM: Rotation Speed / Complexity / Bloom Intensity / Gravity Well Strength; extraBuffer[133..138] spring; smin core+petals
ADD (2 native ideas):
  1. Petal-fold veins — glow along the KIFS abs-fold planes (the crease is a lotus vein)
  2. Nectary corona — extra bloom where core SDF ≈ petal SDF (the smin nectar well)
FORBID on this file: new extraBuffer slots; replacing lotus with a different KIFS creature
A PACKING: ACES display RGBA in A (HEAD)

---

SHADER: gen-galactic-aether-crystal-geode-core
IDENTITY: cracked geode shell, inner KIFS chrono-crystals, pulsating plasma core, volumetric gas
KEEP VERBATIM: crystal-density / core-glow / fractal-iterations / gas-density; cellular crack; mouse orbit; ACES display A
ADD (2 native ideas):
  1. Druse sparkle — point glints on the inner cavity wall (geodes are lined with crystals)
  2. Gas convection swirl — angular modulation of the hollow volumetric sample (aether circulation)
FORBID on this file: springs; replacing the geode with a different planet / creature
A PACKING: ACES display RGBA in A (HEAD)

---

SHADER: gen-glacial-aether-quantum-cavern
IDENTITY: raymarched ice cavern with octahedral facets, plasma veins, frost tessellation, thin-film
KEEP VERBATIM: ice-density / plasma-glow / fracture-rate / cavern-scale; materials 0/1/2; 3-point lighting; no extraBuffer
ADD (2 native ideas):
  1. Ablation scallops — sinusoidal shade on ice walls (glacial caves have scalloped melt surfaces)
  2. Meltwater film — extra wet specular on downward-facing ice (melt dripping with gravity)
FORBID on this file: springs; IQ overlay; replacing ice with a different cavern
A PACKING: ACES display RGBA in A (HEAD)
