# BRIEFS — grok 2026-09-27 generative unused ten

Written before WGSL edits. Creative law: `docs/SHADER_UPGRADE_BATCH.md`.

## gen-radiant-cyber-bismuth-nebula-colossus

IDENTITY: IFS-folded cyber-bismuth lattice smooth-unioned with hopper octahedra inside a kaleidoscopic nebula storm
KEEP VERBATIM: Fold Scale / Nebula Density / Audio Reactivity / Iridiscent Shift; abs-fold loop; octahedron smin; mouse-orbit camera; click dolly; kaleido star field; adaptive fold/step counts
ADD:
  1. Hopper terrace stairs — concentric inward steps on the existing octahedron, phase from Iridiscent Shift
  2. Terrace-lip emissive — bass lights only those stair edges, scaled by Audio Reactivity
  3. Nebula residue — exact load of C.a (stored nebula) as a faint previous-frame haze
FORBID: spring cursor, new click shockwaves, a different titan, IQ palette replacing the thin-film phase
A PACKING: A.rgb = ACES display; A.a = raw nebula accumulation. C.a read as residue.

## gen-radiant-cyber-chrono-void-stag

Already present: crystal tine bifurcation; segmented chrono hoof wakes. Keep both.

IDENTITY: leaping cyber-stag, crystal antlers, volumetric nebula, acoustic heart core
KEEP VERBATIM: Stag Scale, Antler Complexity, Nebula Density, Core Pulse; torso/neck/head/legs SDFs; mouse orbit; existing tines and hoof packets
ADD:
  3. Antler growth rings — ridges along each existing segment; segment count stays Antler Complexity
  4. Leap afterimage — exact C load of previous display, offset along the leap tangent, trail and miss pixels only
FORBID: a second animal, spring, shockwave rings, replacing the nebula march
A PACKING: ACES display RGBA in A. C read as previous display.

## gen-radiant-cyber-plasma-astro-griffin

IDENTITY: biomechanical griffin — plasma feather wings, prism body, golden eagle head and beak
KEEP VERBATIM: Warp Intensity, Wing Span, Fractal Depth, Plasma Glow; material ids 1/2/3; wingFeathers / griffinBody / griffinHead; mouse twist warp; flight flap
ADD:
  1. Primary-feather slots — dark gaps between existing feather cells
  2. Beak shear glint — treble specular only on material 3, along the beak-forward normal
  3. Flap ghost — exact C load shifted along the flap axis, wings only
FORBID: another creature, spring, click ripples, replacing the rift background
A PACKING: ACES display RGBA (was normal/mat packing; C was unread). C read as previous display.

## gen-radiant-quantum-plasma-kraken-core

Already present: paired sucker-current rows; core-to-arm peristaltic discharge. Keep both.

IDENTITY: eight plasma tentacles around a radiant core, mouse-rotated, bass-breathing
KEEP VERBATIM: Tentacle Twist, Plasma Glow, Core Heat, Void Depth; 8-arm capsule loop; mouse rotation; sucker rows; peristaltic radius pulse
ADD:
  3. Siphon jet — short bright discharge from the core along the nearest arm when bass rises
  4. Ink wake — exact C load darkened along that arm tangent; Core Heat sets stain strength
FORBID: a new creature, extra arms, spring, generic shockwaves
A PACKING: ACES display RGBA. C read as previous display.

## gen-raptor-mini

IDENTITY: mini raptor agents chasing a sprung mouse, claw-striking, leaving scent trails
KEEP VERBATIM: Turn Speed, Max Speed, Rage Duration, Glow Radius; extraBuffer[133..138] spring; u.ripples strike rings; held pounce; scent textureLoad; Gray-Scott stays background energy
ADD:
  1. Claw-rake triad — three short streaks along pursuit velocity inside the existing strike
  2. Tail counterphase — body mark offsets opposite the pursuit direction
FORBID: a new solver, removing the spring, a nebula costume
A PACKING: pre-ACES display/scent history in A. ACES on writeTexture only. C stays textureLoad.

## gen-reaction-diffusion (files `gen_reaction_diffusion.*`)

IDENTITY: Gray-Scott morphogenesis blended with FitzHugh–Nagumo action waves, mouse current injection
KEEP VERBATIM: Excitability, Recovery, Stimulus, Model Blend; both kinetic branches; mouse/click seeds; bass pulses; dataTextureB slot-chain store
ADD:
  1. Refractory trough — FHN recovery paints a dark band behind the wavefront; Recovery sets the width
  2. Gradient-stretched feed — Gray-Scott feed elongates along the concentration gradient; Excitability scales it
FORBID: replacing either solver, raymarched creature, ACES on stored u/v, new B packing
A PACKING: raw sim in A and the existing B copy. ACES on writeTexture only.

## gen-recursive-ancestral-terrains

IDENTITY: fractal height field whose octaves inherit parent genes; mouse picks which lineage shows
KEEP VERBATIM: Mutation Rate, Generation Depth, Height Scale, Erosion; φ persistence; Koch→Sierpinski dimension; bass-scaled erosion; mouse lineage select
ADD:
  1. Unconformity terraces — Generation Depth flattens steps where a child octave disagrees with its parent
  2. Valley sediment — exact C load of previous height settles into lows; Erosion drains it
FORBID: raymarched beast, IQ sky, spring, click shockwaves
A PACKING: A.rgb = ACES display; A.a = raw height. Do not tone-map A.a.

## gen-relay-psychedelia

IDENTITY: warped fbm field, palette color, temporal trail echo, mouse-held fold origin
KEEP VERBATIM: Warp Depth, Saturation, Hue Shift, Trail Echo; frozen chunk order; mouse-held fold origin
ADD:
  1. applyDomainWarp: second curl octave, strength = Warp Depth
  2. applyTemporalFeedback: directional smear along the warp flow via textureLoad; Trail Echo sets the reach
  3. applyPalette only: complementary fringe on tight kaleido seams; Saturation still owns chroma
FORBID: logic in main beyond wiring the seam scalar, new hue sources outside applyPalette, springs, creatures
A PACKING: ACES display RGBA in finalComposite. C is previous display via textureLoad.

## gen-resonant-crystal-canyons

IDENTITY: refractive crystal canyon with a plasma river; mouse warps the local terrain
KEEP VERBATIM: Crystal Density, Plasma Glow, Refractive Index, Audio Reactivity; wall boxes, three crystals, floor, river; mouse warp radius
ADD:
  1. Chromatic bore — river shading splits the boil along the flow by Refractive Index
  2. Organ-pipe partials — mids/treble add a second harmonic on the three existing crystals, Audio Reactivity gain
FORBID: bismuth hoppers, stag, spring, click shockwaves, a new creature
A PACKING: ACES display RGBA. C textureLoad is a faint river reflection only.

## gen-resonant-quantum-obsidian-astro-manta

IDENTITY: raymarched obsidian manta, fin-helix wings, vein lattice, kaleidoscopic shard sea
KEEP VERBATIM: Time Scale, Audio Reactivity, Brightness, Evolution Speed; rippleField plate buckle; mouse-orbit camera; kaleido sea; read-only FFT vein/air bins
ADD:
  1. Trailing membrane — thin sheet behind the wing stroke; Evolution Speed scrolls it
  2. Buckle fractures — existing ripple displacement etches bright cracks on the hull
FORBID: a different animal, removing ripples or the orbit camera, writing extraBuffer
A PACKING: ACES display RGB on writeTexture. A.a = wing coverage (not tone-mapped). C.a tints the shard sea.
