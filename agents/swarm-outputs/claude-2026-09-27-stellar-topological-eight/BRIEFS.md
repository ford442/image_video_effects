# BRIEFS — Stellar / Topological Eight (2026-09-27)

Idea Cards as written by each agent (one file per shader: `card-<id>.md`). Ordering caveat: card mtime precedes WGSL mtime for 7 of 8; `gen-stellar-plasma-ouroboros` shows equal mtimes, so its card-first ordering could not be verified (card and diff do agree).

---

SHADER: gen-singularity-forge
IDENTITY (one sentence): a raymarched black hole with a fbm-turbulent torus accretion disk, a thin knotted jet, mouse lens pull and swirl-advected HDR trails.
KEEP VERBATIM: single 100-step primary march (count unchanged), black-hole/torus(pDisk.y*=5)/jet SDFs, gravity displacement, fbm disk turbulence, jet knot cadence (`knotPhase`), swirl-advected history read with exact `textureLoad(dataTextureC)`, mouse lens pull, camera, 4 params and their roles (Disk Density = torus thickness/rotation, Jet Intensity = jet glow + history gain, Gravity Warp = ray bending, Time Dilation = time scale), ACES only on writeTexture, semantic alpha, depth.
ADD (3 native ideas):
  1. Relativistic beaming + gravitational redshift on the disk. Per-step orbital velocity (tangent, beta ~ r^-1/2, capped 0.55) dotted with the ray gives a Doppler factor D; brightness ~ D^3 (approaching side blazing, receding side dim), times sqrt(1 - rs/r) gravitational dimming near the horizon, with a blue/red tint driven by log2(D*g). Replaces the old 3%-tint `doppler` that was applied to the whole frame. Visible with audio = 0; treble only sharpens the exponent.
  2. Log-spiral density-wave arms: shear phase is `m*theta + a*ln r - w*t` (m=3 grand-design arms, sharpened crests) instead of 16 radial spokes, so the disk reads as a winding galaxy-like spiral rather than a spoked wheel.
  3. Precessing helical jet: jet axis is displaced by a point-symmetric corkscrew `0.09*y*dir(phi)` with phi driven by the SAME ballistic age `|y|*0.18 - time*(0.9+bass*1.8)` as the knots, so knots ride the helix; slow whole-jet precession added.
FORBID on this file: lensed sky / photon ring / KIFS (gen-quantum-singularity-forge), extra marches or step-count increase, springs/ripples, palettes, a second geometry layer.
A PACKING: raw HDR (rgb) + semantic alpha in dataTextureA (kept; C is fed back raw, no decode needed); ACES only on writeTexture.

Silent bugs checked: A/C packing consistent (raw both ways); `normalize(p)` guarded by distToOrigin>0.01; no pow of negatives; audio from plasmaBuffer[0]. New code guards r and tangent normalisation. None found that needed a fix.

---

SHADER: gen-stellar-plasma-ouroboros
IDENTITY (one sentence): a hex-scaled serpent tunnel (cylinder carved by polar-repeated hex prisms, path-distorted) around a boiling blackbody/OkLab plasma core, with Fresnel rim and a mouse gravity nudge of the ray.
KEEP VERBATIM: sdCylinder / pModPolar / sdHexPrism carve and `max(cylD, -hexD)`, path distortion + rotation, 100-step march (`t += d*0.5`), fbm plasma glow accumulation, blackbody + OkLab surface colour, readTexture reflection, star fallback, Fresnel rim, mouse rd nudge, 4 params (Scale Density / Plasma Intensity / Anomaly Gravity / Time Warp) with roles and updatedParams byte-exact.
ADD (2 native ideas):
  1. Peristaltic plasma bolus — a soft pulse (period 16 z-units, travelling +z with Time Warp) that hinges the scale plates outward as it passes: the hex prism is tilted about its inner edge (z shift proportional to radial offset) and swung outward, displacing `hexD`. Native: it moves the exact scales the effect is built from, like a swallowing gullet. Visible at audio = 0 (mids only add amplitude).
  2. Seam light — plasma leaking through the hex gaps: an `exp(-|hexD|)` contour glow on the hit surface, gated by the bolus phase (dim ember between boluses, hot as it passes), coloured by blackbody and flickered by the existing fbm. Native: it lights the seams the carve already creates. Treble adds a slight flicker.
FORBID on this file: spring, ripples, C feedback "for completeness", IQ palettes, particle overlays, lensed sky / photon ring, beads along cylinders.
A PACKING: display RGBA (ACES) — HEAD never wrote dataTextureA.

Floor fixes:
- dataTextureA now written = display RGBA. The shader reads no C, so no C load is invented.
- ACES on display RGB with exposure 0.8 (0.5 -> ~0.54, 1.0 -> ~0.75; default look stays close, HDR glow now rolls off instead of clipping).
- Alpha: coverage/glow = mix(0.2, 1, max(surface hit, 1-exp(-1.5*glowLuma), seam)); floor 0.2 kept from HEAD.
- Depth: made truthful from march distance: hit ? clamp(1 - t/50, 0, 1) : 0 (near = 1; same convention as chrono-void-stag). HEAD passed readDepthTexture through.
- Audio: bass = plasmaBuffer[0].x (plasma boil offset, rim power/colour, as before); mids = bolus hinge amplitude; treble = seam flicker.

---

SHADER: gen-stellar-web-loom
IDENTITY: warp-flight raymarch through a lattice of glowing node spheres joined by three axis families of fbm-warped threads, with HDR light trails and radial streaks.
KEEP VERBATIM: 80-step march (d*0.6), lattice cell/domain spacing, fbm warp (3 fbm calls, no more), mouse singularity + click deepen, starfield, radial warp streaks, HDR trail feedback (C read via exact textureLoad, .rgb only; decay rides Weave Speed), ACES, semantic alpha, 4 params (Thread Density / Weave Speed / Plasma Glow / Thread Opacity Exponent) with `updatedParams` byte-exact.
ADD:
  1. Plucked-string standing waves — each thread segment between two lattice nodes rings as a string pinned at both nodes: mode 1 sin(pi*|s|/spacing) plus a decaying mode 2 sin(2*pi*s/spacing), circularly polarised transverse displacement of warped_q, per-segment hashed pluck phase re-plucked every ~3 s (exp decay). Visible at audio = 0; bass only adds amplitude. Continuous across cell faces. (Ideas 1 = the loom is a stringed instrument, not a static net.)
  2. Warp/weft identity + real over/under — the three axis families get distinct hues (z violet kept, x amber, y teal) instead of one violet mat_id; thread radius swells/thins by cos(2*pi*s/spacing) times lattice-cell parity so each thread alternately passes over/under its crossing neighbours (continuous across cell faces, unlike a per-cell radius step). Under-passing segments are dimmed.
  3. Gyro ring per node — small tilted torus precessing around each node (per-cell hash tilt + spin); cheap (1 hash, 2 rotations, 1 torus SDF).
FORBID: beads / packets running along threads, springs, ripples, extraBuffer state.
A PACKING: existing documented packing kept: A.rgb = HDR (clamped to 6.0) trail colour, A.a = normalized march depth.

Silent bug fixed: audio burst envelope lived in extraBuffer[133]/[134], written by thread (0,0) and read by every thread. Slots 133..255 are zeroed on every upload (audioDepth.ts), so it never persisted and was a data race. Replaced with a stateless per-pixel burst = clamp((bass - 0.3) * 5, 0, 2) (same 0..2 range; fires on loud kicks rather than on rising edge); all extraBuffer writes and reads removed.
Tint note: thread colour now blends tempTint at 50% (mix(1, tempTint, 0.5)) so the three hues stay distinct; nodes keep the full tempTint.

---

SHADER: gen-symbiotic-plasma-reef-matrix
IDENTITY: raymarched underwater reef — fbm seabed, tapered smin coral capsules, 8 orbiting glow entities that flee the mouse, violet->pink coral / cyan-green entity palette, caustic backdrop, orbiting camera.
KEEP VERBATIM: terrain + coralBranch SDF + smin, entity orbit/flee formulas, palettes, raymarch step count (80) and 0.7 step scale, camera, mouse mapping (no Y change), fog/ACES/temporal-persistence structure, depth write, 4 params with labels/roles, updatedParams byte-exact.
ADD:
  1. Symbiotic dock-and-pulse (IDEA 1) — the coral loop remembers its nearest branch axis; the existing entity loop (one extra length per entity, no per-branch entity loop) measures how close the nearest entity is to that axis. Near enough = the branch flares (cyan-green, the entity palette) and a light pulse climbs it from base to tip. Stateless, native to the entity/coral pair.
  2. Caustic dapples by height (IDEA 2) — sun-net caustic pattern projected on terrain/coral in world XZ, weighted by height (brighter shallows/tips, dim seabed) and up-facing normals; the backdrop already has caustics, this carries them onto the reef.
  3. (wiring, not an idea) Reef Density slider = coral branch count 3..9, exactly 5 at the saved default 0.5.
FORBID: replacing entities with particles, springs, ripples, extraBuffer state, more raymarch steps.
A PACKING: display RGBA (ACES colour, alpha = hit/glow coverage); dataTextureA matches writeTexture and is read back by C as colour.
KNOWN BUGS FIXED: (a) sampler read of dataTextureC -> textureLoad exact; (b) hard-coded alpha 1.0 -> semantic alpha; (c) dead Reef Density slider wired.

---

SHADER: gen-tectonic-plasma-crucible
IDENTITY (one sentence): raymarched Voronoi obsidian slabs floating on a magma ocean, fissures between plates expose glowing magma, heat haze bends the rays, the mouse pushes the crust ("tectonic stress").
KEEP VERBATIM: slab/fissure/magma SDF (`map`, smin combine, `inFissure` carve), `blackbody()` ocean colour, heatHaze, bubbling fbm, camera orbit + mouse (no Y change), 100-step march, 4 params (Crust Density, Magma Turbulence, Eruption Intensity, Tectonic Stress) and their roles, updatedParams byte-exact, at saved defaults the same crust/magma composition.
ADD:
  1. Incandescent-crack temperature ramp: a continuous `heat` (from voronoi edgeDist / fissureWidth, squared falloff reaching ~2.5 fissure widths) drives a white-yellow core -> orange -> dull red -> obsidian ramp. It replaces the binary `inFissure > 0.5` look: the fissure magma colour blends toward the ramp core and the obsidian crust gets an unlit thermal emissive halo. The material switch itself stays (it is geometry/haze logic), only the colour becomes continuous.
  2. Per-plate isostatic bobbing + tilt: `voronoi()` now also returns the nearest-cell hash and feature offset (same 2x27 taps, no extra calls). Each plate rides slowly up/down and tilts about its own feature point, so neighbouring plates step against each other across the fissures. Bass rifting (stateless, plasmaBuffer[0].x scaled by Eruption Intensity) widens `fissureWidth`. Bobbing/tilt is visible at audio = 0; rift only rides along.
FORBID on this file: ash/spark particle overlays, springs, ripples, IQ palettes, changing mouse Y, extra voronoi calls, more march steps.
A PACKING: display RGBA (ACES display RGB, semantic alpha). C is read as colour only, via exact textureLoad.

Notes: `slabHeight = 0.3 + hash3(floor(vp))*0.4` (grid-cell hash, not Voronoi id) is left alone; idea 2 adds the true Voronoi plate hash as an extra lift/tilt term instead of replacing it.
Bugs to fix: (a) sampler read of dataTextureC -> textureLoad(coord); (b) hard-coded alpha 1.0; (c) blackbody `pow(t-0.4, 2.0)` had a possibly-negative base (NaN risk) -> explicit square; (d) temporal mix blended display-range prev into pre-ACES HDR then tone-mapped again -> mix after ACES in display space.

---

SHADER: gen-topological-phase-weave
IDENTITY (one sentence): a nematic director field wound by 8 orbiting +1/2 / -1/2 defects (plus a held-mouse +1/2 that pins the field), drawn as an iridescent thin-film weave with warm/cool singularity glow, Euler tint and a bass-driven order-parameter colour shift.
KEEP VERBATIM: `directorField` / `defectProximity` layout and defect orbits; iridescent map; mouse defect when held + local pin (`mouseAttract`); Euler tint; phase colour shift (`orderParam` from bass); C exact-load feedback; ACES; semantic alpha; A = display RGBA; 4 params (Defect Density -> density, Defect Mobility -> orbit speed, Perturbation -> treble-style angle noise + streak scale, Color Saturation) and `updatedParams` byte-exact.
ADD (native ideas):
  1. True line-integral convolution: 5 steps each way along the streamline (11 taps, triangle kernel) replacing the noise-offset `streak`/`streak2`. Cheap director: the field is sampled once per pixel with its analytic gradient (grad of atan2 = (-dy,dx)/r^2, same loop, no extra atan2); steps use theta(q) = theta0 + grad.(q-p), the mouse pin gradient is blended by `mouseAttract`. Threads follow the weave for real.
  2. Defect glyphs from the field itself: radial alignment cos^2(theta - phi) about the nearest defect is one wedge for a +1/2 (comet tail) and three lobes for a -1/2 (trefoil), because theta-phi = c - phi/2 vs c - 3phi/2. Warm comet / cool trefoil, drawn after the core darkening. Needs the nearest defect's offset, so `defectProximity` now also returns it (struct).
  3. Order parameter drives coherence: `cohere` = autonomous slow-breathing ordered/disordered domains (visible at audio = 0), pushed to 1 by bass `orderParam`, by the mouse pin, and reduced at defect cores. Low coherence jitters every LIC step's direction (isotropic speckle, soft threshold); high coherence gives crisp aligned threads (higher contrast, tighter smoothstep).
FORBID: pair annihilation, Schlieren from |grad theta| (acoustic-knots), springs, ripples, extraBuffer state.
A PACKING: display RGBA (ACES) — unchanged from HEAD.

SILENT BUG (fixed): `extraBuffer[0]` as "prevBass". Slot 0 is the raw bass uploaded every frame, so `bassEnv(prev, bass, ...)` returned exactly `bass` (a no-op) and thread (0,0) overwrote the audio slot mid-dispatch (race). Replaced by `bass` directly (numerically identical to the old effective behaviour); `bassEnv` and all extraBuffer writes removed.
COST: per pixel ~1.4-1.6x HEAD (extra 8 divides in the director loop + 11 value-noise taps + 10 cos/sin + 10 hashes; no extra atan2).

---

SHADER: gen-vortex-cathedral
IDENTITY (one sentence): a spinning arch/column vortex (sin(spinA*archCount) piers, sanctum rings, fog) around a bright warm sanctum with two god-ray passes, a 6-spike starburst and edge chromatic aberration.
KEEP VERBATIM: sector/arches/rings/columns/fog/centerLight construction, sanctum glow, both god-ray passes (20 steps), 6-spike starburst, edge CA sampling readTexture, ghost persistence from C, premultiplied writeTexture, 4 params (Arch Count, Spin, Haze, Sanctum Radius) with their roles, updatedParams byte-exact.
ADD (native ideas):
  1. Arch-gated crepuscular shafts — each of the 20 god-ray samples evaluates the same spinA/sector formula in its own polar coordinates (one atan2 + sin + smoothstep per step); dust is lit only where the sample is between piers, so light falls in shafts between the arches instead of a uniform glow. Applied to both passes.
  2. Stained-glass sector tint — per-pane hash picks a jewel colour (ruby/amber/sapphire/emerald/violet, a hand-picked 5-entry table, not an IQ cosine palette). Shafts use the gap pane index floor(x/PI+0.5) (x = spinA*archCount) so a whole shaft is one colour; piers use the pier index floor(x/PI) so each pier is one colour. (Sharpened from the proposed floor(x/TAU): a TAU cell holds two piers and puts the boundary through the shaft.) Tint fades out near the sanctum so the core stays warm white.
  3. Counter-rotating second vault — a half-density arch ring at r~0.6, spinning against the main vault (opposite spin, opposite twist), jewel-tinted, adds to arches/columns/presence.
FORBID: springs, ripples, generic IQ palette overlay, changing param roles or defaults look.
A PACKING: display RGBA (post-ACES colour, non-premultiplied, + semantic alpha). HEAD stored (arches, rings, centerLight, alpha) yet read C back as colour: the ghost tint therefore changes slightly (previously a lavender-ish arches/rings/light mix; now the actual previous frame colour, decayed 0.92 at 4-5.5%).

Bugs fixed: (a) extraBuffer[0] "prevBass": slot 0 IS the uploaded raw bass, so bass_env(prev==bass) was already identity (smoothing no-op) and thread (0,0) wrote the audio slot mid-dispatch (race). Now stateless smoothBass = max(bass,0) (numerically identical to what actually ran), all extraBuffer writes removed. (b) sampler read of dataTextureC -> textureLoad(dataTextureC, coord, 0). (c) packing lie above. (d) godRays normalize(zero) -> d / max(len, 1e-5).

---

# Idea Card: gen-wasm-hls-physarum-swarm (RESCUE, then 2 ideas)

```
SHADER: gen-wasm-hls-physarum-swarm
IDENTITY: slime-mould vein network that eats the video (luma = food), mouse attracts, audio steers.
WHY IT IS DEAD (HEAD): agent (x,y,angle,alive) lives in extraBuffer[agentIdx*4..]. The runtime re-uploads all 256 floats
  every frame (0-2 audio, 4 historyHead, 5..132 FFT, rest zero) => every agent reads alive==0 and re-seeds to the same
  hash position each frame (static noise), and the shader clobbers the audio/FFT slots (race).
KEEP VERBATIM: 3-sensor F/L/R steering with weight (trail + food*2.5); sensorAngle / sensorDist / decayRate / depositAmount
  roles and mix() ranges (0.3..1.2, 5..25, 0.85..0.995, 0.3..2.0); turnSpeed = 0.5 + bass*3 + mid*1.5 (times sensorAngle),
  moveSpeed = 1.5 + treble; deposit *(1+bass*2); random tie-break when F is the minimum; mouse pull radius 150 px, blend*0.3;
  3x3-blurred, decayed trail; video-as-food; chromatic palette (paletteChromatic); depth pass-through.
RESCUE (state rule changes): Eulerian agents, no extraBuffer at all (not even 133..138).
  A = (trail, mx, my, hue): m = mass density * heading (|m| = mass, m/|m| = heading).
  Per pixel, exact textureLoad on C only:
   1. u = speed * m/max(|m|,0.05); source s = p - u.
   2. gather at s from the 4 bilinear corners: mass = bilinear(|m|); heading = corner with largest weight*|m|
      (winner-take-all).  Plain vector bilerp of m was tried FIRST and failed the gate (opposing streams cancel -> isolated
      hubs, giant component 0.17); this is the "do not annihilate" mechanism.
   3. Jacobian J = det(I - grad u) from central differences of u (4 more loads): converging flow piles mass up
      (this is what concentrates agents onto veins, as in real physarum); mass = clamp(max(mass,0.07)*(1+0.6(J-1)), 0.07, 0.6).
   4. steer (F/L/R sense on trail C + food*2.5), +-0.075 rad wander, mouse pull; then trail = blur3x3(C.r)*decay
      + 0.05*dep*mass*(1-trail)*(1-decay)/0.04125  (deposit normalised so Trail Decay changes persistence, not brightness).
  Seed path: C texel all-zero (first frame / resize) -> mass 0.075..0.225, heading from hash.
  Mass floor 0.07 = re-inflation; cap 0.6.
NUMPY GATE (physarum_sim.py, N=128, 1500 steps): see report; all 9 slider cases pass (vein mesh, giant comp >= 0.66, mass
  >100% of initial, no saturation, state moving).
ADD (after the sim lives):
  1. Peristaltic cytoplasm streaming: brightness pulses that run along the veins in the local heading direction:
     phase = dot(pos, heading)*k - time*w, modulating trail brightness (gated by heading coherence so it only shows on real veins).
     Native: an actual vein carries cytoplasm along its axis, and heading is a field the rescue now owns.
  2. Tube shading of veins: normal from the trail gradient (C central differences), diffuse + specular, so veins read as
     cylinders; plus a distinct foraging-front colour where mass is high but trail is young
     (youth = (1.21*dep*mass - trail)/(0.3*1.21*dep*mass+0.02), the equilibrium trail for that mass; 7-17% coverage in numpy).
FORBID: boids / reaction-diffusion reimagining, springs, ripples, extraBuffer state, ripple-style overlays, IQ palette stamp.
A PACKING: raw sim state (trail, mx, my, hue). ACES only on writeTexture. No ACES on stored fields.
SLIDERS: names/defaults/min/max/step byte-exact. Roles kept. LOOK AT SAVED VALUES DIFFERS: HEAD was static per-frame noise
  (dead); saved values now give a slowly migrating vein mesh.
SILENT BUGS FIXED: extraBuffer clobber of audio/FFT slots + always-reseeding agents; alpha hardcoded 1.0 and A alpha 1.0
  (now vein coverage); mouse pull blended raw angles across the +-pi seam (now shortest arc) and normalize(0) at the cursor
  pixel (guarded); prior "temporal persistence" mix with C.rgb (no longer feeds anything back through display).
```

