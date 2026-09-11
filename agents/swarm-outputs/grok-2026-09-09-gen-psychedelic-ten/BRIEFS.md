# Generative fast-motion / psychedelic ten — Idea Cards (written before WGSL)

Family: leftover catalog generative with plasma / acid / polar explosion / mandala / neon-solid identity (not another photo kaleido/tunnel overlay, not holographic). Two native ideas each. Identities kept. Existing pointer + click ripples kept; no new extraBuffer springs.

Claimed IDs: `gen-plasma-psychedelic-wormhole`, `gen-neon-acid-geometry`, `gen-chromatic-acid-drip`, `gen-polar-rainbow-explosion`, `gen-neon-cyber-mandala`, `gen-plasma-mandala`, `gen-neon-lotus`, `gen-electric-kaleidoscope-storm`, `gen-rainbow-icosahedron-cascade`, `gen-neon-stellated-octahedron`.

Skipped: today’s kaleido/tunnel ten; classic gen ten; Batch 71 DMT / cymatic mandalas; Batch 45/46 synapse / mushroom / velvet / jelly; Batch 39 firefly; Batch 36 thermal rainbow; `gen-relay-psychedelia`; holographic leftovers; `gen-hyperdimensional-plasma-loom` (illegal extraBuffer audio).

---

SHADER: gen-plasma-psychedelic-wormhole
IDENTITY: 1/r plasma tunnel with blackbody temperature, spiral arms, and streaming stars
KEEP VERBATIM: brightness / travel speed / tunnel scale / color shift; 1/r depth; plasma fBm octaves; blackbody mix; spiral arms; stars
ADD (2 native ideas):
  1. Contra-rotating inner vs outer plasma octaves — this tunnel already stacks octaves; inner shears against outer
  2. Doppler hue along radial travel — approaching vs receding plasma along the existing 1/r axis, not a new portal
FORBID on this file: cloning mouse-wormhole-lens 1/r² lensing or C ghost; log-z from kaleido-tunnel; new springs
A PACKING: HDR trail RGB in A; ACES on writeTexture only. HEAD filtered C — exact textureLoad. Mouse UV is 0–1 (floor, not an idea).

---

SHADER: gen-neon-acid-geometry
IDENTITY: grid of melting triangle / hex / circle SDFs whose glow is a universal-indicator pH color
KEEP VERBATIM: intensity / speed / scale / color shift; sdTriangle / sdHexagon / sdCircle; phToColor; Snell refraction; mouse pH splash
ADD (2 native ideas):
  1. pH on the rim only — interiors keep a cooler geometry fill; indicator lives on the SDF edge
  2. Traveling smin morph — a second sibling SDF of the same family blends around the existing shape, not a drip metaball
FORBID on this file: cloning chromatic-acid-drip metaballs; kaleido fold; IQ palette takeover
A PACKING: HDR display RGBA in A (ACES on write). HEAD filtered C — exact textureLoad. Mouse UV 0–1.

---

SHADER: gen-chromatic-acid-drip
IDENTITY: metaball blobs plus chromatic drip that changes color as it falls through a pH gradient
KEEP VERBATIM: intensity / flow speed / blob scale / color shift; metaballField; chromaticDrip; phDripColor; mouse acid/base splash
ADD (2 native ideas):
  1. Meniscus / coffee-ring on the metaball isosurface — a bright rim where the blob meets the field threshold
  2. Gravity-biased fall — extra +Y on blob centers so they drop more than they orbit
FORBID on this file: cloning acid-geometry triangle/hex grid; ferrofluid rewrite; new springs
A PACKING: HDR display RGBA in A (ACES on write). HEAD filtered C — exact textureLoad. Mouse UV 0–1.

---

SHADER: gen-polar-rainbow-explosion
IDENTITY: polar neon rays from a mouse origin with a spherical shock front and particle bursts
KEEP VERBATIM: intensity / speed / scale / color shift; 36-ray loop; existing shockR; burst particles; spiral arms
ADD (2 native ideas):
  1. Mach split — energy ahead of shockR vs behind it (compression vs rarefaction on THIS shock)
  2. Wavelength-scaled ray width — R/B sample the same polar ray at different widths, not extra CA blobs
FORBID on this file: kaleido fold; log-z tunnel; IQ as the whole look
A PACKING: ACES display RGBA. C already textureLoad. Mouse UV 0–1.

---

SHADER: gen-neon-cyber-mandala
IDENTITY: nested patterned rings, stars, and polygons with golden-ratio / Fibonacci layering
KEEP VERBATIM: glow / rotation / zoom / color shift; PHI; GOLDEN_ANGLE; patternedRing; starRays; sdPolygon
ADD (2 native ideas):
  1. φ ring spacing — consecutive ring radii follow r_{n+1}=r_n/φ instead of even steps
  2. Inner vs outer contra-rotation — inner rings spin against outer rings on the existing rotation
FORBID on this file: cloning plasma-mandala angular fold; Poincaré; new springs
A PACKING: ACES display RGBA. HEAD filtered C — exact textureLoad.

---

SHADER: gen-plasma-mandala
IDENTITY: audio-driven radial mandala whose petals are an angular-folded plasma field
KEEP VERBATIM: symmetry / spin / zoom / glow; angular sector fold; plasma() + fbm; mouse-pull center
ADD (2 native ideas):
  1. Fold-seam highlight on the sector cut — the fold already exists; light the knife edge
  2. Radial plasma advection — plasma phase travels along r, not just hue cycle
FORBID on this file: Poincaré / opposite-wedge from today’s kaleido-scope; IQ palette as the whole look
A PACKING: ACES display RGBA (HEAD never reads C).

---

SHADER: gen-neon-lotus
IDENTITY: layered teardrop-petal SDF lotus with stamens and neon edge glow
KEEP VERBATIM: petal count / bloom / speed / glow; petalSdf; 3 layers; stamens; mouse center
ADD (2 native ideas):
  1. Vein along each petal midline — this is already a polar teardrop; the mid-θ is the vein
  2. Golden-angle offset between layers — replace the flat 0.4 with GOLDEN_ANGLE
FORBID on this file: cloning mushroom-mandala-garden; iris-bloom collarette; new springs
A PACKING: ACES display RGBA (HEAD never reads C).

---

SHADER: gen-electric-kaleidoscope-storm
IDENTITY: branching lightning bolts in a kaleidoscope fold with a dielectric center orb
KEEP VERBATIM: bolt intensity / flicker / symmetry / color shift; kaleidoscopeFold; branchingBolt; dielectricBreakdown; existing click shock rings
ADD (2 native ideas):
  1. Lichtenberg afterimage — exact-C trail mixed along the bolt, not a new sim
  2. Leader vs return-stroke — thin dim leader then bright return on the same bolt (hash-gated)
FORBID on this file: log-z / opposite-wedge / inhale-exhale from today’s kaleido ten; new extraBuffer springs; extra shock overlay (HEAD already has click rings)
A PACKING: HDR trail RGB in A; ACES on write. HEAD already textureLoad. No new extraBuffer.

---

SHADER: gen-rainbow-icosahedron-cascade
IDENTITY: nested golden-ratio icosahedral wireframe shells with spectral edge glow
KEEP VERBATIM: shell count / spacing / edge glow / hue drift; icosaVerts / icosaEdges; mouse orbit
ADD (2 native ideas):
  1. Silhouette orbit-trap — edges that face the camera (small |p.z| or facing term) burn brighter
  2. Golden-angle yaw offset per shell — each shell rotates by n·GOLDEN_ANGLE, not a second polyhedron
FORBID on this file: cloning stellated dual-tetra; kaleido XY fold from the octahedron; springs
A PACKING: ACES display RGBA. HEAD packed minDist/hue telemetry while mixing C as color — packing lie fixed.

---

SHADER: gen-neon-stellated-octahedron
IDENTITY: two interpenetrating tetrahedra (stella octangula) with neon edges and 6-fold XY fold
KEEP VERBATIM: star scale / spin / neon power / color shift; tetraVerts; 6-fold XY kaleido; mouse orbit
ADD (2 native ideas):
  1. Intersection ridge — glow where the two tetras occupy the same space (min of both layer edges)
  2. Face vs edge spectral split — hue2 stays on facets, hue on edges (HEAD already has two hues; make the split spatial)
FORBID on this file: cloning nested icosa shells; Poincaré; new springs
A PACKING: ACES display RGBA. HEAD packed sd.x/hue telemetry while mixing C as color — packing lie fixed.
