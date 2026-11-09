# sonnet/batch-22 — fork D briefs (written before any WGSL edit)

Shaders: gen-chromatic-singularity-loom (2nd pass), gen-sentient-holographic-neuro-lace-matrix (3rd-ish pass; 7 ideas already).
All HEAD diagnostics were done on scratch copies (scratchpad/forkD/x/), never on the real files.
Renders at 192/288/384/576 px, idle cursor (0.5,0.5) and moved/held cursor, audio 0 and (0.4,0.3,0.2).

---

## 1. SHADER: gen-chromatic-singularity-loom

IDENTITY: a gravity-warped KIFS weave of thin light threads (warp/weft families by fold parity) around a lit singularity sphere under the pointer, with chromatic R/B hue split, ergosphere shear bands, a photon-ring shell and an orbital infall trail.

KEEP VERBATIM: 4 params + roles (x loom intensity = singularity mass AND primary intensity; y weave speed = fold count 2..6 + weave rate; z detail contrast = accretion bloom AND detail pow; w chromatic shift AND mouse influence — HEAD's dual use is kept); `map()` (1/r^2 warp, tidal thread neck, continuous fold count, parity flips, sphere union); Lipschitz-relaxed march; cos palette on hit z + time + family phase; tidal striation + heat; the existing 5 ideas (tidal spaghettification, weft/warp parity, orbital infall trail, ergosphere shear bands, photon-ring shell); `applyGenerativePrimaryControls` display chain; depth write (near=1, miss=0).

MECHANISM INTERROGATION
- Tactic 1 (deepen the kernel): the infall trail reads C with ONE nearest-pixel `textureLoad` at a rotated/pushed position. A semi-Lagrangian advection with nearest sampling at a multi-pixel angular step makes a train of discrete copies of the weave, not a smear. The next-better approximation of the same operator is a bilinear reconstruction of the same exact loads (still `textureLoad`, no sampler on the rgba32float history).
- Tactic 2 (physics one step further): the effect has a spinning ergosphere (shear bands rotating with +azimuth) and a lensing mass. The first-order side effects of light from matter orbiting a mass are (a) relativistic Doppler beaming — the approaching limb is brighter and blue-shifted, the receding limb dimmer and red-shifted — and (b) gravitational redshift — light from deep in the well arrives redder. HEAD has neither: the left/right and near/far of the weave are statistically identical.
- Tactic 3 (promote an intermediate): `az`, `dist_center`, `mass`, `shear` are already computed in the hit block; both new ideas consume them (Doppler needs `az`, redshift needs `dist_center`). The thread SDF gradient (surface normal) is computed by nobody — the threads are flat-shaded palette ribbons (measured in a normal/material debug render: crisp ribbon weave, zero volume cue).
- Tactic 6 (history): C is read as HDR colour history (A = pre-ACES hdr, same domain) — packing is consistent; no packing change. Only the *sampling* of the history changes (R1).

RESCUE
- R1 infall-trail copies. At HEAD the angular step is `0.035/(rr+0.15)` rad per frame (0.08 rad at rr=0.3, = 4.5 px at 192 px, 14 px at 576 px) read with nearest sampling. The result is ~10 stacked rotated copies of every thread (decay 0.8–0.92) with sawtooth edges that merge into filled polygons — "blocky streaks" — and the screen is meanA 0.58–0.69 flat colour. With history disabled (scratch) the same frame is a crisp weave with black gaps (meanA 0.42). No per-block hash mosaic is present; there is no early return on C≈0. Fix: step `0.035 → 0.014`, bilinear reconstruction of the same exact loads; infall push (1.012), decay, max-composite, packing all unchanged. Default look changes (cleaner weave, shorter smooth comet tails); documented as RESCUE, not an idea. Scratch variants at 288 px: 0.011/0.02 bilinear both remove the stacked copies; 0.014 chosen between them.

ADD (2 ideas)
1. Relativistic Doppler beaming + gravitational redshift (tactic 2; not a §12.2 row). Beaming: the ergosphere rotates toward +azimuth, so the x<0 limb approaches the camera at β = 0.38/sqrt(r); intensity `D^2` with `D = 1/(1+β cos az)`, blended 60% so it stays a bias, blue-shift on D>1 / red-shift on D<1, applied to the shear bands, photon ring and the singularity's bloom (the orbiting emission). Redshift: threads and sphere shift toward amber with `g = sqrt(1 − r_s/r)`, `r_s = 0.55`, hue-only (the existing tidal heating keeps the brightness). Native: a lensing mass with a rotating ergosphere shows exactly these two asymmetries.
2. Chord-length emission profile on the threads (tactic 3: promote the SDF normal; optically-thin emissive filament). The threads are "strings of pure light": a thin emitter's brightness follows its chord length, `|n·v|`, so each thread gets a bright core and soft limbs. Normal from a 4-tap tetrahedron of the file's own `map()`, threads only, hit pixels only (4 extra map calls per thread hit). Deletion test: remove it → flat-shaded ribbons (HEAD). Remove the weave and keep the idea → nothing to shade, so it cannot replace the mechanism.

FORMULA ADMISSION: neither idea is a §12.2 row (the Fork D budget rows — Henyey–Greenstein, energy-conserving bloom — do not fit: HG on the loom's bloom is a ~0.07 radial term, invisible; no smooth-iteration escape loop exists). 0 rows used. Both consume quantities the file already has; no new state, binding or spring.
FORBID on this file: springs / click ripples, IQ palette, new params, replacing the fold weave or the sphere, extraBuffer state, changing the OkLab-less cos palette or the display chain.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha in A; C read as the same domain (unchanged).

---

## 2. SHADER: gen-sentient-holographic-neuro-lace-matrix

IDENTITY: flight down a channel of an endless teal gyroid lace — thin sheets that breathe with bass, bioluminescent depth fog, a camera-borne pull node that the pointer gathers the lace toward (hold = glowing neuron with vortex loops), amber conduction beads, holographic scanlines, a grid scanning line and data-corruption block glitches.

KEEP VERBATIM: 4 params + roles (x complexity = gyroid scale, y colorShift = cyan↔indigo, z growthSpeed = flight speed + wave rate, w specular); gyroid DE (`GYROID_LIP`, thick sheet, breathing wave); pull node + hold behaviour; step-count AO; haze/fog; node glow; vortex loops; bead trains; scanline overlay; the 7 existing ideas; camera path (`ro.z = −3 − t·z·0.5`, rd +z); ACES display; A = display RGBA, C not read.

MECHANISM INTERROGATION
- Tactic 1 (deepen the kernel): the "cybernetic grid scanning line" is a flat additive cyan bar in screen space — it lights the void and the lace identically. A projector's scan line lights the *volume it sweeps*: the next-better version of the same operator is a bar whose light is modulated by what it crosses.
- Tactic 2 (physics one step further): a nerve spike is not a symmetric sinusoid. In myelinated axons it is saltatory — the depolarisation jumps between nodes of Ranvier (internode dwell, fast hop) and is followed by a refractory tail. HEAD's beads are symmetric `pow(0.5+0.5 sin, 6)` lobes sliding at constant speed.
- Tactic 3 (promote an intermediate): `diff`, `ao` and `n` are already computed for the lit lace — the scan-lit idea reuses them; the bead idea reuses `p.z`, `bass`, `mids`, `strand`.
- Tactic 6 (history): C is not read and the camera flies, so a history echo would smear — no history idea added. Packing unchanged.

RESCUE (found on a second read of the code, before the lace WGSL was touched)
- R1 audio-multiplied time phases: `sin(p.z*16 - t*(4.0 + bass*2.5))` (beads) and `sin(atan2(..)*9 + t*(5.0 + bass*3.0))` (vortex loops) multiply TIME by an audio value, so at t = 60 s a bass change of 0.1 moves the phase by ~15–18 rad per frame: the beads and loops strobe/jump with the music instead of flowing (same class as the loom's HEAD "time * audio chaos"). Fix: constant phase rates (4.0 / 5.0); the audio keeps its amplitude role (`0.1 + mids*0.2`, `0.2 + 0.35*bass`), so at silence the picture is bit-identical.

RESCUE (otherwise none). Checked at HEAD (576 px idle + held + audio): no NaN, no blank/inverted frame, camera not inside lace, black region to the right at default is the real open channel axis (rays escape >MAX_DIST) as HEAD designed with fog. Open item (not changed): `ro.z` decreases while `rd.z=+1`, so the camera flies backwards relative to its view; the lace is homogeneous along z so it is invisible in stills — left alone (would change the whole motion feel, not an additive idea).

ADD (2 ideas — HEAD already carries 7, so the cap is 2)
1. Scan-lit lace with a trailing wake (extends "grid scanning line"). The flat cyan bar stays over the void; over the lace its light is modulated by the lit-lace term (`diff·ao`) so the bar reveals strands instead of painting over them, and an exponential afterglow trails behind the sweep (sweep moves down-screen; wake is the soft side above it) lighting the lace faintly. Native: a holographic projector's scan.
2. Saltatory conduction with refractory tail (extends "myelin-like conduction bead trains"). The bead train advances in dwell-and-hop steps between internodes (time quantised through a smoothstep, spatial period unchanged) and each bead gets a sharp leading edge with an exponential tail instead of a symmetric lobe. Same colour, same amplitude gate (`0.1 + mids·0.2`), same `strand` mask. Native: myelinated-axon conduction.

FORMULA ADMISSION: neither is a §12.2 row; 0 rows used (budget rows HG / energy-conserving bloom fail the family test for the existing node/haze: the node glow is already a point falloff, an HG term would be a no-op at the closest-approach sample). Both operate on quantities already computed.
FORBID on this file: new springs/ripples, IQ palette, new params, changing the gyroid/pull/fog/AO, history reads, more than 2 new ideas.
A PACKING: ACES display RGBA (unchanged); C not read.
