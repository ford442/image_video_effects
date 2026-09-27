# BRIEFS — grok 2026-09-27 xeno / kimi / holo unused ten

Written before WGSL edits. Creative law: `docs/SHADER_UPGRADE_BATCH.md`.

Kimi files use underscore filenames (`kimi_fractal_dreams.wgsl`, `kimi_nebula_depth.wgsl`, `kimi_quantum_field.wgsl`). `gravito-phononic-accretion` is not `gen-gravito-phononic-accretion`.

## gen-xeno-botanical-synth-flora

IDENTITY: L-system branch fan, leaf SDF, Turing venation, nutrient green and bioluminescent blue
KEEP VERBATIM: Flora Density = growth, Bloom Intensity = branch frequency, Cyber-Circuit Glow = depth-alpha mix, Glow Spread = feather; branchDensity, sdLeaf, turingPattern, lSystemIterate
ADD:
  1. Midrib and lateral veins — drawn on the existing leaf SDF, not a new plant
  2. Conductive filaments — treble lights the existing branch ridges so the synth reads as circuitry on the plant
  3. Held phototropism — branch angle bends toward the pointer while held; click spore spray along the ripple age
FORBID: a new creature, a spring, retargeting the four sliders, IQ palette as the look
A PACKING: ACES display RGBA

## gen-xeno-mycelial-resonance-web

IDENTITY: KIFS hypha raymarch, mouse gravity well, bass swell, Beer-Lambert fog
KEEP VERBATIM: Intensity / Speed / Scale / Mouse Influence as both the SDF (repetition, branch radius, hue, pulse) and the existing primary-control multiply; camera orbit; gravity well. No third meaning. No new spring.
ADD:
  1. Anastomosis bridges — wider smin between successive fold branches
  2. Septal rings — periodic constrictions along each existing hypha
  3. Click inoculation — local thickening for the ripple lifetime, not a shockwave ring
FORBID: a different fungus, spring cursor, shockwave rings as the picture
A PACKING: ACES display RGBA. Exact C load already present.

## gen-zeta-function-landscape

IDENTITY: Dirichlet-eta height field of zeta, hue from argument
KEEP VERBATIM: Sigma Offset, T Range, Height Scale, Term Precision; eta series; 2026-09-15 known-zero rails and |ζ|=1 contours; click refraction of the complex plane
ADD:
  3. Critical-line sheen — a band where a slight real-part tilt crosses σ=1/2, separate from the ordinate rails
  4. Argument-winding ticks — thin contours where arg(ζ) steps
FLOOR: spectral voice leaves extraBuffer[5..12] for plasmaBuffer bins
FORBID: a new spring, replacing the eta evaluator
A PACKING: ACES display RGBA

## kimi-fractal-dreams

IDENTITY: layered burning-ship Julia, spring-morphed c, orbit-trap filaments
KEEP VERBATIM: Intensity / Speed / Scale / Detail roles; spring c in extraBuffer[133..136]; click zoom pulses; IQ trap mix; per-bin treble filaments. [137..138] stay free.
ADD:
  1. Interior lake — pixels that never escape get a slow arg fill, persisted with an exact C load
  2. Fold-crease highlights — brighten orbits that pass the |Re| and |Im| axes the ship already folds
FORBID: a different fractal, a second spring, replacing the IQ mix
A PACKING: ACES display RGBA

## kimi-nebula-depth

IDENTITY: posterized halftone dots plus Sobel ink on the source image. Not a nebula.
KEEP VERBATIM: Dot Size, Edge Threshold, Posterize Levels, Ink Density; the transpiled Sobel loop; spring vignette in extraBuffer[133..138]
ADD:
  1. Rosette screen angle — the existing dot grid is rotated a few degrees
  2. Wet-ink bleed — exact C load of previous ink alpha feathers the paper
  3. Click misregister — the screen shifts locally for the ripple age
FORBID: turning this into a nebula or raymarch, rewriting the Sobel loop, a second spring
A PACKING: ACES display RGBA. Alpha stays ink coverage.

## kimi-quantum-field

IDENTITY: Gaussian wave packets around the pointer, per-bin amplitudes, antinode bloom, held collapse
KEEP VERBATIM: Intensity, Speed, Scale, Detail; packet loop; held-button measurement flashes. No spring.
ADD:
  1. Nodal lines — dark curves where amplitude crosses zero, distinct from the bright antinodes
  2. Click packet — each ripple adds one extra source for its age, same envelope as the existing packets
  3. Decoherence haze — exact C load of the previous display, faint
FORBID: a spring, a new palette replacing the purple/cyan field
A PACKING: ACES display RGBA

## lava-lamp-blobs

IDENTITY: rising metaball wax, blackbody core and halo, melt window, click-injected blobs
KEEP VERBATIM: Blob Count, Rise Speed, Melt, Heat; blobField and clickField; spring mouse in extraBuffer[133..136]
ADD:
  1. Saddle meniscus — extra brightness where the field sits in the melt window and the gradient is low
  2. Cooler wax skin — a thin shell just outside blobShape on the existing blackbody ramp
FLOOR: spring writes only at (0,0). C is textureLoad of previous raw fields, not a filtered color mix.
FORBID: storing display RGBA in A, a new spring
A PACKING: A.rgba = raw (blobShape, blobHalo, heat, alpha). ACES on writeTexture only.

## holographic-crystal

IDENTITY: L∞ holographic crystal, facet phase, tilt, dispersion, held pull, click fronts
KEEP VERBATIM: Facets, Tilt, Interference, Dispersion; square crystal; audio spring in extraBuffer[133..137]; click fronts
ADD:
  1. Facet grooves — dark cuts at integer crystalR so Facets reads as edges
  2. Stepped diffraction orders — Dispersion spreads RGB by facet index instead of a smooth wash
FORBID: a different solid, a second spring, an IQ palette replacing the cosine fringes
A PACKING: ACES display RGBA

## holographic-entropy-vortex

IDENTITY: polar fbm entropy vortex, OkLab palettes, spring pointer, capped click front
KEEP VERBATIM: Vortex Speed, Entropy Scale, Holographic Intensity, Atmosphere Density; spring in [133..136]; click front in [137..138]; existing palettes
ADD:
  1. Atmosphere column — Atmosphere Density drives the existing Rayleigh and Mie helpers from the vortex view angle
  2. Entropy caustics — caustics() folded into the vortex UV, scaled by Entropy Scale
FLOOR: drop workgroupBarrier() after the early return
FORBID: a second palette, a second spring
A PACKING: ACES display RGBA

## gravito-phononic-accretion

IDENTITY: two orbiting centers advecting previous C, prism injection, mouse gravity, click fronts
KEEP VERBATIM: Accretion Speed, Lensing Strength, Material Diffusion, Mouse Gravity Power; audio spring in extraBuffer[133..134]; do not copy the gen- sibling's beaming crescent or spiral density waves
ADD:
  1. Phonon standing ridges — brightness along the flow between the two centers, scaled by Lensing Strength
  2. Accretion shock shell — a thin ring outside each core inject
FORBID: the gen- file's crescent and spiral-density ideas, a pointer spring
A PACKING: ACES display RGBA
