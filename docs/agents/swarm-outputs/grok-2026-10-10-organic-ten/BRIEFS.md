# Organic generative ten — 2026-10-10

Idea cards written before WGSL edits. Each shader gains two native ideas. Saved params stay byte-exact. September ideas on the six second-pass files stay.

## gen-cryogenic-frost-plasma-matrix

IDENTITY: KIFS ice matrix with a hot plasma interior and volumetric frost fog.
KEEP VERBATIM: KIFS fold, ice-vs-plasma split, fog march, Fracture / Plasma Heat / Ice Density / Fog Thickness, bass envelope at extraBuffer[133], existing click-front fracture kick.
ADD:
1. Hoarfrost dendrites — branching ridges on the ice from the KIFS fold seams, scaled by Fracture Intensity.
2. Sublimation sheath — cyan vapor where ice and plasma distances match, thickness from Fog Thickness.
FORBID: a second shockwave system, IQ palette, springs.
A PACKING: HDR colour in A (C feedback mixes pre-ACES); ACES only on writeTexture.
SYMBOLS: `hoarfrostDendrites`, `sublimationSheath`

## gen-cyber-organic-void-mycelium-pulsar

IDENTITY: void grid of mycelial tubes and glowing spore nodes.
KEEP VERBATIM: cell repeat, three-axis tubes, node spheres, spore bloom, abyssal fog, Density / Spore Glow / Twist / Fog.
ADD:
1. Anastomosis bridges — short links between the three axis tubes inside each cell.
2. Spore pulse train — a bead travels each tube; Spore Glow sets brightness, mids set the rate.
ALSO: real 2D twist rotation; audio from plasmaBuffer.
FORBID: cursor spring, click rings, neural-web palette.
A PACKING: ACES display RGBA.
SYMBOLS: `anastomosis`, `sporePulse`

## gen-cybernetic-mycelium-neural-web

IDENTITY: mycelial net, filigree, data pulses, spring cursor, click mutation.
KEEP VERBATIM: myelination, gap-junction flash, spring [133..138], four slider roles.
ADD:
1. Dendritic spines — knobs where filigree peaks.
2. Refractory notch — dark gap just after each pulse peak.
FORBID: new extraBuffer slots.
A PACKING: ACES display RGBA.
SYMBOLS: `dendriticSpine`, `refractory`

## gen-cybernetic-plasma-orchid-nexus

IDENTITY: plasma core, petal ring, labellum, nectar well, pollinia column.
KEEP VERBATIM: labellum, column, pollinia, bloom R/B split, tetrahedral normals, four slider roles.
ADD:
1. Dorsal sepal — cooler hood opposite the lip.
2. Petal veins — radial ridges on the petal blades, widened by Distortion Strength.
FORBID: springs, a second flower species.
A PACKING: ACES display RGBA; C is not read.
SYMBOLS: `dorsalSepal`, `petalVeins`

## gen-ethereal-chrono-flora-loom

IDENTITY: six-fold glowing stems around a central orb, twisted over height.
KEEP VERBATIM: 6-petal fold, stem capsule, orb, smin, cosine palette, four slider roles.
ADD:
1. Warp threads — helices along Z; Density owns radius.
2. Weft shuttle — bead orbiting at Flow Speed.
ALSO: plasmaBuffer audio; mouse orbit from 0–1 zoom_config.yz.
FORBID: click shockwaves.
A PACKING: ACES display RGBA.
SYMBOLS: `warpThreads`, `weftShuttle`

## gen-ethereal-chrono-fluid-symbiote

IDENTITY: warped fluid blob joined to a crystal lattice, held-pointer gravity well.
KEEP VERBATIM: 4D fbm warp, fluid sphere, crystal boxes, smin, two materials, four slider roles.
ADD:
1. Meniscus film — membrane on the fluid/crystal seam; Symbiote Glow owns it.
2. Chrono smear — C lags fluid colour; Chrono Warp scales the lag.
ALSO: plasmaBuffer audio; ACES replaces col/(1+col).
FORBID: springs, mycelium grid.
A PACKING: ACES display RGBA. C is the previous display frame.
SYMBOLS: `meniscus`, `chronoSmear`

## gen-ethereal-cyber-aurora-hummingbird-core

IDENTITY: hummingbird in a chrono flower, spring hover, nectar bloom, wingbeat afterimage.
KEEP VERBATIM: spring [133..138], nectar bloom, wingbeat afterimage, four slider roles.
ADD:
1. Gorget plate — throat disk; Aberration splits its hue with view angle.
2. Forked tail ribbons — two streamers behind the body.
FORBID: new extraBuffer indices.
A PACKING: HDR in A, ACES on writeTexture; alpha = hit coverage + glow.
SYMBOLS: `gorget`, `tailRibbon`

## gen-ethereal-cyber-chrono-void-whale

IDENTITY: skeletal whale, open ribs, streams, baleen, bass sonar.
KEEP VERBATIM: spine, eight ribs, core, streams, baleen, sonar, four slider roles, existing click fronts.
ADD:
1. Flukes — two lobes at the tail of the spine.
2. Blow mist — bass-gated puff above the core, separate from sonar rings.
FORBID: a new spring.
A PACKING: ACES display RGBA.
SYMBOLS: `flukes`, `blowMist`

## gen-ethereal-quantum-glass-nautilus

IDENTITY: log-spiral glass shell, septa, pearl nacre.
KEEP VERBATIM: log spiral, septa, nacre, four slider roles.
ADD:
1. Siphuncle — thin canal along the spiral centerline.
2. Aperture lip — thickened rim on the outer chamber; Refraction Index lifts its fresnel.
FORBID: creature SDFs, springs.
A PACKING: ACES display RGBA.
SYMBOLS: `siphuncle`, `apertureLip`

## gen-fireworks-dahlia-burst

IDENTITY: flat dahlia-disk shells, layered rows, mouse shell.
KEEP VERBATIM: shell cycle, imbrication, midrib, gravity fall, four slider roles, bass/mids/treble roles.
ADD:
1. Involute curl — petal tips hook sideways as the row ages.
2. Pistil disk — short central florets; count from Petal Count.
FORBID: spherical chrysanthemum, extraBuffer.
A PACKING: ACES display RGBA; C is the trail mix.
SYMBOLS: `involuteCurl`, `pistilDisk`

## Closeout 2026-10-10

Per-file `wgsl_precommit_gate.py`: 10/10 naga and bind-group pass after `#include "_prelude.wgsl"`.
`audit:extrabuffer` pass (1428 files, 0 new writes into `[0..132]`).
`audit:dead-sliders` full catalog pass (0 new dead sliders).
`npm test -- --watchAll=false --ci`: 133 suites, 1011 passed, 1 skipped.
`SKIP_WASM_BUILD=1 npm run build`: compiled successfully.
Real-GPU visual QA was not run. This VM has no hardware GPU adapter.
