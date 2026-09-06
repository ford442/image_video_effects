# Grok batch — simpler generative / kinetic (10) — Idea Cards

Written **before** WGSL. Native ideas only. Catalog IDs use hyphens; several files are underscore-backed (`gen_grid.wgsl`, `gen_grok4_life.wgsl`, …). Identity is the **current kernel**, not the informal “Focus” label.

Family: generative / kinetic fields. No shared spring+ripple+IQ overlay. Springs/ripples stay only where HEAD already owns them.

---

SHADER: gen-grid (`public/shaders/gen_grid.wgsl`)
IDENTITY: domain-warped FBM lattice with chromatic line edges and recursive moiré at intersections
KEEP VERBATIM: warp / density / thickness / palette sliders; domainWarp; gridLine; mini-grid moiré; existing spring well + click warp; ACES display history in A
ADD:
  1. Anisotropic lattice — Jacobian of the warp thickens H vs V lines so the grid stretches with the field (this is a grid)
  2. Intersection phosphor — joints remember last-frame glow from exact C instead of `floor(time)` sparkle strobe
FORBID: replacing the lattice with a CA or a different fractal; extra IQ overlay
A PACKING: ACES display RGBA (HEAD already stores generated color + alpha)

---

SHADER: gen-grok4-life (`public/shaders/gen_grok4_life.wgsl`)
IDENTITY: two-species SmoothLife (prey A / predator B) with Lotka–Volterra coupling
KEEP VERBATIM: TimeStep / Sharpness / ColourSpeed / InitDensity; toroidal wrap; annular neighbourhood; raw A packing (prey, predator, age, activity); extraBuffer pop/bloom
ADD:
  1. Hunt fronts — extra predation / predator growth on the spatial gradient of B (edges, not bulk)
  2. Prey-edge activity flash — activity channel spikes where |ΔA|+|ΔB| is already high, tinted on the display only
FORBID: Conway 3×3 rewrite; springs; IQ palettes as the look
A PACKING: raw sim (r=prey, g=predator, b=age, a=activity) — do not ACES A

---

SHADER: gen-grok4-perlin (`public/shaders/gen_grok4_perlin.wgsl`)
IDENTITY: stratified erosion terrain (catalog name is Perlin; the picture is sediment + water table). Do **not** reimagine as a Perlin field.
KEEP VERBATIM: erosion / waterline / terrain_scale / wind; hydraulic incision; A packing (erosion, sediment, water, uplift)
ADD:
  1. Bedding terraces — display-only height shelves from existing strata frequency (geology, not a new solver)
  2. Shoreline foam — bright band where waterMask meets slope
FORBID: replacing the terrain solver with generic fbm candy; springs
A PACKING: raw (erosion, sediment, water, uplift)

---

SHADER: gen-grok41-mandelbrot (`public/shaders/gen_grok41_mandelbrot.wgsl`)
IDENTITY: Buddhabrot orbit accumulation (escaping orbits paint the nebula)
KEEP VERBATIM: center/zoom/evolution params; escape-orbit density; linear A accumulation; gliding extraBuffer nav
ADD:
  1. Mandelbrot body — non-escaping `c_pixel` as a dark set silhouette under the nebula (this ID is mandelbrot)
  2. Dwell iso-bands — escape iteration of the pixel’s own c as faint rings (orbit time, not a new fractal)
FORBID: Julia rewrite; springs stamped as the upgrade (nav spring already exists)
A PACKING: linear RGB accumulation + presence alpha (ACES display only)

---

SHADER: gen-grok41-plasma (`public/shaders/gen_grok41_plasma.wgsl`)
IDENTITY: ray-hit gas giant whose bands are spherical harmonics Y(l,m)
KEEP VERBATIM: L1/L2/L3/hue sliders; exact Y coefficients; telemetry A (pattern, storm, limb, valid)
ADD:
  1. Zonal jets — latitude stripes added into the existing harmonic pattern (gas giant, not a new planet)
  2. Persistent storm eye — warm vortex from existing Worley stormMask × a latitude well
FORBID: replacing SH with plasma noise; extraBuffer springs
A PACKING: raw telemetry (pattern, stormMask, limbT, validity)

---

SHADER: gen-grokcf-interference (`public/shaders/gen_grokcf_interference.wgsl`)
IDENTITY: circular membrane / Chladni plate (Bessel modes). Catalog “interference” is this drum, not Young slits.
KEEP VERBATIM: ModeScale / ColourMode / NodeSharpness / ModeCount; J0–J3; audio mode families; A = (u, r, φ, alpha)
ADD:
  1. Radial vs azimuthal node tint — m=0 families vs m>0 families colour the Chladni lines differently
  2. Displacement Lambert — light the membrane by signed `u_total` (a drum surface)
FORBID: optical two-slit rewrite; springs
A PACKING: raw membrane (u_total, r, phi/2π, blendAlpha)

---

SHADER: gen-grokcf-voronoi (`public/shaders/gen_grokcf_voronoi.wgsl`)
IDENTITY: layered Worley F1/F2 cells with thin-film edges
KEEP VERBATIM: density / edge / color / parallax; FBM Worley; A = (cellId, edge, F1)
ADD:
  1. Cell nucleus — glow at primary F1 (site of the feature point)
  2. Crack ridge — extra wall from primary F2−F1 (true Voronoi edge, not only FBM edge)
FORBID: replacing Worley with a different CA; springs
A PACKING: cell id xy, edge mask, F1 (HEAD). Display is ACES; A stays telemetry.

---

SHADER: gen-fourier-epicycles (`public/shaders/gen-fourier-epicycles.wgsl`)
IDENTITY: stacked rotating wheels whose last center is a pen
KEEP VERBATIM: speed / cycle count / rim / trail params; radius∝1/n; A packing (bassEnv, trail.r, trail.g, alpha)
ADD:
  1. Arm segments — glow along the radius from hub to next hub (an epicycle has arms, not only rims)
  2. Pen ink into the existing trail pack — the nib writes the C trail harder than the rims
FORBID: replacing Fourier wheels with a particle galaxy; extraBuffer springs
A PACKING: keep HEAD (bassEnv, trail rb, alpha)

---

SHADER: gen-dragon-curve (`public/shaders/gen-dragon-curve.wgsl`)
IDENTITY: Heighway dragon as a glowing polyline of left/right folds
KEEP VERBATIM: zoom / glow / CA / feedback params; LSB fold rule; existing spring (pointer already owns it)
ADD:
  1. Paper crease — extra energy at the closest fold vertex (`closestTurn`)
  2. Generation thickness — early segments thicker than late ones (the folded strip)
FORBID: more kaleido/Clifford as the upgrade; IQ overlay as the whole look
A PACKING: ACES display RGBA (HEAD)

---

SHADER: gen-de-jong-attractor (`public/shaders/gen-de-jong-attractor.wgsl`)
IDENTITY: Peter de Jong map density + optional hero-orbit tube
KEEP VERBATIM: morph a/b, glow, decay; de_jong iterate; raw A density; existing spring
ADD:
  1. Local stretch tint — splat gain from |p'−p| (map expansion, not a new attractor)
  2. Dwell rings — nearest-iteration index colours the density (orbit time)
FORBID: replacing De Jong with Lorenz; extra springs
A PACKING: accumulated density, hue phase, tube depth, alpha (raw)
