# Grok simpler generative leftover (10) — Idea Cards (2026-09-27)

Contract: `docs/SHADER_UPGRADE_BATCH.md`. Second-pass: two **new** native
ideas each, appended on top of existing 09-09 / 09-14 / Batch-18 cards.
Identities kept. Saved params byte-exact. No new extraBuffer springs.
User override: do not skip already-carded files.

Underscore-backed URLs: `gen_rainbow_smoke`, `gen_orb`, `gen_kimi_crystal`,
`gen_kimi_nebula`.

---

SHADER: gen-rainbow-firefly-dance
IDENTITY: rainbow orbital firefly swarm with velocity-stretched comet tails,
mouse attraction, click mini-swarms, swirl-advected phosphorescent trails
KEEP VERBATIM: Intensity / Speed / Scale / Color Shift; orbit + turbulence
motion; comet tails; click ring heads; C history advection; slider roles
ADD (2 native ideas):
  1. Photinus flash codes — per-fly hash duty cycle so orbs blink (dark
     interval, not constant glow); bass slightly shortens the dark
  2. Courtship antiphase — even/odd flies flash delayed vs leaders; held
     mouse tightens pairing (stronger attract + tighter phase lock)
FORBID on this file: extraBuffer spring; IQ palette as the picture; ACES into A
A PACKING: linear HDR history in A; ACES on writeTexture only
FLOOR (not an idea): add matching four-entry `params`; tag upgraded-rgba

---

SHADER: gen-rainbow-icosahedron-cascade
IDENTITY: nested icosahedral wireframe shells with spectral edges, golden-angle
yaw per shell, silhouette orbit-trap, mouse orbit
KEEP VERBATIM: 12-vert / 30-edge SDF; golden-angle yaw; silhouette trap;
mouse yaw/pitch; shell_count / shell_spacing / edge_glow / hue_drift
ADD (2 native ideas):
  1. Dual dodeca vertices — 20 triangle-centroid sparks per shell (icosa dual)
  2. Click shell pulse — ripple age scales that shell's radius/thickness so
     clicks breathe the cascade (mouse orbit stays)
FORBID on this file: filled geodesic ball rewrite; new springs
A PACKING: linear HDR history in A; ACES on writeTexture only
FLOOR (not an idea): header currently claims ACES-in-A while storing pre-ACES —
tell the truth

---

SHADER: gen-rainbow-smoke (gen_rainbow_smoke.*)
IDENTITY: multi-scale curl-noise smoke with vorticity confinement, buoyancy,
Rayleigh edge scattering, Mie cores, spectral FFT emitters
KEEP VERBATIM: CFL clamp; spectral emitters; click density/heat; extraBuffer
[133..136] spring stir; raw A (velocity, density, temperature); existing B write
ADD (2 native ideas):
  1. Vortex-ring clicks — toroidal velocity around each ripple (smoke rings)
     in addition to the existing radial burst
  2. Kelvin–Helmholtz billows — shear along the density-gradient edge wrinkles
     the smoke/air interface
FORBID on this file: display-history sparkle rewrite; ACES on stored fields
A PACKING: raw (velocity.xy, density, temperature) in A; display ACES on write

---

SHADER: gen-orb (gen_orb.*)
IDENTITY: Lorenz strange attractor streams (RK4), lobe-switch sparks, unstable
fixed-point eyes C±, held-drag camera, click butterfly kicks
KEEP VERBATIM: sigma / rho / beta / trail_persistence; RK4; lobe-switch sparks;
C± eyes; held orbit; click kicks; display A
ADD (2 native ideas):
  1. Lyapunov stretch sheen — filament brightness/width from local |Δpos|/dt
     so mixing stretches glow thin
  2. Poincaré z=ρ−1 flashes — brief glints when a trajectory crosses the plane
     of the fixed points
FORBID on this file: extra streams/steps; new springs
A PACKING: ACES display RGBA in A

---

SHADER: gen-newton-fractal
IDENTITY: Newton basins of z^n−1 with orbit traps, convergence-order sheen,
damped-Newton relaxation from clicks/held, RD packed in alpha
KEEP VERBATIM: zoom / polynomialDegree / iterationPrecision / boundaryDistortion;
damped-Newton; conv-order sheen + isochrones; A.a RD packing helpers
ADD (2 native ideas):
  1. Newton-flow striations — atan2(lastDz) bands inside basins (the Newton
     vector field)
  2. Wandering-orbit dust — high orbitMin despite convergence (Julia-adjacent
     itineraries) as fine spectral dust on basin walls
FORBID on this file: Mandelbrot/Julia rewrite; changing A.a pack
A PACKING: ACES display RGB in A; A.a = floor(convAlpha*255)/256 + rd*(0.999/256)

---

SHADER: gen-percolation-threshold
IDENTITY: Bernoulli site lattice, L–R spanning cluster, conduction pulses on
the backbone, critical opalescence, held/click doping
KEEP VERBATIM: 80×60 lattice in A; epoch flood; conduction pulses; opalescence;
held doped disk; click doped rings; four-channel lattice pack; no extraBuffer
ADD (2 native ideas):
  1. Red-bond bottlenecks — spanning sites with two occupied neighbors glow as
     current constrictions
  2. Finite-cluster mass fade — non-spanning clusters dim by local degree
     (small blobs milkier, not jewel-bright)
FORBID on this file: extraBuffer[0..] labels; changing lattice pack; wrap flags
A PACKING: lattice (label, epoch, touchL, touchR) in [0..79]x[0..59]; ACES
display RGBA elsewhere

---

SHADER: gen-neon-snowfall
IDENTITY: Nakaya hex plates ↔ stellar dendrites, habit-dependent fall, click
gusts, held eddy, bass_env on extraBuffer[133]
KEEP VERBATIM: flakeDensity / fallSpeed / chroma / streak; snowCrystal SDF;
terminal velocity; flutter glint; click gust / held eddy; [133] bass_env
ADD (2 native ideas):
  1. Riming → graupel — toward the bottom of the frame, dendrites plump into
     lumpy spheres (wet-growth)
  2. Snowbank — C history piles at the bottom with wind-lean from the existing
     gust vector
FORBID on this file: 22° halo theft from kimi-crystal; new extraBuffer slots
A PACKING: ACES display RGBA in A

---

SHADER: gen-neon-lotus
IDENTITY: layered neon lotus petals, Nelumbo receptacle with Vogel carpels,
lotus-effect beads, click pond-ripples
KEEP VERBATIM: petal_count / bloom / speed / glow_scale; petal SDF; Vogel
carpels; stamen fringe; midline beads; pond-ripple shake
ADD (2 native ideas):
  1. Nyctinasty — petals fold on a slow circadian of speed; bloom slider is
     still max open; bass + held ease them open
  2. Peltate lily pad — circular pad under the blossom with radiating veins
     and a central stem, so the lotus sits on a pond
FORBID on this file: a different plant; inventing C feedback
A PACKING: ACES display RGBA in A

---

SHADER: gen-kimi-crystal (gen_kimi_crystal.*)
IDENTITY: odd-row hex ice grid, Nakaya plate→dendrite, Fresnel/Beer ice,
22° halo + parhelia around the mouse sun
KEEP VERBATIM: density / purity / growth / thickness; hex grid; Nakaya SDF;
Fresnel/Beer; 22° halo + parhelia; click nucleation
ADD (2 native ideas):
  1. 46° halo — second ring from prism min-deviation through 90° ice paths
     (weaker, outside 22°)
  2. Light pillars — vertical glints from plate-habit cells (diamond-dust)
     stretched along the sun's x, distinct from sundogs
FORBID on this file: snowfall graupel clone; extraBuffer springs
A PACKING: ACES display RGBA in A

---

SHADER: gen-kimi-nebula (gen_kimi_nebula.*)
IDENTITY: mouse O-star, Strömgren ionization ([OIII]/Hα/[SII]), dust extinction
and bright rims, Sedov click shells
KEEP VERBATIM: intensity / speed / scale / detail; Rs zones; 1/λ extinction;
bright rims; Sedov shells; four slider roles
ADD (2 native ideas):
  1. PDR skin — thin UV/PAH layer just outside Rs (photodissociation region)
  2. EGGs / cometary globules — dense dust knots with tails pointing away
     from the star (opposite of the existing bright-rim faces)
FORBID on this file: galaxy/spiral rewrite; fake extraBuffer audio
A PACKING: ACES display RGBA in A
