# Quantum / Psychedelic Seven — Idea Cards (written before any WGSL edit)

**Agent:** claude · **Date:** 2026-09-27 · **Contract:** docs/SHADER_UPGRADE_BATCH.md §0/§2/§7 · see CONTRACT.md


SHADER: gen-psychedelic-layered-time-stamps

IDENTITY (one sentence): the live video summed as up to 10 delayed, OkLab/blackbody-tinted copies (weight exp(-delay*scale*i)) with sinusoidal chromatic-split distortion, a Fresnel rim on the distortion edges and a light feedback mix.

KEEP VERBATIM:
- zoom_params roles: x = layer count (i32(x*10+3), loop hard-capped at 10), y = delay_scale, z = distortion_amp, w = chromatic_shift*0.01. Saved defaults 0.5/0.5/0.5/0.5 and the JSON updatedParams untouched.
- sin(uv.y*10+t) / cos(uv.x*10+t) distortion field with (1+2*bass) gain, R/B chroma split (+/- chromatic_shift*(1+bass|treble)).
- layer_weight = exp(-current_delay*delay_scale*i), final/layer_count, OkLab mix of layer tint with blackbody(layer_factor+bass*0.3), the Fresnel rim, held-mouse bass flash, alpha formula, depth passthrough.
- applyGenerativePrimaryControls display wrapper (intensity / speed pulse / contrast / mouse gain + ACES). It double-duties the four sliders but is HEAD's look; retained, noted.
- A delay clock advances 0.01/frame and wraps (same speed).

ADD (native ideas):
  1. Lagged echo taps — today every layer multiplies the SAME base sample, so the "time-stamps" are only tints. Each layer i now re-samples the video through the distortion field evaluated at (time - i*lag), lag scaled by delay_scale, with the same R/G/B chroma split. Layer 0 is bit-identical to HEAD's base sample; older layers trail as phase-lagged ghosts of the distortion. Layers become real dated stamps.
  2. Postmark rings — each layer stamps a dashed ring on its own age phase (the same color_shift phase already used for its tint): radius grows with age, fade envelope sin(pi*phase) so it is born/dies invisibly, inked in the layer's OkLab/blackbody tint, rings warped by the same distortion (z slider), centred on the pointer (default 0.5,0.5). A postmark per layer, on the layer's own clock.
  3. Delay wavefront — HEAD's delay clock is one global sawtooth (every texel identical, whole frame pops at wrap). Clock is now offset by radial distance from the stamp anchor, so the wrap edge (the stamp "edge" of the weights) sweeps outward from the anchor as a ring instead of a global pop.

FORBID on this file: spring/extraBuffer state, click shockwaves, ripple-w scaling, IQ cosine palette as the look, ferro/quantum motifs from sibling files, replacing the layer-sum with a different accumulator.

SILENT BUGS FIXED (read path):
  - plasma_color = plasmaBuffer[0..254].rgb: only [0] is ever uploaded (bass,mid,treble,0); the other 255 entries are zero, so the per-layer "plasma color offset" was black and every layer tinted only by blackbody. Replaced by a stateless OkLab hue-cycle ink (stamp_ink) on the same color_shift phase (restores the "different color offset per layer" the description promises). Consequence: layer tints are now hue-varied, not monochrome warm; documented, not hidden.
  - srgb_to_linear/linear_to_srgb: pow of negative (out-of-gamut OkLab) is NaN; bases clamped with max(...,0).
  - Feedback: HEAD read C.rgb via textureSampleLevel with a filtering sampler on rgba32float while A stored only (delay,0,0,1) — so "feedback" was a red sawtooth tint. Packing lie. Now exact textureLoad(C) and A stores raw pre-ACES accumulated colour in .rgb with the delay clock moved to .a (read back with the same packing).
  - Duplicate delay_track load removed.

A PACKING: raw pre-ACES accumulated feedback colour in A.rgb, wrapping delay clock in A.a; C read exactly the same way. ACES only on writeTexture. (HEAD packed the clock in A.x, read C.rgb as colour = packing lie, fixed and stated here.)

Notes: ripples unused by HEAD, none added. No extraBuffer use. Audio from plasmaBuffer[0].xyz only rides along (bass gain, treble chroma); all three ideas visible at audio = 0. Slider mapping: idea 1 lag scales with y (delay), idea 2 ring warp with z (distortion); no new sliders. Default look is NOT numerically identical to HEAD (tint hue, echo lag, feedback repaired); look unverified — no GPU here.

---

SHADER: gen-quantum-acoustic-bioluminescent-void-urchin
IDENTITY (one sentence): a raymarched spiny sea-urchin body (core + polar-repeated octahedron-tipped spines + membrane) wrapped by gyro torus rings, a quantum octahedron cage and drifting plankton, glowing cyan/violet over a kaleidoscopic hex-tessellated void.
KEEP VERBATIM: map() SDF (core, polar spines, membrane, rings, cage, plankton, matIDs 1-4), 4 slider roles (p0 spine density/length, p1 audio multiplier, p2 colour shift, p3 void fluidity + kaleido fold count), mouse orbit + mouse bend of spines, hex membrane shimmer, kaleidoscopic void backdrop for misses, real depth, semantic luma alpha, volumetric glow accumulation. No click ripples exist at HEAD and none are added (not native).
ADD (3 native ideas):
  1. Spine firing waves — a stateless nerve-impulse band races outward along every spine (core to octahedron tip) and flares at the tip; phase comes from a smooth direction-noise so neighbouring spines fire in coherent groups. Visible at audio 0. Belongs: the spines are the urchin's signature; this makes them alive.
  2. Luminous afterglow — exact C load of the previous display frame; only the bright bioluminescent points (tips, plankton, rings, glow) linger and fade (max-decay, bounded), persistence rides Void Fluidity (thicker void = longer glow). Belongs: bioluminescence is glow that lingers; orbiting plankton and rings leave streaks.
  3. Cage void-reflection — the crystalline quantum-cage shards (matID 4) reflect the kaleidoscopic hex void (backdrop factored into one function, miss branch unchanged) instead of a flat tint. Belongs: joins the cage to the existing backdrop motif.
FORBID on this file: spring+ripple+IQ-palette stamp, new creature/SDF, extraBuffer state (133..255 is zeroed each frame), reading audio from config.y / zoom_config.x, Reinhard-to-ACES look reset that hides the effect.
A PACKING: display RGBA (post-ACES, post-gamma, same values as writeTexture) — C read as colour history, so it decodes consistently. Floor items also done: ACES replaces Reinhard (gamma kept to preserve brightness), no silent bug on read path at HEAD (no pow of negative base: fresnel base is clamped; no C read existed; no ripple.w read; no dead mask). Saved params: JSON has only updatedParams; left byte-exact.

---

SHADER: gen-quantum-entangled-ferrofluid-engine
IDENTITY (one sentence): a black-purple metallic ferrofluid blob (raymarched sphere + 4 smooth-min satellite droplets, fbm spikes driven by a wavefunction |psi|^2) with cyan entanglement glow lines to the satellites and a faint double-slit interference backdrop; the mouse is a "measurement" magnet.
KEEP VERBATIM: 4 params (Magnetic Strength / Fluid Viscosity / Quantum Glow / Audio Reactivity) and their roles in map() (mag -> collapse pull + spike freq, viscosity -> smin k, glow -> entanglement glow scale, audio -> spike amp); sphere + 4 orbiting satellites (same orbit formulas); fbm spike displacement + sharpen pow; wavefunction() and interferencePattern(); the existing centre->satellite glow lines; PBR shading (diff/spec/fresnel/chromatic env reflection/fake SSS); vignette; chroma shift; ACES on display; A = display RGBA (C read as display colour history).
ADD (3 native ideas):
  1. Rosensweig spike lattice — real ferrofluid under a field forms a lattice of cones above a critical field. Add a stateless icosahedral-axis cosine lattice of sharp cones on the sphere shell, rotating slowly; amplitude = smoothstep on Magnetic Strength (no lattice at 0 = unmagnetised) and taller on the side facing the mouse magnet. Sits on top of the fbm spikes, does not replace them.
  2. Entangled-pair filaments — the four satellites are two entangled pairs (0<->1, 2<->3). Add glowing segments between each pair carrying a standing |psi|^2 bead pattern that pulses in antiphase between the two pairs, with magenta beads over the existing cyan glow. Native to the "entanglement" motif; existing centre lines stay.
  3. |psi|^2 nodal contours on the metal — the JSON description says probability density modulates glow but the code never did that. Trace iso-lines of the same wavefunction (same k, omega as the spike driver) across the surface as thin cyan-violet contours scaled by Quantum Glow, so the spike-driving wave is visible on the body.
FORBID on this file: spring/extraBuffer state, IQ palettes, oil-slick thin film, generic ripple shockwave stamps, replacing the fbm spikes or the raymarch, borrowing beads/lattices from sibling quantum/psychedelic files.
A PACKING: ACES display RGBA (unchanged; history now decoded with acesInverse before the temporal mix so the stored value is not tone-mapped twice).

Silent bugs on the read path (fixing, will report):
  - Feedback used textureSampleLevel(dataTextureC, u_sampler, ...) on rgba32float -> exact textureLoad.
  - History was fed back post-ACES into a pre-ACES mix (double tone-map) -> acesInverse decode.
  - Ripple displacement scaled by ripple.z (= startTime, not strength) so amplitude grew with session time, used uv*2.0 vs world-space, and ignored rippleCount; also audio_lf was faked from ripples[0].xy. Now age = time - z, gated by config.y, uv mapped like the mouse, audio_lf from plasmaBuffer.
  - global_glow kept accumulating during calcNormal()/thickness map() calls after the march -> snapshot at end of march.

---

SHADER: gen-quantum-fluorescent-aether-moth-swarm
IDENTITY (one sentence): cyan/magenta/indigo fluorescent moths (simplex-blob spawn field) smeared along a divergence-free curl flow, leaving decaying HDR trails, gravitating to the mouse (scattering on hold) and assembling into an audio-gated mandala.
KEEP VERBATIM: 4-tap curl2 flow + wobble; snoise spawn blobs (density slider = spawn frequency); textureLoad(dataTextureC) advected trail with TRAIL_DECAY 0.92 + HDR_CEIL; vel_color cyan/magenta/indigo mapping; mouse gravity node + SCATTER_PUSH on mouse-down; audio mandala (rings/arms, gate scaled by audio_sens); depth-from-spawn; semantic alpha; ACES only on writeTexture; raw HDR (not ACES) stored in dataTextureA. Slider roles: x density, y curl, z glow, w audio sensitivity. JSON has only updatedParams (no saved `params`) - untouched.
ADD (4 native ideas):
  1. Wingbeat flutter - each moth blob gets a beat phase from the existing wobble + spawn-noise fields (zero extra noise taps); brightness snaps open/closed (~1.7 Hz) and the wing-scale sheen flips cyan -> magenta with the beat. A swarm should flicker; visible at audio = 0.
  2. Flight-aligned wing smear - the spawn noise is sampled in a domain compressed along the moth's local heading (vel.xy), so blobs elongate into streaks with the flow; stretch grows with speed and is identity at rest. Moths look like they are flying, not pulsing.
  3. Lantern orbit - the existing mouse gravity node becomes a lamp: tangential swirl added to vel so moths circle it, spawn threshold lowered in a radius (lure) so they crowd it, small warm halo. Released on mouse-down (scatter keeps its meaning, halo off, swirl reverses).
  4. Idle roost mandala - the mandala now rotates slowly and also self-assembles on a slow ~16 s breathing gate, independent of audio, so the swarm periodically organises into its geometry in silence. Audio gate (scaled by audio_sens) is kept and combined with max().
FORBID on this file: spring cursors in extraBuffer[133..], click shockwaves (HEAD has no ripples), IQ cosine palette, thin-film/holographic overlays, replacing the curl flow, per-particle sim (this is a stateless field + trail), anything from sibling shaders in this batch.
A PACKING: raw HDR RGB + semantic alpha in dataTextureA, read back exactly by textureLoad(dataTextureC) as HDR trail (HEAD packing kept; ACES on writeTexture only). No dataTextureB use. Silent-bug audit of read path: no pow, no ripple.w, no dead fract mask, no early-return (spawn seeds the zero-init C) - nothing to fix; extraBuffer[5..12] FFT read is valid live audio.

---

SHADER: gen-quantum-fluorescent-nebula-anemone
IDENTITY (one sentence): a ring of 22 iridescent, swaying, dual-temperature-lit fluorescent tentacle bands floating in a violet fBm nebula with quantum interference sparkle, god rays and a mouse-attracted glow.
KEEP VERBATIM: the 22-tentacle loop (rot(angle)*p, sway, dist = length(..)-1.6, exp falloff, per-tentacle HSV hue, warm/cool/rim lighting); the fBm nebula/nebula2/fog stack; qWave quantum field (constant freq 0.5, see below); god_rays; mouse reach + mouse glow; hue_preserving_clamp -> ACES -> IGN dither; semantic alpha; depth = depth*0.5+fog*0.2; readTexture *0.86 carry; the four saved `updatedParams` (names, defaults 0.5, 0..1, step 0.01) byte-exact (JSON has no `params` block).
ADD (native ideas):
  1. Nematocyst pulse beads — sparse bright photophore beads crawl around every tentacle band (pow(cos(atan2 phase * 7 - t + fi)) gated by the band), each tentacle with its own phase. An anemone's stinging-cell beads; visible at audio = 0.
  2. Stokes-shift afterglow — tentacle emission is kept in dataTextureC/A.r with slow decay; where a tentacle has swayed away the residual glows amber/red-shifted (fluorescence re-emits at longer wavelength). Reads exact textureLoad(dataTextureC); seeded from zero with no early return.
  3. Crenulated oral disc — the anemone body the god rays were supposed to radiate from: a breathing 11-lobed rosette with a glowing crenulated lip and dim magenta gullet at the centre of the tentacle ring.
FORBID: spring cursor, IQ palette stamp, generic shockwave overlay, replacing tentacles with particles, ACES on stored A fields.
A PACKING: raw sim/field state (glow history, fog, quantum, alpha) — same channel roles as HEAD, except .r changes from instantaneous tentacleEmission to decayed glow history (HEAD's A was never read). No ACES on stored fields; tone-map only on writeTexture.

SLIDER MAPPING (silent bug found): JSON names (x Fluorescence Intensity, y Tentacle Density, z Audio Reactivity, w Nebula Density) did not match what HEAD read (x reach, y fluorescence, z nebula, w quantum freq) — the UI labels lied. WGSL now honours the labels, all at default 0.5 reproducing HEAD numerics:
  x = fluorescence (HEAD y=0.5), y = Tentacle Density (visible tentacle count = y*44 soft-gated, all 22 at 0.5; also mouse reach = y*0.8 = HEAD 0.4), z = Audio Reactivity (gain z*2, =1 at default), w = nebula density (HEAD z=0.5). quantumFreq becomes constant 0.5 (HEAD's default value).
OTHER READ-PATH BUGS TO FIX: audio was u.config.y (click count) -> plasmaBuffer[0].xyz; ripple strength used r.z (start time, grows unboundedly) -> age = time - r.z with decay, r.z>0 guard, no .w.

---

SHADER: gen-quantum-foam-alpha
IDENTITY (one sentence): a dark vacuum of drifting Gaussian probability clouds in correlated, interfering pairs whose alpha encodes uncertainty (diffuse = translucent, sharp = opaque), with the mouse collapsing the wavefunction locally.
KEEP VERBATIM: the whole pair loop (Lissajous orbits, pairOffset, probCloud, interference, hsv colour, totalProb / colorAccum / totalUncertainty); vacuumField feedback via env_q on C.r; bg glow + fbm foam texture; collapse glow; gamma 0.4545 then ACES; uncertainty->alpha mapping; mouse collapse and held boost; the four params (x=Cloud Density, y=Uncertainty, z=Vacuum Energy, w=Collapse Strength) and their existing mappings.
ADD (3 native ideas):
  1. Virtual pair flashes (Planck-scale creation/annihilation) — foam is where virtual particle/antiparticle pairs pop out of the vacuum, separate, and annihilate. Stateless per-cell lifecycle on a 3x3 cell grid: two sharp points of complementary hue born at a cell centre, fly apart along a hashed axis, return and die in a bright annihilation flash. Extends the "correlated pair" motif at the sub-cloud scale. Occupancy scales with Cloud Density (previously dead slider; neutral to the old layers).
  2. Born-rule detection hits — the clouds are probability densities, so sample them: 4-px detector cells fire round ~4-px hits with probability proportional to the local totalProb (12 Hz re-roll), like a double-slit buildup screen. Hits are opaque (alpha) and take the cloud's own colour; they concentrate near the mouse where the wavefunction is being measured (uses Collapse Strength, previously dead).
  3. Spacetime-foam membranes — Wheeler foam is a froth of bubbles: animated Worley F2-F1 film lines over the fbm foam, lit by vacuumField and thickened by Vacuum Energy. Gives the "foam" in the name actual bubble walls.
  (Slider fix, not an idea) Collapse Strength scales the sharpening term (0.7*k, k = collapseStrength/1.5, so k = 1 at saved default 0.5) -> identical old look at default.
FORBID on this file: spring+ripple stamp, IQ cosine palette, extraBuffer state, reimagining the clouds as another creature/fractal, ACES on stored fields, sibling-file motifs (moths, urchins, ferrofluid, anemones, spirals, time stamps).
SILENT BUG on read path: while mouse is held collapseFactor reaches 1.8 so localSigma = sigma*(1-0.7*cf^2) crosses zero and goes negative -> divide-by-zero / NaN in probCloud and negative avgUncertainty into alpha. Fix: floor localSigma at 0.08*sigma (no change unless cf^2 > ~1.3, i.e. only the held core).
A PACKING: raw sim state, kept as HEAD documents it: A = (vacuumField, totalProb, avgUncertainty, alpha); C read as .r = vacuumField only. ACES on writeTexture only, not on stored fields. New ideas write nothing to A (no state added; all stateless).

---

SHADER: gen_psychedelic_spiral (JSON id gen-psychedelic-spiral)
IDENTITY (one sentence): a superformula petal bloom whose outline is offset by nested-epicycle spirograph orbits, wrapped in a chromatic rotating feedback trail.
KEEP VERBATIM: spiroCenter epicycles, superformula() + n1/n2/n3 breathing, ghost ring, core, band/spokes/swirl/halo pattern, iqPalette hue mapping, the feedback history UV chain (rot / zoom / mouse shift / per-channel chromatic taps), hueClamp 1.2 before the A write, mouse offset, click petal-burst ring (position math), all four slider roles and saved params byte-exact (Orbit Intensity, Spin Speed, Petal Count, Feedback Warp).
ADD (3 native ideas):
  1. Petal-tip pearls — the outline's own curvature (superR vs. its two angular neighbours) marks each petal apex; a bead of light sits on the outline exactly at the tips. Belongs here because petals ARE the superformula; pearls make the Petal Count slider read as beads on a necklace. Stateless, visible at audio 0.
  2. Pen-trace rosette — the actual spirograph pen curve (the 4-harmonic epicycle chain, sampled as a 32-segment closed polyline) drawn as a glowing hairline inside the bloom, rotating with Spin Speed and sized by Orbit Intensity. Until now the epicycles only nudged the sample point; you never saw the spirograph curve. Stateless.
  3. Nested outline ladder — homothetic copies of the superformula outline (dist / shapeRadius contours) drift inward like a topographic rosette, so each petal gets a ladder of echo outlines. Extends the existing ghost-ring / halo idea into a family.
  (Silent bug fixes, not ideas:) click ring scaled by ripple.w (always 0) so clicks were dead -> removed the .w factor; ripple age used the x5 "fast" time against ripple.z stamped in raw time (window collapsed to ~0.3 s) -> age now `u.config.x - ripple.z`; prevStandard sampled at uv (texel corner) -> exact textureLoad(dataTextureC, coord, 0); ACES added on the display mix only.
FORBID on this file: springs, extra IQ palette stamps, sibling-batch motifs (moire flower / time-warp kaleidoscope / quantum foam), replacing the superformula with another fractal, ACES on the stored history.
A PACKING: A = raw hue-clamped colour history (pre-ACES) + presence in alpha, exactly as HEAD reads it from C in the feedback chain; ACES is applied to the display RGB written to writeTexture only, so the loop decodes consistently.

---
