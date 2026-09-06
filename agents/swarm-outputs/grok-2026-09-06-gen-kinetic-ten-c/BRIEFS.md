# Grok batch — simpler generative / kinetic (10) C — Idea Cards

Written **before** WGSL. `gen-hyper-warp` is underscore-backed (`gen_hyper_warp.wgsl` / `.json`). Identity is the **current kernel**.

---

SHADER: gen-echo-dunes
IDENTITY: wind-carved sand ridges, sunset sky, heat mirage, cursor echo rings
KEEP VERBATIM: duneScale/wind/mirage/echo; FBM warp; ridge SDF shadows; extraBuffer[133] bass envelope; HDR A
ADD:
  1. Slipface shade — extra dark on the leeward slope of the primary ridge (real dunes have a steep slipface)
  2. Wind streaks — faint along-wind grain on the sand (aeolian)
FORBID: extra springs (bass envelope already owns [133]); replacing dunes with a different terrain
A PACKING: HDR display RGBA in A

---

SHADER: gen-erosion-strata
IDENTITY: sedimentary beds carved by domain-warped erosion, veins, fossils, water line
KEEP VERBATIM: erosion/density/veins/water; layer index `li`/`lf`; voronoi veins
ADD:
  1. Bedding contacts — bright line where `lf` hits a bed boundary
  2. Cross-beds — intra-layer diagonal striae (this is strata, not a generic lattice)
FORBID: rewriting as a heightfield sim; extra springs
A PACKING: ACES display RGBA in A (HEAD)

---

SHADER: gen-ghost-flame
IDENTITY: advected temperature/fuel flame with ghost translucency
KEEP VERBATIM: height/turbulence/cooling/diffusion; A = (T, fuel, vx, age); extraBuffer[133..134] envelopes
ADD:
  1. Wick column — thin fuel stem at the base center (candle/ghost wick)
  2. Ignition chemiluminescence — blue edge at the T≈ignition band
FORBID: writing display into A; new extraBuffer slots
A PACKING: raw T, fuel, vx, age

---

SHADER: gen-fractured-monolith
IDENTITY: raymarched box monolith split into drifting cells over a liquid floor
KEEP VERBATIM: spread/levitation/glow/rotation; cell fracture; cyan crack glow
ADD:
  1. Shard identity tint — per-cellId colour so fragments read as separate stones
  2. Fracture-plane glint — specular from crack noise on the monolith surface
FORBID: a second SDF creature; extra springs
A PACKING: ACES display RGBA (HEAD)

---

SHADER: gen-fractal-clockwork
IDENTITY: infinite tiled interlocking gears over a floor, sprung orbit camera
KEEP VERBATIM: scale/teeth/speed/material; sdGear; extraBuffer[133..138] spring
ADD:
  1. Tooth spark — highlight when the tooth sine is at a crest
  2. Mesh line — glow at the mid-gap between neighboring gears (where teeth meet)
FORBID: new extraBuffer; replacing gears with clock hands
A PACKING: ACES display RGBA

---

SHADER: gen-fractal-ember-lattice
IDENTITY: triangular ember lattice with rigid mouse-shatter / reform
KEEP VERBATIM: glow/shard size/scale/sparks; A = (disp.xy, seed, reform)
ADD:
  1. Triple junctions — glow where all three lattice distances are small (crystal vertices)
  2. Cell-core heat — hotter faces at hex/tri centers
FORBID: packing display into A; extra springs
A PACKING: raw shard state

---

SHADER: gen-hyper-labyrinth
IDENTITY: 4D-rotated gyroid maze, neon veins, persisted neon in A
KEEP VERBATIM: scale/morph/glow/thickness; rotate4D gyroid; neon history
ADD:
  1. Gyroid zero ridge — extra glow on the maze midline (`abs(val)≈0`)
  2. W-slice hue — neon tint from the rotated 4th coordinate
FORBID: replacing gyroid with a cubic maze; new extraBuffer
A PACKING: persisted neon RGB + alpha (HEAD)

---

SHADER: gen-hyper-warp (`gen_hyper_warp.wgsl`)
IDENTITY: nested fBm domain warp + stabilized flow-advected feedback
KEEP VERBATIM: intensity/speed/scale/detail; q/r warp; stabilizeHistory
ADD:
  1. Warp folds — caustic where |q−0.5| sits in the mid range (fold of the first warp)
  2. Flow stretch — extra energy from |r−q| (second-layer shear)
FORBID: Rankine-vortex overlay; extra springs
A PACKING: raw HDR history in A (HEAD)

---

SHADER: gen-hyper-rainbow-vortex
IDENTITY: Rankine vortex (solid core + 1/r outside) with counter-rotating rainbow spirals
KEEP VERBATIM: intensity/speed/scale/colorShift; coreR/omega; spiral layers
ADD:
  1. Rankine seam — mark the core/irrotational interface at r=a
  2. Braid beads — brighter where counter-rotating arms cross (spiral1×spiral2)
FORBID: replacing Rankine with a simple swirl overlay
A PACKING: HDR vortex RGBA in A (HEAD)

---

SHADER: gen-hyperbolic-tessellation
IDENTITY: Poincaré-disk kaleidoscope with Möbius mouse translation
KEEP VERBATIM: symmetry/depth color/rotation/boundary; fold loop; disk mask
ADD:
  1. Ideal vertices — glow at kaleidoscope corners (foldedAngle near 0 and sector/2)
  2. Horocycles — rings of constant hyperbolic radius from the origin
FORBID: Euclidean grid overlay; extra springs
A PACKING: HDR tessellation RGBA in A
