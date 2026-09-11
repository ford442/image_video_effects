# Tactile twelve — Idea Cards (written before WGSL)

Family: print / relief / melt / cloth after the 2026-09-08 warp ten. Two native ideas each. No spring+ripple+IQ stamp. No new extraBuffer owners. Twelve is the hard ceiling.

---

SHADER: kintsugi-repair
IDENTITY: Voronoi ceramic shards repaired with gold lacquer seams
KEEP VERBATIM: scale / width / displacement / shiny; nearest-site Voronoi; mouse repair energy; gold runners; click fronts
ADD:
  1. F2 second-edge cracks — T-junctions from the second-nearest site wall (kintsugi network, not a new motif)
  2. Raised gold meniscus — lacquer beads along edgeDist so the seam has height, not only color
FORBID: extra sparkle, IQ palettes, extraBuffer springs
A PACKING: ACES display RGBA (HEAD wrote unused telemetry and never read C)

---

SHADER: plastic-bricks
IDENTITY: LEGO-style studded bricks with per-brick photo sample and plastic BRDF
KEEP VERBATIM: density / stud_size / relief / bevel; staggered rows; per-brick centerUV sample; stud AO; mouse deconstruct
ADD:
  1. Hollow underside tubes — concentric rings on the brick back (LEGO tubes, not a new toy)
  2. Injection knit-line — faint weld across the brick face from the mold split
FORBID: more toy-tint as the upgrade, extraBuffer springs
A PACKING: ACES display RGBA (HEAD wrote unused telemetry and never read C)

---

SHADER: wave-halftone
IDENTITY: hexagonal printed dots modulated by wave interference
KEEP VERBATIM: dot size / grid density / wave amp; hex cell sample; `zoom_params.w` as chromatic amount even though JSON is named Wave Speed
ADD:
  1. Elliptical dots stretched along the wave gradient (print screen, not a warp costume)
  2. Second hex screen at 15° for a print rosette
FORBID: springs; renaming or rewiring Wave Speed
A PACKING: ACES display RGBA (HEAD wrote unused telemetry and never read C)

---

SHADER: spec-histogram-equalize
IDENTITY: 16×16 workgroup CLAHE with clip-limit redistribute
KEEP VERBATIM: clipLimit / strength / tileBlend / colorPreserve; mouse contrast lens; ripple clip pulses; cooperative histogram
ADD:
  1. Highlight shoulder — CDF remap rolls off above ~0.9 so whites do not clip
  2. Exact-C temporal mix — previous equalize damps tile flicker
FORBID: treating the existing lens/ripples as the new ideas; extraBuffer springs
A PACKING: ACES display RGBA (HEAD already wrote display A)

---

SHADER: pin-art-3d
IDENTITY: push-pin / pin-screen relief of the photo
KEEP VERBATIM: density / pin_radius / push / metallic; pin grid; existing sphere-cap normal; C color persistence mix
ADD:
  1. Neighbor-pin occlusion — taller west/north neighbors shade this pin
  2. Pin shaft — short cylinder neck under the cap when the pin is proud of the board
FORBID: extraBuffer springs; restamping the existing sphere cap as a new idea
A PACKING: ACES display RGBA (HEAD read C as color and never wrote A — packing lie, fix)

---

SHADER: triangle-mosaic
IDENTITY: equilateral triangle mosaic with mouse twist
KEEP VERBATIM: scale / rotation / twist / mix; skewed triangle grid; C history mix
ADD:
  1. Grout darkening along triangle edges
  2. Per-facet tilt from the centroid (each triangle a slightly rotated plane)
FORBID: springs, IQ palettes, replacing triangles with Voronoi
A PACKING: ACES display RGBA (HEAD already wrote display A)

---

SHADER: polka-wave
IDENTITY: CMYK angled-screen polka dots warped by traveling waves
KEEP VERBATIM: density / amp / freq / speed; four CMYK screen angles; invertRipple
ADD:
  1. Offset-print dot gain — dots swell in darks
  2. Screen grid rides the existing wave (dots travel with invertRipple)
FORBID: restamping CMYK angles as a new idea; extraBuffer springs
A PACKING: ACES display RGBA

---

SHADER: honey-melt
IDENTITY: hexagonal honey cells that melt under the pointer
KEEP VERBATIM: cell size / melt radius / distort / softness; hex A/B lattice; solid bulge vs melted mix
ADD:
  1. Gravity sag on melted cells — downward UV, not isotropic noise
  2. Comb-wall capillary — hex rims hold honey until melt
FORBID: extraBuffer springs; replacing hex cells with a liquid solver
A PACKING: ACES display RGBA (HEAD never wrote A)

---

SHADER: slime-drip
IDENTITY: vertical mucus drips with mouse wipe
KEEP VERBATIM: speed / viscosity / amount / tint; drip threshold; wipe restores UV
ADD:
  1. Anisotropic gravity stretch of the drip noise (falls down, not isotropic blobs)
  2. Exact-C drip hang — previous drip field persists so trails hang
FORBID: extraBuffer springs; replacing drips with a liquid solver
A PACKING: raw fields (drip, thickness, tint_mask, alpha) — HEAD wrote A and never loaded C; start reading C as those fields. ACES on writeTexture only.

---

SHADER: velvet-scatter-bloom
IDENTITY: velvet subsurface scatter in darks with a mouse key light
KEEP VERBATIM: scatter / bloom / subsurface / lightAngle; darkMask scatter; mouseLight
ADD:
  1. Anisotropic nap sheen along the light tangent
  2. Held-pointer nap crush — scatter drops under press
FORBID: springs; IQ palettes
A PACKING: ACES display RGBA (HEAD wrote unused telemetry and never read C)

---

SHADER: page-curl-interactive
IDENTITY: cylinder page-curl follows mouse X
KEEP VERBATIM: curlRadius / shadow / feedback / depth; front/curl/back masks; exact C feedback. Existing click shocks stay (HEAD, not this upgrade)
ADD:
  1. Backside peek of the curled sheet
  2. Paper fiber along the curl tangent
FORBID: more shockwaves; extraBuffer springs
A PACKING: ACES display RGBA (HEAD already wrote display A)

---

SHADER: fabric-step
IDENTITY: Verlet mass-spring cloth with tear threshold
KEEP VERBATIM: stiffness / tearThreshold / gravity / damping; A = (pos, prevPos); mouse push; constraint iterations
ADD:
  1. Warp/weft weave from strain axes
  2. Exact integer textureLoad C (HEAD filtered dataTextureC)
FORBID: extraBuffer cursor springs (the cloth already is the mass-spring); ACES into stored fields
A PACKING: raw sim (pos.xy, prevPos.xy) — HEAD packing kept; display ACES on writeTexture only
