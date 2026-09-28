# BRIEFS — Densest Crystal/Chrome Nine (2026-09-27)

Idea Cards drafted by the coordinator from three read-only audits of HEAD, before any WGSL edit.
Out of scope: gen-chrono-kinetic-fractal-engine (2026-09-15 Ideas already in body).

## gen-bismuth-hyper-crystals

```
SHADER: gen-bismuth-hyper-crystals
IDENTITY: a raymarched field of stepped boxes folded by a KIFS abs-fold loop with an xz rotation, shaded with the
  existing cosine iridescence palette, Blinn specular and step-count AO — a growing bismuth hyper-crystal.
KEEP VERBATIM: rot (L30), abs-fold + box map structure (L36-63), the stepping term floor(length(p)*10)/10 as the
  bismuth staircase (may soften its normal spikes), iridescence() palette (L75) as the base colour, 4 slider roles
  (x Complexity = fold count, y ColorShift = palette phase, z GrowthSpeed = rotation/growth, w Specular), saved params.
FIX/WIRE (major first):
  - HEAD CAMERA INSIDE GEOMETRY: at t=0/bass=0 the fold fills a cube of half-size ~n+1, so map(0,0,-5) < 0 for
    Complexity >= ~0.2 INCLUDING the default 0.5 -> every ray hits at step 0, frame is one flat colour. Pull the camera
    back / bound the fold region so map(ro) > 0 for x in {0,0.5,1}; prove with a numpy port of map() (camera outside,
    a surface exists in view).
  - uv not flipped (L88-91): screen top = -y -> flip.
  - z GrowthSpeed: rotation = config.x*z*0.1 (L49) -> phase jumps when the slider moves; accumulate phase as time*const
    with z scaling something continuous, or keep but make growth idea carry the slider (explain).
  - w Specular: exponent w*100 (L127) -> pow(x,0)=1 white sheet at w=0 and pow(0,0) undefined; floor the exponent (e.g.
    max(w*100, 2)); default 0.8 must stay 80.
  - Audio from extraBuffer[0] (L42) -> plasmaBuffer[0].x; FFT read extraBuffer[4u+bin] (L130) is off by one -> 5u+bin.
  - No A write, no depth, no C read, no ACES (gamma only, specular clips), alpha 1.0. Add: A = HDR + alpha, exact C
    read (a light temporal blend is optional, not an idea), depth near 1/miss 0, ACES on writeTexture, semantic alpha.
  - Integer fold count i32(x*5+3) pops (L46) — folded into idea 2.
ADD (native ideas):
  1. Nucleation seed under the cursor — HEAD computes distToMouse (L40) and never uses it. Map the pointer to a seed
     point in the crystal and let the fold offset (1.0 at L47) shrink with distance to the seed, so the crystal is
     densest/finest where it nucleates and coarsens outward. Default mouse (0.5,0.5) = a centred seed that reproduces
     roughly the HEAD structure.
  2. Fractional fold growth — the crystal actually grows: blend fold iteration n and n+1 by a fractional growth phase
     (Complexity picks the base count continuously, GrowthSpeed advances the growth cycle), so new terraces of folded
     boxes emerge smoothly instead of popping.
  3. Fold-lineage colour — record the sign-flip history (which abs() planes flipped, per iteration) inside the fold
     loop and offset the EXISTING iridescence palette phase by that lineage, so sibling crystals of the same fold
     branch share a hue family.
FORBID: thin-film/oxide/tarnish, hopper terraces, twin seams, melt-pool bands, axial beacon, self-assembling sectors,
  spring cursor, ripple rings.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha.
DEFAULT-LOOK SHIFT: HEAD is one flat colour at default; now a visible crystal. Not GPU-verified.
```


## gen-celestial-nanite-swarm-nebula

```
SHADER: gen-celestial-nanite-swarm-nebula
IDENTITY: a fixed-step volumetric march through a nebula of 3D Voronoi nanite cells (F1) and constellation links
  (F2-F1), blended with a repeating box lattice ("geometric order"), emissive cyan/magenta/gold.
KEEP VERBATIM: hash3/voronoi (L30-60), map_density structure (cells + links + lattice, L62-106), emission colours
  (L138-160), ACES (L108,175), coverage alpha (L174), depth convention (L169), 4 slider roles (x Swarm Density,
  y Constellation Link, z Wind Speed, w Geometric Order), saved params, updatedParams.
FIX/WIRE:
  - Corner NaN: bg = ...*(1 - length(p)*0.5) (L163) goes negative for length(p) > 2 (16:9 corners) and pow(col,0.8)
    (L166) -> NaN. Clamp with max(...,0).
  - Mouse attractor: drift is added to pos (L71-72) BEFORE comparing to mouse_pos, so the pull point swings +-2 units
    off the cursor; x not aspect-corrected. Compare in undrifted space, aspect-correct.
  - z Wind Speed: config.x*(0.2+z*0.5) (L69) -> phase jumps when the slider moves; acceptable only if unavoidable —
    prefer drift = time*0.2 + time*z*0.5 still jumps; use a slider-independent base phase and let z scale drift
    amplitude/advection direction, or document. Do not introduce a new jump.
  - Fake "chromatic aberration" (L170-171) is a flat tint: either make it a real per-channel offset or rename the comment.
  - smoothstep(0.5, 0.0, ...) (L97) reversed edges -> 1.0 - smoothstep(0.0, 0.5, ...).
  - Ray stops at t<=6 (60 steps x <=0.1): fine to leave; note it. No A-read (C unused): optional light trail only.
  - JSON features [] -> the true tags.
ADD (native ideas):
  1. Kuramoto nanite sync — voronoi() discards the cell id (hash3(n+g)). Return it, give each nanite a natural
     frequency and phase, and pull the phases toward a shared mean-field phase with a coupling that rises with
     Geometric Order (stateless: phase_i = mix(own, global, K) with a travelling offset), so nanite blinks lock into
     sweeping synchronised waves as order rises. Visible with audio = 0; bass may kick the coupling.
  2. Lattice self-assembly — fuse the Voronoi field with the box lattice (L91-97): as Order rises, pull each cell's
     feature point toward the nearest lattice edge/node, so the swarm physically assembles onto the megastructure
     instead of the two fields cross-fading.
  3. (optional) Absorption dust lanes — Beer-Lambert extinction in the emission-only march from link density, so dark
     filaments silhouette between bright cells.
FORBID: spring cursor, ripple rings, IQ palette, thin-film, Strömgren ionization, boids.
A PACKING: ACES display RGBA (HEAD) — keep, document.
DEFAULT-LOOK SHIFT: corners no longer NaN; blink pattern now synchronised waves. Not GPU-verified.
```


## gen-chromatic-singularity-loom

```
SHADER: gen-chromatic-singularity-loom
IDENTITY: thin cylinder threads repeated by a fold-and-rotate loop, pulled by a 1/r^2 gravity warp toward a
  mouse-placed singularity sphere, coloured by a chromatic lensing term with accretion glow/bloom.
KEEP VERBATIM: rot, map structure (thread cylinder length(pos.xz)-0.05, fold/rotate loop, singularity sphere,
  L51-85), gravity warp 1/r^2 concept (L57-63), chromatic shift term, accretion glow, ACES (L37,87), slider families
  (x mass, y fold/weave, z accretion glow, w chromatic shift; applyGenerativePrimaryControls may be kept), saved params.
FIX/WIRE (major first):
  - HEAD BLACK AFTER ~0.1 s: plasma_index = min(u32(dist*10 + time*10), 255u) (L139) reads plasmaBuffer[1..255]
    (zero / OOB) -> plasma_color = 0 -> col = 0. Replace with a real colour source (the existing chromatic lensing term
    driven by dist/time, tinted by plasmaBuffer[0].xyz).
  - y fold count i32(y) (L66-68): y in (0,1) -> 0 iterations at the default 0.5 (no weave); y=0 -> 4. Map to a
    continuous count (e.g. 2 + y*4 with fractional blend).
  - audio_intensity = u.config.y (L104) is rippleCount -> plasmaBuffer[0]; mid unused.
  - Gravity warp uses normalize(pos) (L63) = direction from the ORIGIN, not from center, unbounded mass/dist^2 ->
    use pos-center, clamp the pull, scale step (relaxation) for the non-Lipschitz map. Centre mouse -> no NaN.
  - rot(time*0.2*chaos) (L74) audio/click-scaled time -> phase from time only.
  - C read with textureSampleLevel + sampler (L159) and only on hit pixels -> exact textureLoad, every pixel.
  - Depth dO/MAX_DIST (L167) inverted -> near 1, miss 0.
  - Mouse y inverted (L54/L137 flip vs unflipped uv L102): flip uv so screen top = +y and make mouse consistent.
  - The ==0 slider substitutions (L57, L142, L152) are fine to keep (saved defaults are 0.5).
ADD (native ideas):
  1. Spaghettification necking — fuse warp and threads: thread radius (0.05) and brightness follow the local warp
     strength mass/dist^2 at that point, so threads visibly neck thin and stretch as they fall toward the singularity
     and fatten far away.
  2. Warp/weft parity — map() already returns a material channel (L84) that nobody reads. Record the fold index /
     parity of the nearest thread inside the fold loop and shade even/odd families as two thread colours (warp vs
     weft), so the folded threads read as a woven loom.
  3. (optional) Orbital accretion trail — read C exactly at a coordinate rotated slightly around the projected
     singularity (Keplerian-like angular advection, faster near the centre) and blend with a real weight (HEAD's
     ~2.4% is invisible), so light spirals in toward the singularity.
FORBID: photon ring, Doppler beaming, gravitational redshift, lensed far-side halo, singularity shadow, self-assembling
  sectors, time dilation (sibling gen-bismuth-singularity-loom-engine), heddle lanes, plasma shuttle, over-under
  interlacing, thread thin-film, IQ palette as the whole look.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha (HEAD already stores pre-ACES in A).
DEFAULT-LOOK SHIFT: HEAD black after 0.1 s and 0 folds at default; now a visible woven thread field. Not GPU-verified.
```


## gen-chrono-kitsune-prism-weaver

```
SHADER: gen-chrono-kitsune-prism-weaver
IDENTITY: a fox-spirit seen from the front — a sine-wobbled sphere body at z=5 with 3-9 tapered tails fanning radially
  and streaming away with a travelling weave, a volumetric glow shell and a radial HDR echo feedback.
KEEP VERBATIM: mapKitsune body + tail loop (L85-111), tetrahedral calcNormal, bounding-sphere early-out (L178-182,
  Batch 37 optimizer), glow accumulation (L191-206), echo feedback structure (L237-251, textureLoad C), ACES on display
  only, 4 slider roles (x prism_hue_shift, y tail_count, z weave_tightness, w chrono_echo), saved params/updatedParams,
  FFT reads extraBuffer[5..12] (legit read-only).
FIX/WIRE:
  - Depth inverted (L254-255: t/FAR_CLIP on hit, 1.0 on miss) -> near 1, miss 0.
  - uv not flipped (L162) while mouse is flipped "bottom-up" (L147) and the light (1,1,-1) ends up lighting from
    screen-bottom -> flip uv so screen top = +y; mouse and light consistent.
  - Step exhaustion shaded as hit (L210 hit_surface = in_bounds && t < FAR_CLIP) -> require d < SURF_EPS (or a
    loose threshold) for a hit.
ADD (native ideas):
  1. Body prism, tails as spectral bands — mapKitsune only returns material 1/2 (L110). Return the nearest tail index
     too; the body is the prism: light entering the body leaves split into discrete spectral bands, one band per tail
     around the fan (red..violet), with Prism Hue Shift rotating the band order. The body stays white-hot/clear.
  2. Heartbeat transfer — couple the body's sine wobble (L88-91) to the tail weave: a pulse born in the body travels
     out each tail with a delay proportional to distance along the tail (tp.z), swelling tail radius and glow as it
     passes, so the body's heartbeat visibly runs down the nine tails.
  3. (optional) Tail unfurl — y maps via floor(p*9) clamped 3..9 (L159), so 0.1..0.333 is dead and each step pops.
     Use a fractional count: the newest tail grows in length/opacity continuously. At default 0.8 the tail count must
     stay 7 fully grown (check numerically).
FORBID: kitsunebi/fox-fire wisps at tail tips, nine-tail thin-film, Cauchy glass armour, spring cursor, ripple rings,
  IQ palette stamp, the (missing) chrono-void lattice as a new system.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha (HEAD) — keep.
DEFAULT-LOOK SHIFT: image now upright; tails spectrally banded. Not GPU-verified.
```


## gen-chronodynamic-aether-weaver-automata

```
SHADER: gen-chronodynamic-aether-weaver-automata
IDENTITY: a 2D clockwork loom — two rotating sdGear gears (12 and 8 teeth) with metallic banding and edge glow,
  crossed by sine+noise "aether" thread splines with node glints, echo trails and a chromatic smear.
KEEP VERBATIM: sdGear (L60-65), the two gears' placement/teeth/rotation sense (L106-117), metallic banding + edge glow,
  thread spline formula family (L124-148), node glints, 4 slider roles (x thread_count, y loom_rotation_speed,
  z aether_bloom, w temporal_decay), saved params/updatedParams. applyGenerativePrimaryControls may stay but must not
  double-map a slider into something unrelated (document if kept).
FIX/WIRE (major first):
  - THREADS DEAD: i32(u.zoom_params.x) (L120) = 0 threads for every x < 1.0 (default 0.5!). Map x to a real count,
    e.g. 2 + x*10 (default -> 7), fractional last thread fading in.
  - Audio from u.config.y (L81 = rippleCount) feeding thickness/glow (L132,142,144) -> plasmaBuffer[0].xyz.
  - Thread colour reads plasmaBuffer[0..255] (L138-139) -> black/undefined. Use a real per-thread colour.
  - "Previous frame" is readTexture (L164: the input photo) and the chromatic smear samples readTexture (L178-182),
    mixing 20-35% of the user's photo into a generative shader -> use exact textureLoad(dataTextureC) for echo/smear.
    Fix the back_uv=1.0 off-edge read.
  - Mouse "click" test mouse.x>0 && mouse.y>0 (L96) is ~always true -> use zoom_config.w for held.
  - y rotation: time*speed (L106/108) phase jump when the slider moves -> accept only if documented; prefer a
    continuous base spin plus slider.
  - Reinhard + pow + gain up to 1.45 (L171) -> ACES on display. Alpha 1.0 (L189) -> semantic.
  - A packing lie: A = (thread.r, thread.g, gear.b, 1) (L191) while C is read as colour -> display-consistent HDR RGBA.
  - Depth: glow-based unclamped (L188) -> gear coverage (gears near, threads mid, void 0).
  - JSON description "" and features [] -> fill honestly (params untouched).
ADD (native ideas):
  1. Gear-tooth automaton ring — each tooth of each gear is a cell of a 1D elementary cellular automaton; the ring
     advances one generation per tooth pitch of rotation (stateless: Rule 90 from a single seed via the Lucas/bitwise
     test cell(i,g) = ((g+i)/2 & (g-i)/2)==0 with parity, or equivalent), live teeth glow/extend. The meshing contact
     tooth of gear 1 seeds gear 2's ring, so the two gears pass the pattern like a clockwork computer. This makes the
     "automata" in the name real.
  2. Capstan wrap — the threads bend along the gradient of the gear SDF and wind onto the rotating hubs (tangential
     deflection within a band around each gear, advancing with the gear angle), so thread field and gear field become
     one mechanism instead of two overlaid layers.
FORBID: heddle lanes, plasma shuttle, warp thread-memory ghosting, over-under interlacing, escapement tooth gates,
  backlash lag, Keplerian gearing, spring cursor, ripple rings, IQ palette stamp.
A PACKING: HDR display RGBA + semantic alpha; C read exactly as colour history (echo trails).
DEFAULT-LOOK SHIFT: HEAD had 0 threads at default and a 20-35% input-photo tint; now threads + automaton teeth,
  no photo bleed. Not GPU-verified.
```


## gen-crystalline-chrono-dyson

```
SHADER: gen-crystalline-chrono-dyson
IDENTITY: a raymarched Dyson sphere seen from a mouse-orbit camera — crystal panels on a radius-2 shell (Worley-modulated
  fract panels), a domain-warped FBM quasar core, KIFS box fractal, torus conduit, an octahedron satellite and radial
  capsule spokes, with Fresnel/Beer-Lambert shading, fog, chromatic feedback and click rings.
KEEP VERBATIM: shell + panel construction (L133-138), quasar FBM core (L140-141), KIFS box (L124-131), torus conduit
  (L143), smooth-union chain (L152-158), shading family (L192-209), feedback with dispersion (textureLoad C), click
  rings (HEAD — keep, not an idea), ACES on display, depth, 4 slider roles (x panel_density, y quasar_glow, z flux_speed,
  w swarm_count), saved params.
FIX/WIRE:
  - uv not flipped (L172) though L175 claims screen-top = +Y -> flip.
  - Pole NaN: mouse y = 0 or 1 -> my = +-pi/2, ro parallel to up, cross()=0 -> normalize(0) NaN (L179). Clamp pitch.
  - Spokes (L149-151): sector angle folded but q never rotated into the sector; both capsule endpoints take q.y ->
    unbounded in y, sheets not spokes, non-Lipschitz seams. Rotate into sector, bounded capsule quasar->shell.
  - t = time*flux (L119) phase jump on slider move -> document or use accumulation-free alternative.
  - Full t += d (L189) through non-Lipschitz map (fract panels, noise added to distances) -> relaxation factor.
  - Dead kifsFold (L89) — may use in an idea or delete; volumetricFog ignores p/ro (L110) — fix or note.
  - Miss background hash3(rd).x static noise (L210) -> sparse stars (hash thresholded) is fine as floor.
ADD (native ideas):
  1. Statite swarm — Swarm Count (w) today only makes depth stripes sin(t_hit*swarm) (L209). Replicate the single
     octahedron satellite (L145-147) into w-count statites riding the conduit orbit by polar repetition (one SDF
     evaluation per sample, not a loop of 100), with a golden-ratio (PHI already at L146) phase spread and inclination.
     The slider now counts a swarm. Keep the stripes if they still read, or retire them into the statites (explain).
  2. Power-grid pulses — once spokes are real capsules, return the capsule parameter h (sdCapsule L94) and send
     emissive packets outward quasar -> spoke -> torus conduit (and along the conduit), fusing three existing
     subsystems into one energy-harvest circuit; packet speed from flux_speed.
  3. (optional) Louvered panels — each Worley panel cell (w.y seam) opens/closes on its own phase, leaking quasar light
     through open louvres.
FORBID: Keplerian gearing, Doppler beaming, photon ring, ripple rings as idea, thin-film, spring cursor, IQ palette,
  Cauchy facet fire, time-fault seams.
A PACKING: clamped HDR linear RGB (pre-ACES) + semantic alpha (HEAD) — keep.
DEFAULT-LOOK SHIFT: image upright; spokes become 8 real spokes; statites around the conduit. Not GPU-verified.
```


## gen-crystalline-nebula-weaver-void-spider

```
SHADER: gen-crystalline-nebula-weaver-void-spider
IDENTITY: a raymarched crystalline spider (ellipsoid body + abdomen, legs) hanging on web threads and a lattice of
  web nodes, in front of a 2D fbm nebula, with march glow, click rings and A/C feedback.
KEEP VERBATIM: hash3/vnoise/fbm (L31-65), palette (L68) as HEAD's nebula colouring (not a new stamp), body/abdomen
  ellipsoids (L84-90), smin, displace concept (L110), calcNormal, hueClamp, aces on display, A=pre-ACES HDR with exact
  C read, ripple rings (HEAD, not an idea), 4 slider roles (x web_complexity, y gravity_distortion, z plasma_intensity,
  w void_depth), saved params/updatedParams.
FIX/WIRE:
  - Step exhaustion shaded as hit (L191, L239) -> require d < eps.
  - thread2 dot grid computed at p*2*wc but divided only by wc (L107) -> distance 2x too large; fix the scale.
    The grid fills all space and grazing rays exhaust steps — idea 1 gates it, also bound it.
  - displace() adds scalar vec3(fbm) (L112) -> only a (1,1,1) diagonal shift; make it a real 3D warp (vector fbm or
    gradient) or document; keep gravity_distortion as its amount.
  - uv not flipped (L155); light at +y lights from screen bottom -> flip uv, keep mouse consistent.
  - zoom_config.w unused while JSON claims a hold-lunge: optional (only if cheap: hold pulls camera in via void_depth).
ADD (native ideas):
  1. Nebula-condensed web nodes — gate the thread2 node grid by the SAME fbm density that paints the nebula (sampled
     at the node cell centre), so web nodes only exist where the gas is dense: the web crystallises out of the nebula,
     and the march glow accumulator (L179) makes the condensing nodes glow. Fuses the web and nebula subsystems.
  2. Metachronal eight-leg gait — replace the one mirrored box leg pair (L91-93) with four leg pairs placed by polar
     (angular) repetition around the body, each leg a two-segment capsule bent at a knee, lifted in alternating
     tetrapod phase (legs L1,R2,L3,R4 vs R1,L2,R3,L4) on a time phase; bass may scale stride amplitude, never phase.
     Makes the JSON's gait claim true.
  3. (optional) Spinneret dragline — thread1 is an infinite axial cylinder (L105): anchor it at the abdomen tip and
     let it sag under gravity_distortion (catenary-ish bend), so the spider hangs from its own silk.
FORBID: plucked standing-wave strings, dew beads, silk afterglow via C, agate banding, thread-tension sheen,
  over-under interlacing, thin-film, photon ring, lensed halo, spring cursor, IQ palette as a new stamp.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha (HEAD) — keep.
DEFAULT-LOOK SHIFT: image upright; exhaustion no longer painted as surface; web nodes clustered in nebula; 8 legs.
  Not GPU-verified.
```


## gen-cybernetic-crystalline-neuro-lattice

```
SHADER: gen-cybernetic-crystalline-neuro-lattice
IDENTITY: an infinitely repeated raymarched cell where a gyroid sheet smooth-blends with 4-fold IFS crystal boxes,
  cyan crystal "nodes" vs magenta gyroid "links", fog, mouse-held bend/shock, ripples, A/C feedback.
KEEP VERBATIM: rot3D, sdGyroid (L42-45), ifsCrystals (L48-56), map's smooth blend and material id (L84-94), node/link
  colour scheme (L172-196), fog, ACES on display, A=HDR with exact C read, ripples (HEAD, not an idea), 4 slider roles
  (x node_density = cell size, y growth_speed, z glitch_intensity, w neon_hue_shift), saved params/updatedParams.
FIX/WIRE:
  - Float % sign bug (L85): WGSL float % keeps the dividend sign -> q never centred for negative coords -> seams on the
    x=0 and y=0 planes through the screen centre. Use p - c*floor(p/c + 0.5).
  - Treble rescales the cell (L83) -> distant cells swim; audio must not change the lattice period. time = config.x +
    audio.y*0.1 (L76) audio jitter on rotation phase -> remove.
  - Camera can start inside geometry / step exhaustion shaded as hit (L154, L230) -> hit only if d < eps; if the camera
    is inside, handle (e.g. start the march past the containing surface or keep the camera in a carved channel).
  - Rodrigues hue rotation uses (1,1,1)/3 (L176) -> k=(1,1,1)/sqrt(3); apply the hue shift to links too if cheap.
  - Mouse-held shock centred on the screen, not the cursor (center L206 unused) and negative shock subtracts colour
    (L209) -> centre on the pointer, clamp >= 0. Mouse y inverted (L64 flip vs unflipped uv L128) -> flip uv, consistent.
ADD (native ideas):
  1. Nucleation front — a spherical growth front sweeps outward from the origin (period set by growth_speed, which
     keeps its rotation role too): cells behind the front have converted gyroid melt -> IFS crystal (the smooth-blend
     weight h biased toward the crystal), cells ahead are still liquid gyroid, with a bright freezing rim at the front.
     Fuses the two existing subsystems through the existing blend.
  2. Memory-crystal bit states — compute the cell index floor(p/cell + 0.5), hash it per time slice, and switch each
     cell's crystal on/off like a stored bit (off cells are gyroid-only / dim). Glitch intensity sets the bit-flip rate,
     reviving the near-dead Glitch slider (at glitch 0 no flips: all bits keep the HEAD state).
  3. (optional) Light-piped links — return d_crystal from map so the magenta gyroid links glow by proximity to lit
     crystal nodes (exp(-k*d_crystal)), i.e. nodes light the sheet.
FORBID: Bragg colour, line-defect waveguides, action-potential runners, saltatory, synapse flash, integrate-and-fire,
  refractory afterglow, dendrite web, triple-junction glow, photoelastic fringes, cage lanterns, thin-film, spring cursor.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha (HEAD) — keep.
DEFAULT-LOOK SHIFT: centre seams gone; image upright; growth front and bit states visible. Not GPU-verified.
```


## gen-cybernetic-liquid-chrome-engine

```
SHADER: gen-cybernetic-liquid-chrome-engine
IDENTITY: a camera travels down an x/z-repeated hall of engine cells — base box, surging capped-cylinder piston,
  KIFS-folded core — joined by exponential smin and shaded as liquid chrome with core glow, streaks and advected C history.
KEEP VERBATIM: cell repeat (L70-72), base box / piston / KIFS core construction (L74-103), exp smin, glow accumulation
  (L106), chrome pseudo-env shading (L210-221), streaks, ripple clickDrive (HEAD, but fix its camera use), advected C
  history (L245-250), ACES on display, depth, 4 slider roles (x intensity, y speed, z scale, w mouseInfluence),
  saved params/updatedParams.
FIX/WIRE (major first):
  - Phase jumps: cameraTravel = config.x*(1.6 + speed*6 + audio*1.8) (L163) multiplies absolute time by bass -> the
    camera teleports with the music; map t = config.x*mix(.45,2.8,speed) (L66) jumps when Speed moves. Use
    time*base_rate for phase; audio may scale amplitude/glow, never phase. (Speed may still scale rate — document the
    slider-move jump if kept, it's HEAD behaviour; audio must not.)
  - clickDrive computed per pixel and added into cameraTravel (L163) -> discontinuous ring in the image. Make the
    camera per-frame (pixel-independent); keep click influence as a shading term.
  - Camera flies through the piston column every cycle (x=0, y in [-1.3,2.6]) -> t=0 full-frame flash. Offset the
    camera lane between cell columns (x = 4) or above the pistons; verify with a numpy port of map() along the path.
  - uv not flipped (L135) -> base box renders at the top. Flip.
  - "Chromatic aberration" comment (L141-146) is a monochrome barrel scale: fix comment or make it real.
  - rotX/rotY duplicate (L36-46): fix if rotY is meant to rotate y.
ADD (native ideas):
  1. Firing-order crank — the piston phase today uses an arbitrary p_in term (L94). Use the cell index floor(xz/8) to
     assign each cell a cylinder slot in a real 1-8-4-3-6-5-7-2 firing order, so the pistons along the hall fire in a
     visible travelling sequence like a crankshaft. Bass may scale stroke/throttle amplitude, never the phase.
  2. Compression ignition — fuse piston and KIFS core: the piston height drives the core's fold offset (L78) so each
     stroke crushes the fractal, and the core glow (L106) flashes at top dead centre like a diesel ignition, decaying
     over the power stroke.
  3. (optional) Heat shimmer — perturb rd (or the C history lookup) by a small noise scaled by the local ignition
     flash above firing cells, so hot air wobbles over the pistons that just fired.
FORBID: conductor Fresnel on liquid gold, Rayleigh-Plateau beading, neon rivers, meniscus rims, viscous stir memory,
  ferrofluid spikes, escapement/backlash, thin-film, spring cursor, ripple rings as idea.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha (HEAD) — keep.
DEFAULT-LOOK SHIFT: image upright; no teleports or full-frame flashes; sequential firing. Not GPU-verified.
```

