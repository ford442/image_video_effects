# BRIEFS — fork B (gen-neuro-cosmos, cosmic-web) — sonnet/batch-50

Written BEFORE any WGSL edit. Baselines: `scratchpad/b/gen-neuro-cosmos_head.wgsl` (= worktree HEAD, already on prelude) and `scratchpad/b/cosmic-web_head.wgsl` (= worktree HEAD after the coordinator's codemod; does NOT compile) plus `cosmic-web_headfix.wgsl` (compile-fixed ONLY: `__finalRGB` renamed, duplicate `let rippleCount/aspect` removed; overlay left in) used as the "before" picture.

HEAD evidence gathered before writing this (256/384 px, SwiftShader, saved defaults, mouse 0.5,0.5 up, audio 0.3,0.2,0.1):
- gen-neuro-cosmos `nc_head.png`: smooth teal sheets/curtains, stdL 0.057, meanA 0.92. No neuron, no strand is legible.
- cosmic-web_headfix `cw_headfix.png`: a centred vortex with a screen-wide set of concentric rings (the stamped `clockRings`/`spectral` tail), meanL 0.40.
- numpy port (statistical, not bit-exact hash): HEAD `nodeMetric²` mean 0.0010, p99 0.014 (dead term); junction mask from F3−F1: mean 0.068, p99 0.905.
- hueShift of the two filament colours never goes negative (min component 0.138 / 0.308 over a full colorShift sweep) → no ACES-negative bug in cosmic-web's colour path (not claimed).

---

## SHADER: gen-neuro-cosmos

IDENTITY: an orbit-camera raymarched volume of glowing neuron somas joined by pulsing axon strands in a Voronoi lattice, read as a neural net that is also a cosmic web; a viewer must still see cyan strands, blue/white somas, deep-space purple haze.

KEEP VERBATIM: 4 params and roles (networkDensity → lattice scale, pulseSpeed → conduction speed, glowIntensity → haze glow, connectionThickness → strand/soma radius; mapping order unchanged); orbit camera with mouse yaw/pitch and `time = config.x*0.1` drift; `evoked` electrode (held pointer) + click fronts; all four shipped ideas: `saltatoryConduction()` node hops, `integrateAndFire()` soma spikes with refractory afterglow, activity-dependent pruning shadows, Hebbian reinforcement from `prevFrame.a`; palette (core/outer/synapse/bg); rim light; ACES on display; depth = t/20; A = ACES display RGBA (read back as `prevFrame.rgb` colour trail and `prevFrame.a` Hebbian memory — consistent, unchanged).

RESCUES (HEAD defects, default picture changes — loud):
- R1. The web is F2−F1 = the 2-D Voronoi *bisector surface*, i.e. foam membranes. Rays hit giant flat sheets (the teal curtains); somas float disconnected inside the cells; the comments' "strands" and "f1 parametrizes position along a strand away from the soma" are false at HEAD. Fix: keep the same 3×3×3 Voronoi seed search but track the three nearest seeds and take the web SDF as the distance to the three segments between them (axons between neighbouring somas = Delaunay-style strands). Then f1 really is the distance along the strand from the soma, as the shipped saltatory code assumes. Params keep their roles (scale = density, `w` = strand/soma radius; only the radius multiplier is re-tuned because a 1-D strand needs a thicker radius than a 2-D sheet to be seen).
- R2. `flash = exp(-fract(wave)*5)` with `wave = floor(nodeCoord) - time*speed*…` rises slowly then cuts to ~0 (reverse of an action potential; the comment says "fires, then decays"). Use `fract(-wave)`; hop timing/direction unchanged.

ADD (2 native ideas):
1. **Action-potential undershoot (after-hyperpolarization).** §12.1 tactic 2 (physics one step further): a real AP is spike → decay → undershoot below resting potential (node refractory). Behind each saltatory flash a hyperpolarized trailing zone (`u = fract(-wave) ∈ [0.3, 0.9]`) pulls the strand conduction glow below baseline, so each hop leaves a dark notch that recovers; belongs on THIS effect because the saltatory flash is the file's own spike and the pruning shadows already use darkness as the "inactive" language.
2. **Soft inverse-square somatic halo (§12.2F, owned by this file).** §12.1 tactic 3 (promote an intermediate): `map()` already returns the nearest-soma distance `f1` and cell hash for every march step but the march only uses them at the hit. Each firing soma (existing integrate-and-fire state, same threshold) feeds `I/(f1² + r0²)` into the existing volumetric glow accumulator in warm white — neurons that fire light the haze around them with a cored 1/r² (extracellular field), visible from a distance and not only on the surface.

FORMULA ADMISSION: row = Soft inverse-square (§12.2F lighting). Family: this shader's glow accumulator is an optical term (volumetric haze); consumes `f1` + hash the file already computes; no new state/binding/solver; deletion test both ways passes (without it the file is the same network; without the network it is not a neural net). Row used on this file only.

FORBID: springs/`extraBuffer` state, new ripple shockwaves (the `evoked` fronts already exist), IQ cosine palette, glitch/scanline costumes, re-adding any of the four shipped ideas, new params.

A PACKING: unchanged — ACES display RGBA (alpha = coverage/glow/evoked/reinforce).

### §12.1 mechanism interrogation
- T1 (deepen kernel): the lattice search is a nearest-seed finder; the next-better web operator on the same search is segment distance between the nearest seeds (a real graph) instead of the bisector. That is R1.
- T2 (physics): AP waveform has an undershoot; extracellular potential of a point source falls as 1/r² with a finite soma radius. → Ideas 1 and 2.
- T3 (promote an intermediate): `f1` and `cell_hash` per march step → Idea 2. Also the third-nearest seed (free in the same loop) → R1.
- T6 (history): C is read as display colour + Hebbian alpha. The one extra continuity it affords (the undershoot dims the strand, which lowers `activity` and so lets the existing Hebbian memory fade) is not added — no new continuity needed.

---

## SHADER: cosmic-web

IDENTITY: a multi-scale cosmic filament network in 3-octave Voronoi, dark voids, blue filaments with white cores, galaxy points, a gravity-well vortex under the pointer with accretion arms and click-launched compression waves; temporal feedback gives it persistence.

KEEP VERBATIM: 4 params/roles (warp_strength → fbm warp, filament_density → filament scale, flow_speed → time scale, color_shift → hue); fbm domain warp; 3-octave filament stack with per-octave `plasmaBuffer[(o%8)+1]` spectrum (Batch 17); void path through the same feedback mix (Batch 17); spring-damper well code (extraBuffer[133..138], Batch 17 — NOTE: library-wide, those slots are re-zeroed every frame so the spring currently degenerates to the raw mouse; pre-existing, not touched); accretion arms; click waves/flow; galaxy points on a jittered grid with `GALAXY_THRESH` and twinkle; temporal feedback (`DECAY`, `FEEDBACK`, integer history drift); chromatic shift; ACES on display; layered alpha; depth out. A = pre-ACES HDR temporal colour + temporal alpha (read back as `prev` colour history) — unchanged; ACES only on `writeTexture`.

RESCUES (loud):
- R1. **Does not compile in a real WebGPU engine.** (a) `let __finalRGB` (identifier may not start with `__`); (b) `let rippleCount` and `let aspect` are re-declared in the same scope as their first declarations (WGSL forbids same-scope redeclaration). (c) The tail of `main()` (added by an earlier batch) stamps `clockRings = sin(length(screenUV-0.5)*95 - time*…)` + an IQ-cosine `spectral` palette + a second click-front loop on the *final* colour: a screen-wide concentric-ring overlay (the rings in the headfix picture), plus a click front whose age mixes `time` (= config.x × flow_speed) with `ripple.z` in real seconds, so it is mis-timed and duplicates the real `clickWave`. This is the generic overlay of §4 — it is REMOVED, not renamed. `writeTexture` = ACES display colour (as the Batch-17 comment intends). Before-picture = `cosmic-web_headfix.wgsl` (compile fix only).
- R2. HEAD's `nodeMetric = smoothstep(0.35, 0, f1) * density` marks cell *cores* (f1 ≈ 0 = a void's seed point) where density is lowest, so the "cluster nodes" term is effectively dead (numpy: mean² 0.001). Nodes are where ≥3 walls meet: F3 − F1 small. Fixed together with Idea 1 below.

ADD (2 native ideas):
1. **Junction clusters: filaments swell into nodes (F3−F1).** §12.1 tactic 3: `voronoi3` already visits all 27 neighbours; the third-nearest distance F3 is free. `junction = smoothstep(0.22, 0, F3 − F1)` on the base octave (replaces the dead f1 node mask, keeps the same warm node bloom term `nodeMetric²·(1.3+treble·0.5)`) and *also* thickens the filament density near junctions (`density += junction·0.35`): mass funnels along filaments into clusters, so filaments read as thin threads that bead up at junctions, the defining cosmic-web hierarchy (void → wall → filament → node). Native: it only re-uses the base-octave Voronoi the file already computes.
2. **Golden-angle galaxy groups aligned with the filament (§12.2E "Golden-angle layout", owned by this file).** Each galaxy of the existing jittered-grid field gets 4 satellites on a Vogel spiral (`θ = i·2.39996`, `r = c·√(i+½)`), stretched along the local filament tangent — the tangent comes free from the closest-two-seed vectors in the same Voronoi loop (wall normal = r₂−r₁, tangent = its perpendicular in the slice). Galaxies sit in groups, groups align with their filament (tidal-tensor alignment, §12.1 tactic 7). Satellites dimmer than the host and use the host's tint/twinkle; the group centre jitter is pulled to the cell interior [0.2, 0.8] so satellites are not clipped at the grid cell edge (host positions shift by ≤ 0.2 cell — stated).

FORMULA ADMISSION: Golden-angle layout (§12.2E, generative family; this file's galaxy point field is a dot field that already exists) — consumes `gCell/gPos/gRand` + base-octave Voronoi vectors; no new state; deleting it leaves the same web; deleting the web leaves unrecognisable dots → additive. Junction clusters are a native mechanism (not a §12.2 row; uses F3 from the loop already running). Row used on this file only.

FORBID: new springs, IQ palettes / concentric ring overlays (the ones removed in R1), additional click-ripple systems, any change to slider roles, ACES on stored A.

A PACKING: pre-ACES HDR `temporal` colour + `temporalAlpha` (unchanged); ACES on `writeTexture` only.

### §12.1 mechanism interrogation
- T1: the Voronoi F1/F2 pair is the wall detector; F3 (next-nearest) is the junction detector — the same kernel one step deeper.
- T2: gas funnels along filaments and shocks into nodes (hot WHIM/ICM gas); galaxies cluster in groups and align along filaments.
- T3: F3 and the seed vectors are computed and thrown away in `voronoi3`'s loop → promoted.
- T6: C is read as colour history with an integer drift; no extra continuity added (keep HEAD).
