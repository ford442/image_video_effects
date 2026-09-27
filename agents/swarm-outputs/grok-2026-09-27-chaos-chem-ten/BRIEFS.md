# Grok batch — chaos / chem generative ten — Idea Cards

Written **before** WGSL. Six files already had dated cards; those mechanisms stay. Two new ideas each. Aurora, bioelectric pulse, brutalist monument, alien flora ecosystem, and chronos labyrinth had no `Ideas:` line.

---

SHADER: gen-3d-sierpinski-chaos
IDENTITY: chaos-game point cloud of a 3D Sierpinski tetrahedron
KEEP VERBATIM: midpoint iteration; four tet vertices; attractor-biased die; repeat-vertex corner flares; iteration-age hue; opposite-face chroma; point density / rotation / size / color-shift params
ADD:
  1. Midpoint cavity — darken samples whose distances to all four vertices are nearly equal, so the open tet hole reads as hollow
  2. Edge filament — brighten samples that sit near one edge (two vertices much closer than the other two)
FORBID: a new fractal, springs, replacing the chaos game with an SDF tet
A PACKING: ACES display RGBA

---

SHADER: gen-belousov-zhabotinsky
IDENTITY: Oregonator spiral and target waves
KEEP VERBATIM: newA / newB update; refractory-tail shading; pacemaker epsilon gradient; raw A and B detail writes; saved reaction / diffusion / feed params
ADD:
  1. Phase hue — tint the body by atan2 of activator deviation vs inhibitor so the chemical phase cycles around the spiral
  2. Annihilation cusp — a short white flash where the wavefront is high and lapA is near zero (fronts meeting)
FORBID: Gray-Scott replacement, ACES on stored fields, new springs
A PACKING: raw sim (newA, newB, waveFront, alpha) + B detail (lapA, lapB, oxidized, waveFront^2)

---

SHADER: gen-buddhabrot-aura
IDENTITY: escaping-orbit Buddhabrot density with an aura
KEEP VERBATIM: z²+c accumulation; Nebulabrot early/mid/late channels; anti-Buddhabrot interior dust; orbit trap; orbit threshold / density / zoom / aura params
ADD:
  1. Min-distance spine — a thin bright filament at the running minimum |z − trap| inside the existing orbit trap
  2. Escape argument — tint the escape sample by atan2(z) so the nebula gains angular streaks, separate from the time bins
FORBID: a Mandelbrot interior fill as the picture, new springs
A PACKING: ACES display RGBA

---

SHADER: gen-cellular-automata-tapestry
IDENTITY: Gray-Scott reaction-diffusion grown on the video
KEEP VERBATIM: feed/kill/diffusion params; 3×3 kernel; kill-rate isochrones; diffusion-anisotropy striping; mouse nutrient inject; raw A (nextA, nextB, 0, 1)
ADD:
  1. Spot nucleus — a small bright core where B is high and lapB < 0, distinct from the isochrone bands
  2. Substrate halo — a depleted-A ring around spots so consumed substrate reads around each colony
FORBID: reading C.rgb as color (C is chemical state); plasmaBuffer[1..255] as a LUT; u.config.y as dt; new springs
A PACKING: raw sim (nextA, nextB, 0, 1)

---

SHADER: gen-chromatic-acid-drip
IDENTITY: pH-colored falling metaballs and chromatic drips
KEEP VERBATIM: metaball field; universal-indicator ramp; coffee-ring meniscus; gravity-biased blob fall; intensity / flow / scale / color-shift params
ADD:
  1. Drip neck — a thinner waist just above each falling blob (Plateau–Rayleigh), using the existing gravity offset
  2. Channel lag — the R and B drip trails slip further down-gravity than G
FORBID: replacing metaballs with a fluid solver, new springs
A PACKING: HDR display RGBA in A; ACES on writeTexture only

---

SHADER: gen-alpha-aurora
IDENTITY: four curl-warped Gaussian aurora curtains over a star field
KEEP VERBATIM: four bands; spectralColor; curl deformation; mouse altitude and temperature; band speed / temperature / density / glow params
ADD:
  1. Curtain rays — vertical striations inside each band, stronger where the curl’s vertical component is large
  2. Lower border — a sharper greener hem on the bottom of each Gaussian; the top stays diffuse
FORBID: new springs; replacing spectralColor with an IQ palette; extraBuffer[0] (bass envelope moves to [133])
A PACKING: pre-ACES display RGBA; ACES on writeTexture

---

SHADER: gen-bioelectric-pulse
IDENTITY: wandering radial bioelectric pulses on an fbm vein substrate, with a kick ring and phosphor trail
KEEP VERBATIM: rdPulse centers; megaPulse kick; vein fbm; pulse count / speed / width / hue; kick envelope at extraBuffer[133..134]
ADD:
  1. Recovery trough — darken the trailing half of each sine ring so the membrane has a refractory gap
  2. Biphasic spike — rising half of the existing phase stays cyan, falling half goes magenta
FORBID: new springs; filtering sample of dataTextureC (exact textureLoad); ACES inside the stored trail
A PACKING: unmapped phosphor trail RGB in A; ACES on writeTexture only

---

SHADER: gen-brutalist-monument
IDENTITY: repeated concrete pillars and a ground plane around a floating brass octahedron in fog
KEEP VERBATIM: pillar grid; ground; octahedron artifact; sun / fog / artifact scale / complexity; orbit camera
ADD:
  1. Board-form — horizontal formwork lines and tie holes on concrete (mat 1), not on the brass artifact
  2. Ledge stains — vertical dark streaks on vertical concrete, stronger when the sun is high
FORBID: new springs; click shockwaves; staining the artifact
A PACKING: pre-ACES display RGBA; ACES on writeTexture

---

SHADER: gen-alien-flora-ecosystem
IDENTITY: a field of stemmed caps whose color is a two-species competition, with toxin in the soil
KEEP VERBATIM: stem and cap SDFs; s1/s2 competition; toxin and resource; SSS; mouse nurture; audio seasons; vegetation / sway / glow / color-shift params
ADD:
  1. Cap vs stem zoning — species 1 stains the cap, species 2 the stem
  2. Allelopathy ring — a dead halo in the soil at the cell edge where toxin is high
FORBID: gill ridges or spore motes copied from gen-alien-flora; new springs
A PACKING: pre-ACES display RGBA; ACES on writeTexture

---

SHADER: gen-chronos-labyrinth
IDENTITY: a shifting four-type Escher maze with masonry, bridges, and temporal rift spheres
KEEP VERBATIM: four structure types; masonry course; bridges; rift spheres; existing spring at extraBuffer[133..138]; click shockwaves; rift-echo packing
ADD:
  1. Stair nosing — a darker lip on each tread of the existing staircase boxes
  2. Shift ghost — a faint second sample of the cell SDF a small step earlier in shift_time, so the rotation leaves a wall smear
FORBID: new springs; crystal-labyrinth time-faults or hour caustics; replacing the four structure types
A PACKING: rift echo, depth, material, alpha (not display color)
