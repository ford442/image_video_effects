# Grok-2 batch — mid-complexity generative (10) — Idea Cards

Written **before** WGSL. Identity is the **current kernel**. Two native ideas each. No spring+ripple+IQ stamp. No new extraBuffer slots.

Date: 2026-09-13

Claimed IDs: `gen-eldritch-tesseract-hive-mind`, `gen-electric-kaleidoscope-storm`, `gen-emergent-calligraphic-ecosystems`, `gen-emergent-script-gardens`, `gen-evolutionary-cellular-gardens`, `gen-feedback-echo-chamber`, `gen-fractal-bioluminescence-spore-network`, `gen-fractal-chrono-dendrite-forge`, `gen-glass-mosaic-liquid-refraction`, `gen-gravitational-ferrofluid-singularity-engine`.

## Skipped (already idea-rich)

- `gen-electric-kaleidoscope-storm` — 2026-09-09 psychedelic ten. Ideas: Lichtenberg afterimage from exact C along the bolt; leader vs return-stroke. HDR trail A.
- `gen-feedback-echo-chamber` — 2026-09-11 ethereal ten. Ideas: harmonic echo ladder at integer 2x spacing taps; standing-wave nodal interference. extraBuffer[133] bass envelope kept.

Do not bump those `Upgraded:` dates.

---

SHADER: gen-eldritch-tesseract-hive-mind
IDENTITY: 4D-rotated tesseract SDF with boolean vein carving, voxel tearing, sentinel swarm streaks, thin-film iridescence, HDR trails
KEEP VERBATIM: tesseract-rotation-speed / swarm-density / voxel-tearing-intensity / iridescence-shift; extraBuffer[133..134] burst envelope; XZ+YW 4D tumble; voxel mat 2; ACES on write only
ADD (2 native ideas):
  1. W-cell hive lattice — a neighboring 4D cube along unused W (this is a hive of tesseract cells, not a lone hypercube)
  2. Sentinel pheromone lanes — weaker radial streaks beside the existing tangential speed-streaks (hive traffic along the spokes)
FORBID on this file: new extraBuffer slots; gyroid rewrite; IQ palette as the look
A PACKING: raw HDR trail RGB + raymarch depth in A.a; ACES on writeTexture only (HEAD)

---

SHADER: gen-emergent-calligraphic-ecosystems
IDENTITY: flow-field glyph clusters colored by Lotka–Volterra flora/fauna, paper vs neon, mouse invasive seeds
KEEP VERBATIM: stroke-density / ink-width / complexity / neon-mode; 3×3 glyphCluster; LV prey/predator; click ink; ACES display A
ADD (2 native ideas):
  1. Brush pressure swell — along-stroke width breathes with a slow sine (real calligraphy pressure, not a new stroke family)
  2. Prey–predator ink chase — flora stroke seeds offset along the flow by predatorBloom (ecosystem pursuit on the page)
FORBID on this file: springs; Gray-Scott rewrite; cloning script-gardens phyllotaxis
A PACKING: ACES display RGBA in A (HEAD)

---

SHADER: gen-emergent-script-gardens
IDENTITY: golden-ratio phyllotaxis (137.5°) calligraphic gardens with overgrowth trails in A.a
KEEP VERBATIM: stroke-density / curvature / garden-scale / ink-neon; PHYLLOTAXIS placement; plantedSeed; persistence from palette
ADD (2 native ideas):
  1. Fibonacci parastichy veins — thinner strokes on the opposing spiral family (τ − 137.5°), the packing a botanist would see
  2. Ligature bridges — a short brush from each cluster toward its +X neighbor (script letters connect)
FORBID on this file: springs; Lotka–Volterra costume from the sibling shader; extraBuffer
A PACKING: pre-ACES color RGB + totalInk in A.a; ACES on writeTexture only (HEAD)

---

SHADER: gen-evolutionary-cellular-gardens
IDENTITY: multi-scale Conway-like CA (fine/mid/coarse) with audio-driven birth/survival, spring nutrient attractor, colony age
KEEP VERBATIM: cell_scale / evolution_speed / invasive_force / bioluminescence; extraBuffer[133..138] spring; three cellularState layers; A = trail RGB + colonyAge
ADD (2 native ideas):
  1. Scale-mismatch sporulation — glow where fine is alive and coarse is dead (invasive spores at the scale gap)
  2. Nutrient-facing rhizoids — thin filaments from established colonies toward the spring attractor (chemotaxis, this CA already owns the well)
FORBID on this file: new extraBuffer slots; Lenia rewrite; IQ overlay
A PACKING: trail RGB + colonyAge in A.a; ACES on writeTexture only (HEAD)

---

SHADER: gen-fractal-bioluminescence-spore-network
IDENTITY: kaleido-warped KIFS raymarch with two Clifford-attractor spores plus a filament, mouse injection, glow accumulation
KEEP VERBATIM: sporeDensity / networkComplexity / bioluminescenceIntensity / audioReactivity; kaleido + warpedFBM + Clifford pair; ACES into A
ADD (2 native ideas):
  1. Spore-to-spore hyphae — a capsule between the two Clifford centers inside map (this is a network, not two floating blobs)
  2. Quorum pulse — extra hot glow when the two spores are close (bioluminescent quorum, not a click ripple)
FORBID on this file: springs; CA rewrite; extraBuffer
A PACKING: ACES display RGBA in A (HEAD)

---

SHADER: gen-fractal-chrono-dendrite-forge
IDENTITY: L-system recursive cylinder dendrites with Apollonian node hollows, mouse gravity twist, bismuth thin-film, 3-point forge lighting
KEEP VERBATIM: dendriteComplexity / entropyPulseRate / spectralDispersion / gravityWellStrength; abs-fold cylinders; node subtraction; no extraBuffer writes
ADD (2 native ideas):
  1. Side-branch buds — a thinner perpendicular cylinder at each iteration (real dendrites branch, not only fold)
  2. Recalescence flash — entropy-pulse crest heats the metal at high curvature (forge cooling flash, not a generic sparkle)
FORBID on this file: extraBuffer springs; hopper-bismuth rewrite (that is the hyper-bismuth files); IQ as the look
A PACKING: ACES display RGBA in A (HEAD)

---

SHADER: gen-glass-mosaic-liquid-refraction
IDENTITY: domain-warped Voronoi glass mosaic that refracts the source photo, lead came, caustics, Beer–Lambert, IOR 1.52
KEEP VERBATIM: facet-density / bevel-width / refraction-strength / ripple-speed; voronoi + worley + heightMap; photo refraction; ACES display A
ADD (2 native ideas):
  1. Facet-pane Snell — each Voronoi cell tilts the refract UV by a stable pane normal (true mosaic panes, not only the liquid heightfield)
  2. Meniscus at lead — extra refraction kick on the came (liquid wetting the lead line)
FORBID on this file: springs; ferrofluid rewrite; replacing the photo refraction with a generative-only look
A PACKING: ACES display RGBA in A (HEAD)

---

SHADER: gen-gravitational-ferrofluid-singularity-engine
IDENTITY: Rosensweig-spike ferrofluid sphere around a gravitational singularity, event-horizon lens, accelerating droplets, mouse warp
KEEP VERBATIM: singularityMass / fluidViscosity / spikeDensity / iridescence; angular+radial fronts; 8 analytic droplets; ACES display A; no extraBuffer
ADD (2 native ideas):
  1. Rosensweig peak ridges — extra specular where angularFront × radialFront crests (the actual spike peaks of this SDF)
  2. Photon-ring oil sheen — thin iridescent ring just outside the event-horizon radius (lensing + ferrofluid film)
FORBID on this file: new springs; tesseract rewrite; extraBuffer
A PACKING: ACES display RGBA in A (HEAD)
