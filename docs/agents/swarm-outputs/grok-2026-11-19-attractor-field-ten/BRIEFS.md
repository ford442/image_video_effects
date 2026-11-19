# Idea Cards — Grok (attractor / field ten, 2026-11-19)

Written before the WGSL edits. Ten shaders the user listed by size. Each card adds **two or three** ideas in the existing main path. Saved `params` stay byte-exact. No shared spring, ripple stamp, or new IQ palette.

Several files already carry an earlier idea pass (wing density, escape spokes, bubble sliders, IFS scaffold, Lenia membranes, physarum veins). This pass deepens that mechanism.

Formula rule: a §12.2 row is newly applied on at most one file here.

- Deep-water dispersion (§12.2D) is the ripple bloom only.
- No other §12.2 row is newly applied. The Lorenz tube's bend is the hero polyline's turning angle: a thin tube's SDF Laplacian is ~1/r everywhere, so it does not separate kinks.

`gen-lorenz-attractor`, `phosphorescent-jellyfish`, `voronoi-dynamics`, `dla-crystals`, `gen-lenia-2`, and `quantum-ripples` still paste the binding header. Migrating them to `#include "_prelude.wgsl"` is infrastructure. It is not an idea and does not by itself bump `Upgraded:`. The idea edits do.

`dla-crystals.wgsl` is the single-pass file at this line count. The catalog id routes to the multipass graph (`dla-walkers` / `dla-render`). This card upgrades the single-pass file. It does not retarget the graph.

```
SHADER: gen-lorenz-attractor
IDENTITY: the Lorenz butterfly as accumulated x-z density, plus one live orbit drawn as a raymarched tube.
KEEP VERBATIM: lorenz_step (σ, ρ, β=8/3, dt=0.010); per-pixel Monte Carlo splat; right-wing in A.r, left-wing in A.g, speed weight in A.b; hero capsule chain; treble mirror fold; sigma / rho / glow / decay roles.
MECHANISM INTERROGATION:
  tactic 2: the butterfly is the lobe switch — the trajectory burns a bridge when x changes sign, and each wing has a dark eye at C±
  tactic 3: the hero orbit is stored only as capsule endpoints; the turning angle between those joints is thrown away
  tactic 6: A stays the three density fields. The bridge is shared density written into both wing channels so it survives the existing feedback
ADD:
  1. Lobe-switch bridge — a crossing of p.x deposits into both wing channels, so the join accumulates as a pale filament
  2. Equilibrium eyes — darken the x-z projection at C± = (±√(β(ρ−1)), ρ−1), the slow spiral centers
  3. Tube bend wear — turning angle at the hero polyline joints (the capsules already built). A kink in the orbit catches a cool highlight. The SDF Laplacian is ~1/r on a thin tube, so it is not the mask
FORBID: a second attractor, a new spring, an IQ palette replacing the lobe palette
A PACKING: raw sim — r=right-wing density, g=left-wing density, b=speed-weighted density, a=display alpha. ACES on writeTexture only
```

```
SHADER: phosphorescent-jellyfish
IDENTITY: a small swarm of glowing bells with tentacles, held-pointer attraction, and a click that startles the nearest jelly.
KEEP VERBATIM: sdBell; tentacleGlow; swarm count / bell size / trail persistence / glow; per-jelly FFT band pulse; jet dart away from the click; HDR trail in A (ACES on display only).
MECHANISM INTERROGATION:
  tactic 2: a real bell lights its muscular margin on the squeeze, and the mouth is a short oral arm under the dome, not another tentacle
  tactic 3: pulse is a sine whose falling half is the contraction; only the radius uses it
  tactic 6: C is HDR color. Read it with textureLoad (the chroma offset becomes a pixel offset). Do not ACES the stored trail
ADD:
  1. Contraction velum — a bright ring on the lower bell margin while the pulse is squeezing
  2. Manubrium — a short, thick oral-arm glow under the bell center, sharing the bell hue
FORBID: a new creature, springs, a second tentacle system, thin-film (the bell is not a soap film)
A PACKING: HDR display RGB + alpha in A (C read as HDR history). ACES on writeTexture only
```

```
SHADER: ripple-bloom
IDENTITY: the source photo under a mouse-centered Huygens ripple, with crest chroma, bloom, and caustic light.
KEEP VERBATIM: three-frequency wavelet loop; ripple / bloom / mouse / color-shift params; crest chroma split; Gaussian bloom; caustic, starburst, grain, radial CA, vignette, grade, anamorphic, lens dirt already in the file. Do not add another cinema overlay.
MECHANISM INTERROGATION:
  tactic 1: the loop already disperses by a linear (1 + 0.15·f) speed bump. Deep water disperses as √(tanh(kd)/k)
  tactic 2: a crest that is rising steepens, and capillary ripples ride that crest
  tactic 6: A already stores (ripple, height, bloomAmount, alpha) and nothing reads it. Read height back with textureLoad
ADD:
  1. Deep-water dispersion — §12.2D phase speed √(tanh(kd)/k) inside the existing three-band loop, using the depth-derived waterDepth
  2. Crest steepening — where height exceeds the previous frame's height, the crest mask sharpens
  3. Capillary ripples — one faster wave, amplitude gated by that crest, added to the same displacement
FORBID: a new spring, a new lens-dirt pass, an IQ palette
A PACKING: raw wave state (signed ripple, height, bloomAmount, alpha). ACES on writeTexture only
```

```
SHADER: gen-dmt-fractal-zoom
IDENTITY: a zooming Mandelbrot / Burning Ship hybrid in a DMT rainbow, with orbit traps, an interior nucleus, and escape-argument spokes.
KEEP VERBATIM: fractalIter (escape |z|²>4, hybrid abs fold); smooth coloring; orbitTrap; interior nucleus; argument spokes; zoom / julia mouse / click warp; intensity / speed / scale / color shift.
MECHANISM INTERROGATION:
  tactic 2: the header already cites the main cardioid and the critical point, and neither contour is drawn
  tactic 3: zMag is returned and only the smooth-iteration logarithm uses it; the equipotential (radial partner of the argument spokes) is unused
  tactic 6: A stays ACES display history
ADD:
  1. Cardioid and period-2 bulb contours — the set's main anatomy, visible while zoomed out, fading as zoomFactor shrinks
  2. Equipotential rings — dark bands of fract(log2|z|) in the exterior, the radial partner of the existing argument spokes
FORBID: a different fractal, a new palette, a spring
A PACKING: ACES display RGBA in A (unchanged)
```

```
SHADER: voronoi-dynamics
IDENTITY: the photo cut into moving Voronoi bubbles; repulsion inflates the pointer cell, attraction oozes sites toward the pointer, edges are iridescent.
KEEP VERBATIM: findNearestCentroid (sites, mouse site, click sites); edge = second − nearest; repulsion bubble; attraction mix; centroid count / repulsion / attraction / edge width. A stays (centroidPos, nearestDist, nearestIdx).
MECHANISM INTERROGATION:
  tactic 3: the search already sees every site and throws away the third distance, which is the triple junction
  tactic 7: the shared border has a direction (nearest site minus second site) and the iridescent hue ignores it
  tactic 6: A packing unchanged. No new field
ADD:
  1. Plateau junctions — where the third distance collapses onto the second, the border brightens into a foam node
  2. Border-oriented iridescence — the existing edge hue gains the angle of the shared border
FORBID: a new spring, thin-film (this batch does not add a soap-film costume), a second cellular noise
A PACKING: raw sim state (centroidPos, nearestDist, nearestIdx) — unchanged. ACES on writeTexture only
```

```
SHADER: dla-crystals
IDENTITY: a single-pass diffusion-limited crystal — pixels freeze onto a seed at the pointer or a click, then color by age, hue, and branch.
KEEP VERBATIM: A = (frozen, age, hue, branchId); ripple and mouse seeds; stickiness as the freeze probability; neighbor freeze test; walker speed / attraction / stickiness / branch angle roles.
MECHANISM INTERROGATION:
  tactic 1: DLA screens fjords. The neighbor test returns a max, not a count, so tips and pockets look the same
  tactic 2: dendrites prefer a crystallographic angle. Branch Angle is stored as a hue and does not bias the stick
  tactic 3: attractStrength and walkerSpeed are computed and then discarded
  tactic 6: C is the frozen map. Read it with textureLoad. Audio is plasmaBuffer[0], not zoom_config.x
ADD:
  1. Tip screening — few frozen neighbors stick more and glow as tips; crowded fjords stick less
  2. Branch-angle facets — stick probability peaks on a 2-to-6-fold angle set by the existing Branch Angle slider
  3. Attraction reach — walker speed widens the search, attraction strength raises the stick gate and the approach glow (both sliders were dead)
FORBID: replacing this freeze map with the multipass walker ring, a new palette, a spring
A PACKING: raw sim (frozen, age, hue, branchId). ACES on writeTexture only
```

```
SHADER: gen-chaos-game-ifs
IDENTITY: the Sierpinski chaos game — three maps, last-vertex tint, radial hole, iterate age, median scaffold, vertex glints, contraction echo, and a small raymarched crystal.
KEEP VERBATIM: ifsPoint three-map contraction; iterations / glow / rings / saturation; scaffold triangle; fixed-point glints; contraction echo; sceneDE crystal; the pointer spring already in extraBuffer[133..138].
MECHANISM INTERROGATION:
  tactic 2: the first removal of the chaos game is the open triangle of the three midpoints, which the radial hole only approximates
  tactic 3: consecutive identical vertex picks (a corner lock) are overwritten by lastPick and never counted
  tactic 6: A stays ACES display
ADD:
  1. Excised midpoint triangle — darken the open set bounded by the three edge midpoints of the scaffold triangle
  2. Corner lock — when successive iterates pick the same vertex, that corner's occupancy tint deepens
FORBID: a different IFS, a second spring, a new sculpture primitive
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: gen-lenia-2
IDENTITY: four-species Lenia — radial kernels, bell growth, predator-prey matrix, growth-field membranes, gel relief.
KEEP VERBATIM: kernel_sample_8; bell growth per species; interaction matrix; membranes at G=0; mass-gradient relief and Beer-Lambert; global growth / kernel radius / speed / cross-mix. A stays the four masses.
MECHANISM INTERROGATION:
  tactic 3: the membrane uses the zero of G(U). The peak of the same bell (the cytoplasm) is thrown away
  tactic 2: negative cross-species terms are the competition. They nudge the update and never mark the overlap
  tactic 6: A stays raw masses. Do not ACES them
ADD:
  1. Cytoplasm cores — where G(U) is near its positive peak, inside a body, a brighter interior than the wall
  2. Competition furrows — overlapping mass with a negative interaction darkens, a gutter between species
FORBID: a new species, a new kernel family, thin-film, a spring
A PACKING: raw sim state (four species masses) — unchanged. ACES on writeTexture only
```

```
SHADER: quantum-ripples
IDENTITY: the photo refracted by interfering ripples — a pointer wave, an opposite-phase twin pair, curl advection, Voronoi cells, and a soft portal.
KEEP VERBATIM: waveField; twin orbit; click superposition (max 8); freq / speed / distortion / color shift; curl, voronoi, rounded-box mask; display history in A.
MECHANISM INTERROGATION:
  tactic 2: the twins are added with opposite sign and the cancellation is only a weaker displacement, never a visible node
  tactic 7: the displacement has a direction. The crest runs perpendicular to it, and the chroma split is still radial from the frame center
  tactic 6: A stays ACES display. C is that history
ADD:
  1. Twin interference nodes — where the opposite-phase pair cancels, a dark fringe; where they align, a bright antinode
  2. Crest-tangent chroma — a short R/B split along the wavefront tangent of the existing displacement, scaled by Color Shift
FORBID: deep-water dispersion (ripple-bloom owns that formula this batch), a spring, a new palette
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: gen-wasm-hls-physarum-swarm
IDENTITY: Eulerian physarum — mass and heading in C.yz, a video-food trail, peristaltic veins, tube shading, fusion knots, spent sheath.
KEEP VERBATIM: semi-Lagrangian mass gather; Jacobian convergence; three-sensor steer; sensor angle / distance / decay / deposit; mouse attraction; A = (trail, mx, my, hue). No extraBuffer.
MECHANISM INTERROGATION:
  tactic 2: a vein that has been abandoned should not redeposit at full rate, and the photo under a spent trail is food that was eaten
  tactic 4: sensor angle is one scalar. A wider fan is a wider vein
  tactic 6: refractory reads the trail and mass already in C, before the deposit
ADD:
  1. Refractory deposit — abandoned tubes (high trail, low mass) cut the deposit that the decay slider already scales
  2. Food exhaust — the source photo under the spent sheath desaturates, the slime has eaten it
  3. Sensor-fan width — the existing sensor-angle slider flattens the tube normal so a wider fan reads as a wider vein
FORBID: a particle redeposit into extraBuffer, vorticity confinement, a spring
A PACKING: raw sim state (trail, mx, my, hue). ACES on writeTexture only
```
