# Claude mixed-eight — Idea Cards

Written before WGSL edits. 2026-10-19.

Batch: bitonic-sort, vinyl-scratch, mosaic-reveal, cyber-organic, sim-slime-mold-growth-em,
gen-biomechanical-hive-julia, lenia-on-video, data-slicer. Six of the eight pasted the 13 bindings;
they were migrated to `#include "_prelude.wgsl"` first in a separate header-only commit (not counted).
Files that already carry `Ideas:` get a second pass; their prior ideas stay, and new ideas continue
their numbering.

## bitonic-sort

```
SHADER: bitonic-sort
IDENTITY (one sentence): a per-16×16-tile bitonic pixel sort of the (kaleido/domain-warped) photo by a luma/noise/voronoi/depth key, gated by threshold, span length and the pointer/ripple mask, with amber→cyan span-boundary glow.
KEEP VERBATIM: padded shared-memory layout (PAD_X=17, phys()); the PASS 2 compare-and-swap network and stage order; key formula (luma·0.7 + noise/voronoi·0.3 + depth·0.1 + Halton jitter) and the sentinel threshold gate; params sort_threshold / warp_amplitude / edge_glow / sort_length with their roles; mouse-press direction flip; ripple smin mask; ACES display path; A = feedback RGB + semantic alpha.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): the sort output is a run of slots in key order; real pixel sorters show it as a smooth gradient streak, but here every slot is a hard 1-px sample. The next-better operator on the *same* run is a key-range-weighted (bilateral in key space) tent along slot order — smooth inside a run, hard at key jumps.
  tactic 2 (physics one step further): Asendorf-style glitch sorting "melts": sorted streaks drip along the sort axis frame after frame.
  tactic 3 (promote an intermediate): `nextKey` / `keyJump` already exist for the boundary glow — reuse them as the bilateral weight; `effectiveMix` says where a pixel is sorted.
  tactic 6 (use the history): C is read as colour feedback (prev.rgb·decay mixed with display). Reading C one pixel back along the sort axis (row-major slots run along +x; descending flips) lets the feedback advect along the streak without a new field.
ADD (2 native ideas):
  1. Key-coherent run smoothing — sorted slot blended with its slot-order neighbours (li±1) weighted by key proximity, so each sorted span reads as a continuous gradient streak; boundaries (keyJump) stay crisp. Only where effectiveMix (sorted) is on.
  2. Sort-axis drip — feedback samples exact C one pixel upstream along the sort direction inside sorted spans, and a fraction of that dripped history shows in the display, so streaks melt along the run and settle when the mask lets go.
FORBID on this file: springs, new click fronts, IQ palette, replacing the bitonic network, a new key, any new param.
A PACKING: A = temporal-feedback RGB (display-space, ACES'd colour mixed with decayed C) + semantic alpha (unchanged).
```

## vinyl-scratch

```
SHADER: vinyl-scratch (second pass; first pass 2026-09-21)
IDENTITY (one sentence): the source image printed onto a spinning record — platter rotation + mouse
  scratch, spindle wow, 1/r groove pitch with label, stylus marks cut by clicks, dust/grain/warmth.
KEEP VERBATIM: 4 params and their mapping (x → rotation speed, y → scratch offset, z → wobble/wow,
  w → groove-noise intensity); spring [133..138]; click platter kick + stylus marks; eccentric spindle;
  groove pitch/label/lead-out band; sparkle C.a coherence; dust, grain, vignette, warmth, roll-off,
  lens dirt; ACES; A = display RGBA with semantic alpha (C.a read as sparkle proxy, unchanged).
MECHANISM INTERROGATION:
  t1 deepen the kernel: the groove light is a one-lobe angular gaussian; a groove is a circular
     diffraction/anisotropic reflector, so the true highlight is a radial "bow-tie" — two opposite
     lobes. HEAD also compared an unwrapped lightAngle (time*0.5) to atan2, so the lobe left the
     [-π,π] window after ~10 s and the sheen died; a wrapped angular distance fixes that.
  t2 physics one step further: between songs the cutter lays a silent, unmodulated spiral — the
     glossy track gaps every record shows as bright rings; modulated (loud) grooves read matte.
  t3 promote an intermediate: `rotationSpeed` and the rotated sample direction are already computed;
     a spinning platter seen at frame rate smears tangentially by that angular rate.
  t6 history: C.a is already the sparkle proxy; packing left alone, no new history use.
ADD:
  1. Bow-tie anisotropic groove sheen — second lobe at lightAngle+π, wrapped angular distance,
     lobe narrows with radius (grooves are straighter, highlight tighter, at the rim).
  2. Glossy track-gap bands — 4 silent spirals at fixed radii inside grooveBand: groove noise
     suppressed there and the sheen sharpened/brightened; loud bass widens the matte bands.
  3. Tangential platter smear — 2 extra green-channel-matched taps at ±dθ ∝ |rotationSpeed| along the
     rotation, so fast spins blur along the groove direction, never radially.
FORBID on this file: new params, IQ palette, ripple rings, a second spring, repacking C.a.
A PACKING: ACES display RGBA (unchanged; C.a remains sparkle-coherence proxy).
FORMULAE: §12.1 tactic 1 (anisotropic reflector) / tactic 5 device artifact; no §12.2 row reused.
```

## mosaic-reveal

```
SHADER: mosaic-reveal
IDENTITY (one sentence): the photo as a square/hex mosaic of tesserae that turn over to reveal the full image inside a breathing, pointer-centred disc.
KEEP VERBATIM: 4 params and roles (cellSize → tile count, revealSpeed → disc breathing, edgeGlow → blackbody rim, gridType → square/hex); hexCenterTile lattice; conveyors; tile-turn front (2026-10-05 idea 1); grout + bevel (idea 2); re-mosaic afterimage from C (idea 3); flood runner + capped click fronts; OkLab blend; ACES; layered alpha; A packing.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): a tessera's colour is a single nearest-texel point sample at the tile centre — it aliases and flickers on video. The next-better operator of the same kind is the area mean of what the tile covers.
  tactic 2 (physics one step further): real smalti tesserae are set by hand at slight, random tilts; each catches the light differently, so a mosaic glints as the viewer moves (Byzantine setting technique).
  tactic 3 (promote an intermediate): `q` (pixel-in-tile) and `centerT` (tile id) already drive the bevel; `centerT` hash gives a per-tessera tilt for free; `mouse` already exists as the viewer's anchor.
  tactic 6 (history): C is reveal colour history; nothing new needed — glint is display-only, so the afterimage stays a colour afterimage.
ADD (2 native ideas):
  4. Tessera area-mean colour — 5-tap box over the tile footprint (centre + four ±0.25-tile taps) instead of one point sample; the cut stone carries the mean of the area it replaces.
  5. Hand-set tessera tilt + glint — per-tile random normal (hash of centerT) shades each tessera by Lambert and adds a sharp specular glint; the view vector comes from the pointer, so moving the mouse makes the field sparkle like walking past a church mosaic. Mosaic side only.
FORMULA ADMISSION: tactic-1 kernel deepening (§12.2A spirit, box mean) and a per-facet Blinn glint on the bevel the file already lights; both consume centerT/q/mouse already computed; deleting either leaves exactly this effect.
FORBID on this file: spring cursor, new ripple system, IQ palette, thin-film, any new param, changing the turn front or afterimage packing.
A PACKING: pre-ACES reveal colour history RGB + .a = 10 + accumulated alpha (unchanged).
```

## cyber-organic

```
SHADER: cyber-organic
IDENTITY (one sentence): a biotech scanner that reveals pulsing bioluminescent veins beneath the photo, concentrated in a radius around the cursor.
KEEP VERBATIM: 4 params and roles (scanSpeed → scan sine rate, organicScale → vein fbm frequency, revealRadius → cursor reveal radius (held tightens ×0.72), pulseSpeed → vein pulse rate); cursor reveal + capped ripple reveal; scan/pulse warp of the source; IQ bio palette + OkLab mix + blackbody warmth; vein glow, thin-film rim, split-tone; hue-preserving clamp → ACES → IGN dither; semantic alpha formula; depth relief; A field packing (vein, scan, reveal, alpha).
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): `fbm` calls hash12(floor(f)+fract(f)) == hash12(f), i.e. four octaves of white noise, so the `abs(field-0.5)` iso-band is per-pixel speckle, not veins. The next-better approximation of the same operator is smoothly interpolated value-noise fbm — same octaves/lacunarity/gains — whose 0.5 iso-line is a connected vein network.
  tactic 2 (physics one step further): a scanner's read head is a sweeping line that excites the tissue; fluorescent tissue keeps emitting after excitation and decays (a tail behind the head).
  tactic 3 (promote an intermediate): `scan` phase and `vein` are already computed; the sweep head reuses scanSpeed and lights only where vein > 0.
  tactic 6 (history it owns): A already stores reveal in .z but C is never read. Reading C.z exactly gives scan memory: tissue the cursor passed stays revealed and fades out.
ADD:
  1. Value-noise vein kernel — fix the degenerate hash fbm into interpolated value noise so veins are connected lines (same fbm structure, same organicScale role).
  2. Scan-head fluorescence — a bright horizontal read head sweeps down at scanSpeed; veins it crosses flare and decay with an exponential afterglow tail behind it.
  3. Reveal persistence from exact C.z — reveal = max(live, C.z · 0.95), so the cursor leaves a fading scanned wake; A packing unchanged.
FORBID on this file: springs, new ripple systems, new palettes, raymarching, new params, A packing change.
A PACKING: raw fields (vein, scan, reveal, alpha) — unchanged; C.z now read back as reveal history.
```

## sim-slime-mold-growth-em

```
SHADER: sim-slime-mold-growth-em
IDENTITY (one sentence): Physarum trail network (3-sensor agents, diffuse+decay) steered by the pointer's electric/magnetic field, with click ripples spawning orbiting negative charges.
KEEP VERBATIM: 4 params and roles (sensor_angle → sensor angle + charge strength, decay → decay + field vis, em_influence → agent count + EM steering, ripple_charge → randomness + secondary charge); electricField/magneticField; 50-agent 20-step 3-sensor loop; 3x3 diffuse × decay; mouse deposit; prior ideas (field-line deposit along E, opposite-polarity wipe); streamline overlay, core glow, hueShift by B; extraBuffer [133..138] pointer history; A packing.
MECHANISM INTERROGATION:
  t1 deepen kernel: the 3x3 box is a diffusion step; its taps also give a 5-pt Laplacian and a central-difference gradient of the trail for free.
  t2 physics one step further: real Physarum veins are tubes (gel ectoplasm wall, streaming endoplasm core) that contract rhythmically (shuttle streaming / peristalsis), and the colony advances by a fan-shaped pale search front.
  t3 promote an intermediate: the 3x3 taps are summed then discarded → keep them for Laplacian ridge + gradient.
  t6 history: C.r trail vs this frame's newTrail already tells whether a pixel is growing; C.g holds |E| from last frame.
ADD:
  1. Tube relief (endoplasm core / ectoplasm wall) — ridge = max(−∇²trail,0) brightens vein cores, |∇trail| darkens walls; uses the diffusion taps already fetched.
  2. Peristaltic shuttle streaming — a slow contraction wave travelling outward from the charge along veins (phase from log distance to the pointer), modulating vein brightness and, very slightly, vein decay (mass shuttles along the tube). Bass speeds the pulse.
  3. Advancing search-front fan — where newTrail > C.r (growth) and the gradient is steep, a pale-yellow plasmodial margin fringe on display.
FORBID: springs, IQ palettes, Gray-Scott, new params, replacing the agent loop, ACES on stored fields.
A PACKING: raw (trail, E mag, signed B, activity) — unchanged; ACES only on writeTexture.
FORMULAE: §12.2D-adjacent 5-pt Laplacian ridge (promoted intermediate), no table row reused verbatim.
```

## gen-biomechanical-hive-julia

```
SHADER: gen-biomechanical-hive-julia
IDENTITY (one sentence): fly-through of a hexagonal chitin hive whose every cell holds a morphing, cosine-coloured quaternion Julia core.
KEEP VERBATIM: map() (hex prism cell repeat, ribs, fbm biomass displacement, breathing, min with quaternionJuliaDE), the 8-iteration quaternion iteration and animated c, 100-step raymarch, mouse yaw/pitch camera, cosine hue on the core, spec+rim chitin, fog; params density/pulse/biomass/morph and their mappings.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): the march only returns t; the surface it lands on can be probed along n for crevice occlusion with the same map().
  tactic 2 (physics one step further): a bioluminescent core in a closed cell lights its own chamber walls — the chitin should catch the core's glow with distance falloff, pulsing with it.
  tactic 3 (promote an intermediate): the quaternion iteration computes the orbit q_i and throws it away; its minimum distance to a trap is a vein texture of the organism itself.
  tactic 6 (history): C is unused; no history idea — A gets display RGBA for the engine.
ADD:
  1. Orbit-trap veins on the Julia core (§12.2E orbit trap) — min |q.xyz| trap from the file's own iteration, glowing veins that pulse.
  2. Step-count AO in the hive chambers (§12.2E step AO) — 5-tap occlusion with map(), darkening rib grooves and wall/core junctions.
  3. Core bioluminescence on the chitin (§12.2F soft inverse-square) — wall emission from the cell's own core at the cell centre, I/(d²+r0²), tinted by the core hue, riding the pulse.
FORBID on this file: different fractal, IQ palette swap, springs/ripples, scanlines, liquid sim, new params.
A PACKING: ACES display RGBA (C unused); depth = t/100 unchanged.
```

## lenia-on-video

```
SHADER: lenia-on-video
IDENTITY (one sentence): continuous Lenia (ring kernel + bell growth) living on the video, its μ/σ driven by video luma/sat, neon bioluminescent CA composited over the footage.
KEEP VERBATIM: leniaKernel ring + leniaGrowth bell; video→μ (luma) and video→σ (sat); 2026-09-12 ideas (luma-gradient anisotropic kernel, |∇A| membrane); bass-beat injection; mouse spawn/clear; ripple species rings; leniaColor HSV map + 4-tap bloom; 4 params (kernel radius / video coupling / glow / composite mix) and roles; A packing (density, neighborhood, growth*0.5+0.5, video luma).
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): the single smooth ring is Chan's B=1 kernel; Lenia's larger species use multi-shell kernels with β peak weights (e.g. β=[1, ½]).
  tactic 2 (physics one step further): the video is the food field; what changes in food is motion — a feeding organism follows fresh food.
  tactic 3 (promote an intermediate): growthSignal is computed and stored but only packed into A.b; its sign says which rims are advancing vs retreating.
  tactic 6 (history already owned): C.a stores last frame's video luma and is never read — |luma − C.a| is a free motion map.
ADD:
  1. β-weighted second kernel shell — outer ring at r≈0.82 with weight ½·kernelRadius param, so wide kernels grow multi-ring (Chan β=[1,β₂]) organisms.
  2. Motion-fed growth — |vidLuma − C.a| (exact C load) adds a small positive growth bias scaled by video coupling: creatures feed on/drift toward movement.
  3. Growth-front shading — positive growth brightens the leading rim warm-white, negative growth dims/cools decaying tissue (display only).
FORBID: springs, IQ palette, Gray-Scott, new params, changes to μ/σ mapping, ACES on stored fields.
A PACKING: raw (density, neighborhood, signed growth, video luma) — unchanged; ACES on writeTexture only.
```

## data-slicer

```
SHADER: data-slicer
IDENTITY (one sentence): the source image cut into horizontal tape/data slices that jitter sideways, with curl-rotated RGB split, voronoi cracks, quasicrystal shimmer and a racing horizontal packet.
KEEP VERBATIM: fp128 slice phase (sliceIndex/localY); fbmJitter + wave1..3 + sliceBend displacement; voronoi cellEdge and quasicrystal term; slice_packet with C smear; curl-rotated R/B split; glitch tints, click rings, sparkle; params slideSpeed→jitterSpeed, sliceHeight→sliceThickness, chaos→chaosAmount (held ×1.35), aberration→colorSplit; ACES; alpha/depth formulas.
MECHANISM INTERROGATION:
  tactic 1 (deepen kernel): each slice is a rigid horizontal offset of one row band; a real sliced data stream also loses precision per packet, not just position.
  tactic 2 (physics one step further): when two adjacent tape/data rows shear apart, the boundary shows a torn seam where both rows' content overlap and a sync gap reads dark.
  tactic 3 (promote an intermediate): sliceIndex, localY and the per-slice fractalDisplacement are computed and thrown away after one sample — reuse them for seams and per-slice corruption.
  tactic 6 (history): C is display RGBA read by the packet smear; unchanged — dropout tails read nothing new.
ADD (3 native ideas):
  1. Torn slice seams — within a thin band at each slice boundary, re-sample with the NEIGHBOUR slice's jitter and add a dark sync-gap line; the cut becomes a physical tear whose width grows with chaos.
  2. Per-slice bit-crush (§12.2B block DCT quantization, adapted): hash(sliceIndex, jitter tick) selects corrupt slices that are block-pixelated horizontally and quantised to few levels; probability rides chaos, block width rides sliceThickness.
  3. Dropout bursts (§12.2B): rare slices get a white/black streak starting at a random x with an exponential tail along the slice; rate rides chaos + bass.
FORBID on this file: springs, new ripple system, IQ palette, thin-film, new params, B writes.
A PACKING: ACES display RGBA (unchanged; C read as colour by the packet smear).
```

