# Neural / plasma / photonic generative ten — Idea Cards (2026-09-14)

Contract: CONTRACT.md. Two native ideas each; identities kept; no new springs. Naga 10/10, precommit gate 10/10, extraBuffer audit PASS, dead-slider audit PASS (1255 scanned), updatedParams unchanged 10/10, no params ids renamed. Real-GPU QA external.

SHADER: gen-neural-fractal
IDENTITY: Julia-style escape fractal where each iteration is a neural layer (sigmoid/tanh/swish activations cycling every 10 iterations), colored by twin orbit traps through OkLab/blackbody/cosine palettes.
KEEP VERBATIM: OkLab helpers, blackbody, cosinePalette, fresnelRim, activation fns, neuralLayer, domainWarp, multiTrapColor, twin orbit traps / sumZ structure / minZ detail, vignette, zoom/iteration/mutation mappings.
ADD (2 native ideas):
  1. Dendritic arborization: stalk trap (distance to the sigmoid midpoint / tanh zero axes) records the iteration of closest approach as branch order; branches only appear once an advancing growth cone (iteration front, pushed by clicks and mouse-hold) has passed them; trunk warm blackbody, tips cool, white growth-cone tip.
  2. Firing-rate glow: fraction of iterations whose activation saturates (|out|>0.9) marks "firing" neurons; they flicker with a treble-accelerated spike train in a cyan/magenta membrane glow.
FLOOR FIXES: bounds check; bass/mids/treble clamped from plasmaBuffer[0] (mids -> structure palette, treble -> spike train); Color Cycling (y) was a dead slider -> now scales palette drift (default 0.5 reproduces old rate); click ripples added as depolarizing stimulus waves (warp domain, boost mutation, advance growth cone); mouse-held strengthens domain pull and shifts juliaC; dataTextureA writeback added; alpha = activation density (trap glow + dendrite + firing) instead of luma; depth = escape-time depth instead of 0; header/uniform comments; JSON params + features.
FORBID: dataTextureB writes, extraBuffer use, plasmaBuffer[>0], generic noise/bloom overlays, replacing the neural-layer iteration.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (none used) / sliders x=zoom, y=color cycling, z=iteration depth, w=mutation live


---

SHADER: gen-neural-network-glow-synaptic-pulse
IDENTITY: Voronoi neural mesh whose cell edges are synapses; concentric action-potential rings travel out from nodes, bass envelope swells the mesh, mouse gravity bends it, alpha trail potentiates repeated activation.
KEEP VERBATIM: hash22 Voronoi mesh, bass_env envelope + mouse spring, gravity lens, pulse_ring, chromatic excitatory/inhibitory separation, temporal potentiation, depth-scaled nodes.
ADD (2 native ideas):
  1. Quantal vesicle release: each bouton (cell node) fires stochastic release quanta (probability from bass envelope, rate from Pulse Speed); released transmitter spreads as the 2D diffusion Green's function exp(-r^2/4Dt)/(4Dt) with mids-driven D and reuptake decay, drawn as green-gold clouds.
  2. Action-potential waveform: pulse ring now has a spike (treble sharpens) followed by an afterhyperpolarization undershoot in the refractory window that subtracts intensity and cools/darkens the membrane.
FLOOR FIXES: plasmaBuffer[color_idx] fake palette read (indices up to 255) replaced by native membrane-voltage colormap; audio clamped from plasmaBuffer[0]; textureSampleLevel(dataTextureC) -> clamped textureLoad (alpha trail only); bass envelope + mouse spring state (was misread from C's color channels) relocated to guarded extraBuffer[133..136] with (0,0)-only writes; ripple loop fixed (was treating r.z start time as radius and r.w as active, looped all 50) -> min(u32(config.y),50) expanding evoked rings; generic applyGenerativePrimaryControls overlay removed (double-mapped all sliders, second ACES) -> single ACES; writeTexture and dataTextureA now receive the same ACES RGBA; Mouse Influence (w) now natively scales gravity (default 0.5 == old strength) and mouse-held tetanic glow; JSON workgroup_size [8,8,1] -> [16,16,1] to match WGSL.
FORBID: dataTextureB writes, extraBuffer outside 133..138, plasmaBuffer[>0], new springs, replacing the Voronoi mesh.
A PACKING: ACES display RGBA in A (alpha = synaptic activity, fed back as potentiation trail)
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x=pulse speed+release rate, y=glow intensity, z=trail decay, w=mouse gravity+held glow live


---

SHADER: gen-neuro-cosmos
IDENTITY: Raymarched 3D Voronoi web that reads both as a neural network (somas at cell centres, axon strands on F2-F1 edges) and as the cosmic web; mouse-orbit camera, volumetric proximity glow, distance fog into deep space.
KEEP VERBATIM: hash33, voronoiMap, map (smooth union of web + neuron SDF), calcNormal, orbit camera from mouse yaw/pitch + drift, 80-step volumetric march, colour palette (warm core / blue outer / cyan synapse / deep-space bg), sin(f1*10 - t*speed) strand pulse, rim light, fog.
ADD (2 native ideas):
  1. Saltatory conduction: strands carry nodes of Ranvier (f1 * 12 lattice); the action potential hops node-to-node in discrete flashes (floor(node) - t*speed phase) while the smooth pulse persists dimmer on the myelinated internodes. Pulse Speed drives hop rate; mids and evoked stimulation brighten node flashes.
  2. Integrate-and-fire somas: each neuron (cell hash) charges its membrane potential linearly, spikes at threshold, then shows a refractory afterglow. Bass (and click/held stimulation) lowers the firing threshold; treble brightens spikes.
FLOOR FIXES: header replaced; Uniforms comment names the 4 sliders and correct config.y/zoom_config.w meanings; added plasmaBuffer[0].xyz audio (bass -> glow gain + tone-map gain + firing threshold, mids -> strand pulse/node flash, treble -> rim + spikes); ACES tone map; semantic alpha (fog-attenuated surface coverage max volumetric glow density) replacing hardcoded 1.0; added dataTextureA writeback (same RGBA as writeTexture); no dataTextureB/C/extraBuffer use; added click ripples (expanding depolarization front, loop to min(config.y,50)) and mouse-held stimulating electrode at cursor (previously neither existed); JSON params array + features added.
FORBID: textureStore to dataTextureB/C; extraBuffer outside 133..138; config.y/time as audio; replacing the Voronoi web motif; generic noise/bloom overlays.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (AUDIT PASS, 0 violations) / sliders x,y,z,w live (x=map scale, y=pulse + saltatory hop speed, z=volumetric glow, w=strand/soma thickness)


---

SHADER: gen-neuro-fluid-plasma-lotus
IDENTITY: Raymarched liquid-neon lotus: 8-petal sinusoidal ridges on an FBM-warped sphere around a white-hot plasma stamen core, magnetic twist, phototropic mouse reach, volumetric violet plasma haze, abyss dust background.
KEEP VERBATIM: noise/fbm3, smin, bass_env, map (twist, phototropic reach, petal wave, fluid warp, core), calcNormal, raymarch shading (core plasma, petal gradient, fresnel sheen, chromatic edge, SSS), camera orbit, 16-step volumetric glow, temporal persistence mix, slider mappings (mix ranges).
ADD (2 native ideas):
  1. Golden-angle phyllotaxis stamen florets: the core SDF is displaced by a lattice of florets at intersections of 8 clockwise / 13 counter-clockwise parastichies (consecutive Fibonacci counts), with hot floret tips and cooler valleys; amplitude and glow scale with Core Heat.
  2. MHD flux-rope field lines: helical magnetic field lines on a cylindrical sheath around the lotus (pitch tied to the existing magnetic twist) carrying Alfven wave packets at constant Alfven speed, accumulated in the volumetric loop and occluded behind the flower; bass boosts packet amplitude, Dispersion scales field emission, click ripples (reconnection shock rings) flare them.
FLOOR FIXES: header replaced; Uniforms comment fixed (config.y = RippleCount, not audio); plasmaBuffer[0].xyz clamped 0..1, mids -> petal wave amplitude, treble -> dust sparkle; extraBuffer[0] bass-envelope state relocated to guarded extraBuffer[133] (arrayLength > 138u, write only at gid 0,0); textureSampleLevel(dataTextureC) -> exact clamped textureLoad; hardcoded finalAlpha=1.0 replaced by presence (surface coverage + plasma/field density + shock); ACES kept with small bass gain; A writeback kept, no B write; added click ripples (magnetic reconnection shock rings) and mouse-held (strengthens phototropic reach); JSON params array + features added.
FORBID: textureStore to dataTextureB/C; extraBuffer outside 133..138; plasmaBuffer beyond [0]; config.y as audio; replacing lotus/petal motif.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (AUDIT PASS, 0 violations) / sliders x,y,z,w live (x=petal ridge amplitude, y=bloom radius + SSS, z=core radius/heat + floret glow, w=fresnel sheen + field-line emission)


---

SHADER: gen-neuro-kinetic-bloom
IDENTITY: Raymarched deep-sea garden of repeated biomechanical neuron-flora (axon capsule + two side dendrites), twisting with bass, neon-green veins, sprung-mouse repulsion, click bloom rings.
KEEP VERBATIM: sdCapsule/rot, domain repetition (spacing 6), bass twist, sprung cursor spring (133..138), mouse repulsion, vein displacement MatID, fog, click-bloom ring loop, ACES, semantic alpha (hit + glowMass + treble + click), depth = 1 - t/50.
ADD (2 native ideas):
  1. Dendritic bifurcation: each side-branch tip forks into two thinner second-generation spines (length scales with Bloom Extension via branch_length).
  2. Saltatory action potentials: a per-cell spike front sweeps the axon but is quantized to nodes of Ranvier (0.9 spacing), so a white-cyan flash hops node to node; bass speeds conduction and brightens it; feeds glowMass/alpha.
FLOOR FIXES: removed unguarded extraBuffer[133/134/137] reads inside map() (sprung mouse now passed in as a parameter from main); all 133..138 reads now inside `arrayLength(&extraBuffer) > 138u` guard (writes already guarded); plasmaBuffer[0].xyz clamped 0..1 in map and main; mouse-held (zoom_config.w) now wired (repulsion push 0.5 -> 0.9 when held); header replaced to contract format; Uniforms comment corrected (y=RippleCount, w=MouseDown). JSON: added params array (bloomExtension/repulsionRadius/veinGlow/cameraZoom matching updatedParams), features now include audio-reactive/mouse-driven/upgraded-rgba. updatedParams unchanged. No dataTextureC use (no feedback), no dataTextureB write.
FORBID: writing dataTextureB/C, extraBuffer outside 133..138, u.config.y as audio, new springs, replacing the flora motif.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x (branch length oscillation amplitude + spine length), y (repulsion radius), z (vein displacement + vein glow + spike brightness), w (camera dolly) live


---

SHADER: gen-neuro-kinetic-liquid-gold-lotus
IDENTITY: Raymarched liquid-gold 8-petal lotus smooth-unioned with an fbm plasma core; torque waves, cyan/magenta plasma runners, sprung-pointer + click gravity wells bending rays, click blossom shocks, torque-advected rotational trails.
KEEP VERBATIM: sdLotusPetals/torque wave, map/opSmoothUnion core, fbm plasma veins + runners, sprung cursor + held-gravity envelope (133..138), gravity-well ray bending, blossom shock rings, torque-rotated exact textureLoad of C history, semantic alpha, depth.
ADD (2 native ideas):
  1. Conductor Fresnel on liquid gold: Schlick with spectral gold F0 (1.0, 0.71, 0.29) replaces the white dielectric highlight; specular and rim are gold-tinted at normal incidence, whitening toward grazing. Gold Smoothness also scales rim.
  2. Golden-angle phyllotaxis stamen florets: Vogel spiral (137.5 deg, r = c*sqrt(k)) anthers on the upper core, nearest floret searched over k+-21; they fire sequentially in spiral index order (bass speeds the wave, treble brightens, Plasma Intensity scales).
FLOOR FIXES: extraBuffer 133..138 reads and the (0,0) write now guarded by `arrayLength(&extraBuffer) > 138u` (were unguarded); plasmaBuffer clamp 0..2 -> 0..1; A/writeTexture mismatch fixed: A previously held linear HDR while writeTexture held ACES — now the same ACES display RGBA goes to both, and the temporal max/decay runs in display space (max(ACES(col), prev*decay)) so trails still fade; dead click response fixed: gravity wells and blossom shocks multiplied by ripple.w, which the engine always uploads as 0 (UniformBuffer.setRipple padding) — now full strength per live ripple; bounds check uses textureDimensions(writeTexture). Header replaced. JSON: features + upgraded-rgba, feedbackPacking string updated to the new packing. params/updatedParams unchanged.
FORBID: writing dataTextureB/C, bilinear sampling C, extraBuffer outside 133..138, new springs, replacing lotus motif.
A PACKING: ACES display RGBA in A (rgb = max(ACES(frame), torque-advected C load * decay), a = semantic coverage)
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x (petal bloom lift), y (plasma veins/runners, core audio swell, shock + floret brightness), z (specular exponent, trail decay, Fresnel rim), w (spring stiffness, orbit rotation, held torque kick + gravity) live


---

SHADER: gen-neutron-star-magnetic-spindle
IDENTITY: Raymarched neutron star / compact core with frame-dragged accretion torus, polar fbm jets, step-wise gravitational lensing and blackbody volumetrics; mouse orbits/tilts the camera.
KEEP VERBATIM: map() (core sphere, twisted torus, jets, smin), calcNormal, blackbody, fbm/noise3/hash3, lensing loop, Doppler core shading + rim, vignette, mouse orbit/tilt camera.
ADD (2 native ideas):
  1. Dipole magnetosphere field lines: co-rotating oblique (0.9 rad tilt) magnetic frame, tubes on quantized L-shells of r = L sin^2(theta) x 8 magnetic longitudes, closed only inside the light cylinder R_LC ~ c/Omega (shrinks with Spin Rate); emissivity ~ 1/r^3, colour from curvature-radiation energy ~ 1/rho using the exact dipole radius of curvature; charge bunches stream along lines.
  2. Pulsar beams: open polar-cap field lines (L > R_LC) emit a pale-blue coherent beam along the tilted magnetic axis, sweeping with the spin; lighthouse pulse flash (beam + core temperature + halo) when the magnetic axis crosses the line of sight.
FLOOR FIXES: removed fake audio (textureSampleLevel(dataTextureC,...).r used as "audio") -> plasmaBuffer[0].xyz clamped (bass: core/jet pulse + exposure, mids: disk heat + afterglow, treble: field line/beam brightness); Reinhard+gamma -> ACES; hardcoded alpha 1.0 -> surface coverage + volumetric density + magnetospheric glow; added dataTextureA writeback (same RGBA) and depth write; exact textureLoad C phosphor afterglow; added click ripples (starquake Alfven ring + field-line flare) and mouse-held magnetar flare (field lines x1.8); Doppler normalize NaN guard on the spin axis; header replaced (COPY PASTE junk removed); JSON features added. No extraBuffer use. JSON has no updatedParams (none existed; not added). params unchanged.
FORBID: extraBuffer, dataTextureB writes, textureSample of C, replacing the torus/jet motif with generic glow.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x (core radius+lensing), y (frame drag, Doppler, pulsar period, light cylinder), z (jets + beam brightness), w (disk scale) live


---

SHADER: gen-newton-fractal
IDENTITY: Newton's-method basins of z^n - 1 with fbm domain warp, noise-perturbed iteration, multi-shape orbit traps, multi-root colour blend, SDF root halos and a reaction-diffusion accent on basin boundaries; mouse pans the view.
KEEP VERBATIM: cpower/cdiv/complexNoise, domainWarp, root palette, orbit traps, smooth iteration, multi-root accumulation, SDF halo, RD update rule, chromatic shift, ACES, parameter mappings.
ADD (2 native ideas):
  1. Convergence-order sheen: per-pixel peak estimate q = log|dz_k| / log|dz_(k-1)|; quadratic (q~2) regions get warm isochrone glints (bands every 2 smooth steps), linear-convergence regions (damped or noise-inexact Newton, q~1) shade violet with isochrones. Iteration Precision scales the violet shading.
  2. Damped-Newton relaxation waves: z -= a f/f' with a = 1 + expanding ring from each click ripple (over-relaxation, bass-scaled) and a < 1 under the held mouse (under-relaxation); basins visibly reshape and the order sheen reveals the lost quadratic convergence.
FLOOR FIXES: plasmaBuffer[0] clamped 0..1; dataTextureA previously held telemetry (rdState, orbitMin, iterRatio, alpha) differing from writeTexture -> now the same final RGBA in both, with RD state packed into the sub-1/256 fraction of alpha (alpha still = convergence*vignette to within 1/256); RD neighbour loads clamped; "temporal feedback" from readTexture (input image, via textureSampleLevel) -> exact textureLoad of C colour history; added click ripple + mouse-held response (none existed); uniforms comment lists sliders; header replaced; JSON params array added, features + mouse-driven, upgraded-rgba. updatedParams byte-identical.
FORBID: extraBuffer, dataTextureB writes, textureSample of C, IQ palettes over the basin colours.
A PACKING: ACES display RGBA in A; A.a = floor(convAlpha*255)/256 + rdState*(0.999/256)
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x (zoom), y (degree), z (max iterations/tolerance + order-sheen strength), w (warp, perturbation, bloom, halo radius) live


---

SHADER: gen-obsidian-echo-chamber
IDENTITY: High-speed wrapped fly-through of polished obsidian monoliths (domain-repeated box SDF with structural cuts), cyan/magenta sonar wavefronts racing down the corridor, chromatic-aberrated glossy specular, analytic reflected corridor, click echo shocks, advected corridor speed trails.
KEEP VERBATIM: map()/sdBox/rayMarch/getNormal, wrapped camera travel, mouse rotation (Mouse Influence), sonar ripplePhase + rippleColor, CA specular, analytic refEnv, fog, click echo rings, advected history trail, hit-coverage alpha.
ADD (2 native ideas):
  1. Conchoidal fracture shells: each monolith cell carries one hashed impact scar on its dominant face; concentric Hertzian-cone ribs (spacing grows with sqrt(r)) bend the shading normal used by specular/Fresnel/CA, with rib-crest + fracture-lip glints lit by the passing sonar front and treble.
  2. Reverberant echo taps: three irregular early-reflection taps trail the direct sonar front with geometric decay (longer tail with mids + Intensity), widening band (diffusion) and treble loss toward deep violet (wall absorption). Click echoes also return one delayed, softer wall reflection; holding the mouse makes the cursor a continuous sonar emitter.
FLOOR FIXES: header replaced (removed COPY PASTE junk); plasmaBuffer[0].xyz now clamped 0..1; A now holds the same ACES display RGBA as writeTexture (previously HDR in A, ACES in writeTexture); history still exact textureLoad of C with clamped integer coords; no dataTextureB / extraBuffer use; mouse-held response added (zoom_config.w was unused); params array + upgraded-rgba feature added to JSON; updatedParams unchanged.
FORBID: second raymarch for reflections, writes to dataTextureB/C, fake audio from u.config.y/zoom_config.x, new springs.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (none used) / sliders x=Intensity (sonar emission gain, reverb decay, output gain), y=Speed (motion time, camera travel, sonar speed, trail velocity + history weight), z=Scale (monolith scale, spec exponent, Fresnel/reflection strength, rib glint), w=Mouse Influence (camera yaw/pitch, trail drift, held-ping strength) live


---

SHADER: gen-opal-circuit
IDENTITY: Iridescent opal-toned PCB lattice: hashed horizontal/vertical traces and vias, per-cell travelling data packets, hex-grid overlay, fbm iridescent substrate, bass-enveloped signal pulse.
KEEP VERBATIM: hash/noise/fbm, bass_env envelope follower, hexDistance, iridescentSubstrate, trace/via/packet generation, opalR/G/B trace colouring, slider mappings (traceScale/pulseRate/iridescence/bloom), light temporal mix.
ADD (2 native ideas):
  1. Bragg play-of-colour: Voronoi opal domains, each with its own silica-sphere plane spacing (205-262nm) and lattice tilt; lambda = 2 d n_eff cos(theta) (n_eff 1.36) mapped through a spectral RGB curve with infrared fade, flashing only near Bragg alignment. View tilt follows the mouse + treble; bass swells the lattice spacing (colour shift). Tints traces and the substrate, scaled by Iridescence.
  2. Manhattan-routed signal propagation: clicks launch edges that travel L1 grid distance at a Pulse-Rate-dependent velocity, followed by damped transmission-line ringing, gated to copper traces. Holding the mouse makes the cursor a clock driver emitting square-wave edges with overshoot.
FLOOR FIXES: extraBuffer[0] (unguarded, bass envelope) relocated to guarded extraBuffer[133]; textureSampleLevel(dataTextureC) replaced by exact textureLoad; hardcoded alpha 1.0 replaced by copper coverage + signal + diffraction alpha; A now holds final display RGBA (was packed trace/signal/packet/hex data); depth now traces/vias height (was 0); plasma audio clamped; click ripples + mouse-held added (none existed); header replaced; JSON params array + features added; updatedParams unchanged.
FORBID: generic IQ-palette overlay, writes to dataTextureB/C, extraBuffer outside 133..138, FFT bins beyond plasmaBuffer[0].
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (133 guarded) / sliders x=Trace Scale (grid density, hex scale, ripple/clock cell mapping), y=Pulse Rate (signal pulse speed, edge velocity, clock Hz), z=Iridescence (substrate/trace opal + Bragg strength), w=Bloom (via glow, bus-edge glow) live


---

