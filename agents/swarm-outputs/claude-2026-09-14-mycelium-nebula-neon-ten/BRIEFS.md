# Mycelium / nebula / neon generative ten — Idea Cards (2026-09-14)

Contract: CONTRACT.md. Two native ideas each; identities kept; no new springs. Naga 10/10, precommit gate 10/10, extraBuffer audit PASS, updatedParams byte-exact 10/10. Real-GPU QA external.

SHADER: gen-mushroom-mandala-garden
IDENTITY: Radial psychedelic mushroom garden: petal-segmented breathing cap rings, luminous gills, spore lanes, sinuous mycelium, fairy-ring fronts, drag-bent growth with swirl history, clicks releasing rayed spore fronts.
KEEP VERBATIM: palette, acesToneMap, hash21, historyLoadUV (exact textureLoad), polar layout (segments/petalAngle/breathe/ringCoord), cap/stem/spores/mycelium/fairyRing, drag warp + dragMask, click-spore ripple loop, hue/colour stack, swirl history mix, structure alpha, depth formula, param mappings (Cap Count / Breathe Rate / Gill Detail / Bioluminescence).
ADD (2 native ideas):
  1. Lamellulae gill tiers: full-length lamellae plus short secondary lamellulae inserted at half spacing on the outer (margin) half of each cap band, and tertiary lamellulae at quarter spacing near the margin weighted by Gill Detail — the real stem-to-margin gill insertion pattern of agaric caps.
  2. Buller's-drop ballistospore discharge: lattice of ripe discharge sites (ripeness rises with treble) firing spores with a catapult flash (bass-lifted), a drag-stopped sideways sporabola hook, then vertical gravity sedimentation; fire rate from Breathe Rate, glow from Bioluminescence. Feeds structure alpha.
FLOOR FIXES: header replaced (legacy one-liner removed); uniforms comment lists sliders; plasmaBuffer audio clamped 0..1 into bass/mids/treble with controlled gains (was raw audio.xyz with +1.0 unscaled mids/treble gains, now *0.5); ACES display gets (1 + bass*0.15). No fake audio, no extraBuffer use, dataTextureC already exact load, no dataTextureB writes; A and writeTexture already identical RGBA. JSON: features + "upgraded-rgba"; updatedParams and existing params array untouched (existing param ids are kebab-case, left as-is to avoid churn).
FORBID: extraBuffer use outside 133..138, dataTextureB writes, textureSample on dataTextureC, fake audio, new springs, replacing the radial mandala motif.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok (bindgroup compatible, 0 extraBuffer violations) / extraBuffer audit PASS / sliders x (segments, ring count, cap width, drag falloff), y (breathing, gill drift, spore lanes, discharge rate), z (gill frequency, tertiary lamellulae, mycelium, drag amp), w (cap glow, hue, history, discharge glow) live


---

SHADER: gen-mycelium-network
IDENTITY: Branching fungal mycelium from 3 roots (noise-wandered, coarse-culled segment SDF walk) with chemotaxis toward the mouse nutrient well, anastomosis fusions, bioluminescent tips, traveling signal pulses, time-warped growth front with age rings, bass-kick spore-burst shockwave, persistent max-decay feedback.
KEEP VERBATIM: hash/noise/fbm, distToSegment, MycelData, generateMycelium (incl. prior chemotaxis + anastomosis ideas), bass rising-edge kick detector (state 133..135), growth cycle/frontEase, tip/pulse/nutrient/mouse/rings/burst rendering, vignette, clearFade decay constants, param mappings (Growth Rate / Branching Factor / Nutrient Density / Bioluminescence).
ADD (2 native ideas):
  1. Peripheral growth zone + interior autolysis: only a band of width (0.35 + growth*0.2 + nutrient*0.35) behind the advancing front stays vital; interior hyphae stale toward grey-translucent, thin, lose tip light (vitality²) and partially their translocation pulses.
  2. Click-inoculated spore germination: each click ripple drops a spore that swells, then after a lag pushes out 2–4 germ tubes (count from Branching Factor) with linear apical extension (rate from Growth Rate), gentle midpoint curl, and a bright Spitzenkörper at each apex (Bioluminescence, bass); fades over 4.5 s. Satisfies the missing click-ripple floor.
FLOOR FIXES: header replaced (legacy multi-line block, "By:" removed); uniforms comment lists sliders; FAKE AUDIO removed: extraBuffer[6..11] "FFT bins" (fftLo unused, fftMid drove nutrient shimmer → now mids); plasmaBuffer clamped 0..1; extraBuffer[133..135] kick state guard tightened from >135u to arrayLength > 138u, and the unguarded select(…extraBuffer[134]…) read moved inside the guard; dataTextureC load now coord-clamped; A packing changed from HDR pre-ACES history (with different RGBA than writeTexture) to identical ACES display RGBA in A and writeTexture — the max-decay feedback is now done in display space so trails/clear-fade behave as before; alpha glow mass also persists with the same decay; click ripples added (loop to min(config.y,50)); mouse-held still moves burst origin. JSON: params array added (camelCase ids, byte-exact values), features + mouse-driven, click-reactive; updatedParams unchanged.
FORBID: extraBuffer indices outside 133..138, dataTextureB writes, textureSample on dataTextureC, fake audio (FFT bins in extraBuffer), new springs, replacing the branching-walk motif.
A PACKING: ACES display RGBA in A (display-space feedback: rgb = max(ACES(col), C.rgb*decay), a = max(glow mass, C.a*decay))
VERIFY: naga ok / gate ok (bindgroup compatible, 0 extraBuffer violations) / extraBuffer audit PASS / sliders x (segment length, cycle speed, pulse speed, vital zone, germ extension), y (branch count/probability, germ tube count), z (chemotaxis, fusion reach, nutrient glow, vital zone), w (tip/pulse/germ-tip glow) live


---

SHADER: gen-navier-stokes-ink
IDENTITY: Single-pass Navier-Stokes ink: semi-Lagrangian advection of velocity+dye carried frame-to-frame through A->C, viscosity blur, divergence correction, mouse force + ink injection, curl-lit eddies, shear chroma, plus raymarched SDF vortex tubes anchored on the sim field and a tessellated ink-drop corona under a mouse orbit camera; click ripples deform geometry.
KEEP VERBATIM: acesToneMapping, huePreserveClamp, ign dither, rotX/rotY, sdCapsule, param mappings (Injection Rate / Viscosity / Dispersion / Vorticity Scale), mouse force/source, viscosity mix, divergence correction, ink decay, vortex-tube + corona raymarch, ink/eddy/shear colouring, input composite, depth logic, sim-state A packing.
ADD (2 native ideas):
  1. Vorticity confinement (Fedkiw/Stam/Jensen): curl evaluated at the 4 neighbours (8 extra exact loads), N = grad|omega| normalised, force eps*(N.y*omega, -N.x*omega) added to velocity; eps = Vorticity Scale * 0.18 * (1 + smoothed bass * 0.4). Restores the small eddies that bilinear back-tracing dissipates.
  2. Negative-buoyancy Boussinesq ink: dense ink sinks, f_y = g*(inkSat - 0.6*neighbourAvgInkSat) (+y = down screen), g scaled by mids and inverse viscosity. Click ripples now also drop a dense ink bead with a radial splash impulse (first 0.35 s) into the sim, which then falls and fingers into plumes; the existing geometry ripple wave is kept.
FLOOR FIXES: header replaced; uniforms comment lists sliders; 8x textureSampleLevel(dataTextureC, non_filtering_sampler) -> exact clamped textureLoad (neighbours, tube anchors) and the advection back-trace -> manual bilinear from 4 clamped loads (bilinearC, pixel-space); fake audio extraBuffer[8]/[64] "FFT bins" removed (fftLow -> raw bass, fftHigh -> treble); extraBuffer[133] smoothed-bass guard raised from >133u to >138u (read+write); dataTextureB pressure-stub write deleted (never read back); audio clamped 0..1; display alpha now Porter-Duff over (alpha + inA*(1-alpha)) instead of max(); velocity magnitude bounded to 24 px/frame for stability; mouse-held adds corona swell; unused texel constant dropped. JSON: params array, features + audio-reactive, mouse-driven, upgraded-rgba, click-reactive, depth-aware, vorticity-confinement, boussinesq-buoyancy; updatedParams unchanged.
FORBID: extraBuffer indices outside 133..138, dataTextureB writes, sampler reads of dataTextureC, fake audio, new springs, replacing the ink field/vortex tubes, overwriting A's sim packing with display colour (would kill the fluid).
A PACKING: raw sim state (vel.x px/frame, vel.y px/frame, ink density, coverage alpha) — NOT display RGBA; C feeds back velocity (rg) and dye (b). ACES display RGBA goes to writeTexture only. Deliberate per the batch Simulation-state note.
VERIFY: naga ok / gate ok (naga OK, bindgroup compatible, 0 extraBuffer violations) / extraBuffer audit PASS / sliders x (ink injection + drop mass), y (viscosity blur + buoyancy + corona facets), z (ink decay + glow falloff), w (displayed vorticity, tube length, confinement eps) live


---

SHADER: gen-nebula-light-trail-swarm
IDENTITY: 20 analytic photon particles race outward from a nebula core leaving glowing trails (cosine palette OkLab-mixed with blackbody), central Fresnel-like core, drifting soft bloom, blackbody starfield, colour-history feedback with chromatic dispersion, ACES.
KEEP VERBATIM: OkLab helpers, blackbody, cosinePalette, acesToneMap, hash/hash21, trailDist, particle launch/curl/direction math, core/bloom/starfield, chromatic-dispersion feedback structure, param mappings (Particle Speed / Trail Decay / Curl Strength / Glow Radius).
ADD (2 native ideas):
  1. Strömgren-sphere ionization stratification: aspect-correct sphere around the core with R_s ∝ Q^(1/3) (Q from bass, +held), wrinkled by clumpy value-noise gas density; [O III] teal inner zone (mids), H-alpha red shell, thin [S II] ionization front (treble). Contributes to alpha coverage and depth.
  2. Recombination afterglow along trails: each trail's colour is OkLab-mixed with an emission-line colour that goes from ionized [O III] white-teal at the photon head to H-alpha red behind it, ionFrac = exp(-behind/recombLen); recombLen and trail length set by Trail Decay. Trail brightness/alpha follow the afterglow.
FLOOR FIXES: header replaced (legacy "Visualist Upgrade" block removed); uniforms comment lists sliders; 4x textureSampleLevel(dataTextureC, u_sampler) -> exact clamped textureLoad (dispersion offsets rounded to integer texels); dead slider Trail Decay (y) now drives feedback persistence (coordinator: persist = 0.03*8^(1-2y), so default 0.5 keeps the original 0.03 weight), prev fade, trail length and recombination time; unused `repel` now used (cursor halo) and mouse actually deflects particles (repel, held = gravitational well pull) — previously the mouse did nothing; added click response (light echo: scattered-light shell expanding from each ripple, loop to min(config.y,50)); audio clamped 0..1; alpha now includes nebula/echo coverage plus decaying previous alpha; depth clamped and shaped by front/trails. No fake audio, no extraBuffer, no dataTextureB use found. JSON: params array added, features (was empty) = audio-reactive, mouse-driven, upgraded-rgba, click-reactive, depth-aware, temporal, stromgren-stratification, recombination-afterglow; updatedParams unchanged.
FORBID: extraBuffer indices outside 133..138, dataTextureB writes, sampler reads of dataTextureC, fake audio, new springs, replacing the particle-trail motif with generic noise.
A PACKING: ACES display RGBA in A (C read back as trail history)
VERIFY: naga ok / gate ok (naga OK, bindgroup compatible, 0 extraBuffer violations) / extraBuffer audit PASS / sliders x (particle speed), y (trail persistence/length/recombination), z (curl), w (trail width) live


---

SHADER: gen-nebular-chrono-astrolabe
IDENTITY: Raymarched cosmic astrolabe: glowing core sphere, concentric noise-warped torus rings (count = Complexity), orbiting satellite box, curl-noise space warp, domain-warped FBM nebula volume, Fresnel/Beer-Lambert shading, sprung-mouse gravity well, click gravity rings, temporal feedback, depth output.
KEEP VERBATIM: hash/vnoise/fbm/domainWarp/curl, SDFs, smin/rot2D/fresnel/beer/ACES, raymarch loop, getNormal, material colours, spring-mouse integrator (omega 7) and its 133..138 slots, click gravity rings, temporal mix, slider mappings (Rotation Speed / Complexity / Glow Intensity / Gravity Well Strength).
ADD (2 native ideas):
  1. Keplerian rete gearing: each ring's rotation rate scales by (1.5/a)^1.5 from its radius a (Kepler's third law), so inner almucantars lap outer ones like a geared astrolabe/orrery; the satellite pointer uses the same law at a≈3.
  2. Strömgren-stratified nebular emission: nebula samples blend their original tint with emission-line colour by radius from the core — [O III] teal inside the ionisation (Strömgren) radius, H-alpha red + H-beta outside, with a brightened ionisation-front shell. Radius grows with bass (ionising flux) and Glow Intensity; treble lifts line brightness.
FLOOR FIXES: header replaced; uniforms comment lists sliders. extraBuffer[133..138] reads were unguarded in both main() and map() (map read them per SDF evaluation) — all reads/writes now inside arrayLength > 138u guards in main; map() uses a var<private> sprung mouse set once per invocation. Audio clamped 0..1 via private globals; gains tamed (gravity bass*2.0 → *0.5, ring phase bass*2.0 → *0.4, glow treble 1.0 → 0.5). Added mouse-held: gravity well ×(1+held·1.5). dataTextureC load now clamped. Alpha was lum-mix → astrolabe coverage / nebula column density / glow halo / click rings. No fake audio found (config.y only ripple count). JSON: params array added, features + audio-reactive, mouse-driven, upgraded-rgba; updatedParams unchanged.
FORBID: extraBuffer outside 133..138 or unguarded, dataTextureB writes, textureSample on dataTextureC, fake audio, new springs, replacing rings/core with generic noise.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer audit PASS / sliders x (ring + satellite rotation), y (ring count 1..5), z (glow, Beer density, Strömgren radius), w (gravity-well bend) live


---

SHADER: gen-neon-acid-geometry
IDENTITY: 9x9 grid of rotating triangles/hexagons/circles as neon tubes with universal-indicator pH colouring, smin sibling morph, melt noise, critical-angle refraction warp, pH-tinted FBM background and wave overlay, treble bubble sparkle, held-mouse acid/base splashes, temporal trails, chromatic offset, vignette.
KEEP VERBATIM: hash/vnoise/fbm, phToColor, snell/criticalAngle, SDFs, smin, sdfGlow, grid layout and shape selection, sibling morph, melt/wobble, pH cycle, wave overlay, sparkle, mouse splash, trail mix, CA, vignette, slider mappings (Intensity / Speed / Scale / Color Shift).
ADD (2 native ideas):
  1. Positive-column striations: each neon rim's core glow is modulated by travelling ionisation waves (bright striae with dark spaces, sharp head/long tail) along the arc; 4-7 striae per tube, drift rate from Speed, phase nudged by mids; held mouse (more current) crowds extra striae.
  2. Click titration fronts: each click drops titrant whose neutralisation front spreads ∝ √t; behind the front shape/background/wave pH snaps toward neutral green via a steep sigmoid titration-curve jump, with an indicator flash at the equivalence boundary. (Shader previously had no click response.)
FLOOR FIXES: header replaced; uniforms comment lists sliders. A was HDR while writeTexture was ACES → both now store the same ACES RGBA. Alpha was clamp(length(col)) → neon coverage (rim glow/fill/splash) + titration front + sparkle with decaying prev.a trail. time×audio phase jitter removed (pH cycle, sibling morph, melt now use additive audio phase); audio clamped; gains tamed (speed bass*0.7 removed, sparkle treble 2.0 → 1.2, CA bass 1.0 → 0.5, pulse gets bass*0.3). Scale slider min 0 divided by zero (0.18/scale) → clamped to ≥0.05. dataTextureC load clamped. No extraBuffer use; no fake audio found. JSON already compliant (params, features) — left unchanged.
FORBID: extraBuffer use outside 133..138, dataTextureB writes, textureSample on dataTextureC, fake audio, new springs, replacing the pH-neon shapes with generic noise.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer audit PASS / sliders x (glow/fill/melt/pulse), y (rotation, morph, striae drift, waves), z (grid spacing, shape noise freq), w (pH hue offset) live


---

SHADER: gen-neon-cyber-mandala
IDENTITY: Rotating neon sacred-geometry mandala: six phi-spaced rings with five decorative patterns (dots, radial lines, zigzag, wave, diamonds), golden-angle contra-rotating layers, Fibonacci hexagons and stars, connecting threads, a 13-ray central star and orb, orbiting particles, neon rainbow palette, breathing pulse, mouse zoom/rotation/symmetry warp.
KEEP VERBATIM: hash/noise, rainbow/neonRainbow, sdPolygon, starRays, patternedRing, phi ring spacing, golden-angle layer rotation, Fibonacci shape counts, connecting lines, central star/orb, border, particles, vignette, saturation boost, chromatic offset, param mappings (Glow Intensity / Rotation Speed / Zoom Scale / Color Shift).
ADD (2 native ideas):
  1. Glow-discharge tube anatomy: each ring is lit like a cold-cathode tube. There is a bright cathode negative glow, then the Faraday dark space, then a positive column split into striations that drift around the ring (spacing comes from the circumference / relaxation length; drift is set by Rotation Speed + mids and follows each layer's contra direction). Higher discharge current smears the striations into a solid column. Rings alternate between neon red-orange and argon-mercury blue emission-line tints (blend strength rises with treble).
  2. Ionization strike fronts: click ripples send out breakdown avalanche fronts, drawn as violet-white rings. Rings and Fibonacci shapes behind a front re-ignite and then fade out over the ion recombination time. Holding the mouse raises the discharge current (brighter rings with smoother columns), and bass surges the supply.
FLOOR FIXES: header replaced (was 2026-09-09 with non-standard features line); uniforms comment lists sliders; A was HDR pre-tonemap, now the same ACES display RGBA as writeTexture (temporal afterglow moved to display space: mix(mapped, max(mapped, prevC*0.92), 0.6)); dataTextureC load now clamped exact textureLoad; alpha was clamp(length,0.2,0.95), now glow-coverage luminance + strike front with afterglow persistence; audio clamped 0..1; added mouse-held (unused `mouseDown` replaced by held-driven current); added click ripples (loop to min(config.y,50)). No fake audio, no extraBuffer, no dataTextureB use found. JSON: unchanged (existing snake_case params ids kept by coordinator to protect presets).
FORBID: extraBuffer use, dataTextureB writes, sampled dataTextureC, fake audio, new springs, replacing rings with generic noise/bloom.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer audit PASS / sliders x (all glow + saturation), y (rotation + striation drift), z (zoom + ring radii), w (hue offset) live


---

SHADER: gen-neon-lotus
IDENTITY: Blooming neon lotus: three golden-angle-offset layers of teardrop polar petals with midline veins, neon cosine-hue petals, edge glow, a central stamen glow, treble shimmer, and a vignette. Bass swells the bloom, mids shift the glow, and holding the mouse shifts the flower center.
KEEP VERBATIM: hash2/noise2d, petalSdf, layer loop (layerScale, golden-angle offset, sector folding, bloom breathing), petal hue/colour, edge glow, vein, shimmer, vignette, mouse-held center shift, param mappings (Petal Count / Bloom / Speed / Glow Scale).
ADD (2 native ideas):
  1. Nelumbo seed-pod receptacle: a flat pod in the flower's center with carpel pits on a Vogel golden-angle spiral (r=R*sqrt(k/N)). The pits glow amber at their rims (bass), and a fringe of stamen filaments with anthers surrounds the pod. Carpel count follows Petal Count (8..24), pod radius follows Bloom, and stamen length swells with bass.
  2. Lotus-effect water beads: each petal carries a beaded water drop that rolls down the midline groove toward the tip (roll rate from Speed) and shrinks as it leaves the tip. Each bead has a refractive rim (Glow Scale) and a specular glint (treble). Click ripples become rings on the pond surface that refract the flower, add cyan swell light, and jolt and jiggle the beads.
FLOOR FIXES: header replaced; uniforms comment lists sliders; double ACES (aces() then acesToneMap()) collapsed to a single ACES pass; alpha was luma-driven, now petal/receptacle coverage + edge glow + swell; audio clamped 0..1; added click ripples (loop to min(config.y,50)). Unused duplicate acesToneMap removed. No fake audio, no extraBuffer, no dataTextureC/B use found. A already had the same RGBA as writeTexture. Depth now includes bead and receptacle lift. JSON: unchanged (existing snake_case params ids kept by coordinator to protect presets).
FORBID: extraBuffer use, dataTextureB writes, fake audio, new springs, replacing the petal SDF with generic noise/bloom.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer audit PASS / sliders x (petal count + carpel count), y (bloom + pod radius), z (rotation + bead roll), w (edge glow + bead rim + receptacle + pond light) live


---

SHADER: gen-neon-neural-network
IDENTITY: Neon feed-forward network: 6 layers of breathing ReLU neurons (4..14 nodes), hashed sparse edges with tonic signal pulses, treble backprop error glow, soft smin node cores, background grid, cursor node that wires to nearby neurons when held, temporal feedback, chromatic offset, vignette.
KEEP VERBATIM: hash/noise/neonColor/neonColor2/smin/relu/neuralLayer/getNodePos/sdSegment/signalPulse, layer/edge loops and connection hash, ReLU activation (inputSignal/weight/bias), node/edge/backprop/core/cursor rendering and palettes, grid, vignette, CA, feedback mix, param mappings (Intensity / Signal Speed / Network Scale / Color Shift).
ADD (2 native ideas):
  1. Leaky integrate-and-fire neurons: each soma has a tonic drive I (synaptic weight + Intensity); closed-form interspike interval T = τ·ln(I/(I−θ)) plus absolute refractory period gives a coherent per-neuron spike train. Membrane potential V(t) = I(1−e^(−t/τ)) charges the soma glow, spikes flash white-hot, the refractory window dims the node. Subthreshold neurons never fire. Held cursor and click electrodes inject extra current (forced spikes).
  2. Saltatory conduction: each presynaptic spike (current + 2 prior in the train) launches an action potential down every outgoing axon at a conduction velocity set by Signal Speed; the glow appears only at nodes of Ranvier (internode 0.045) and hops node to node, with faint myelin sheath between.
FLOOR FIXES: header replaced; uniforms comment lists sliders; added dims bounds check; mouse position bug fixed (zoom_config.yz is uv, was treated as pixels so cursor node was off-screen); redundant `mouseDown || zoom_config.w` collapsed; audio clamped 0..1 and gains tamed (bass ×2.0 → ×0.5 on activation, treble error 2.0 → 1.2, speed 0.6 → 0.4); textureSampleLevel(dataTextureC) → exact clamped textureLoad; added click ripples as stimulating-electrode depolarisation fronts (loop to min(config.y,50)); alpha length(col) → neural activity coverage (edges, spikes, AP hops, stimulus, cursor); depth 0 → layer recession + soma/spike pop; ACES exposure bass-modulated; same RGBA to writeTexture and dataTextureA. No fake audio found, no extraBuffer use. JSON: params array added, features [] → audio-reactive, mouse-driven, upgraded-rgba, click-reactive, depth-aware, temporal; updatedParams unchanged.
FORBID: extraBuffer use outside 133..138, dataTextureB writes, textureSample on dataTextureC, fake audio, time-varying LIF drive (phase = fract(time/period) strobes if period changes over time), replacing the layered network motif.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok (naga OK, bindgroup compatible, 0 extraBuffer violations) / extraBuffer audit PASS / sliders x (edge/core/AP brightness + LIF drive rate), y (tonic pulse + conduction velocity), z (network zoom), w (hue shift) live


---

SHADER: gen-neon-plasma-biomechanical-hive
IDENTITY: Raymarched biomechanical labyrinth: voronoi-displaced spheres fused to a cubic strut lattice, breathing scale, fbm neon veins over gunmetal, per-channel chromatic raymarch, plasma-spore swarm with spring-damped cursor pursuit + velocity lead, cursor gravity well, bass-kick and click shockwaves whipping the camera, velocity-advected HDR trails.
KEEP VERBATIM: hash3/voronoi/rot/smin/fbm/map (sphere+strut+gravity well)/map_spores, extraBuffer[133..137] state (bass envelope, kick time, smoothed cursor, prev time) and single-writer logic, kick detection, cursor pursuit + lead, click/kick shockwaves, camera flythrough, 3-pass CA raymarch, spore glow, vein fbm, neon colour logic, advected trail fetch, HDR_CEIL/TRAIL_DECAY, alpha and depth, param mappings (Hive Breathing Speed / Neon Intensity / Spore Density / Magnetic Pull).
ADD (2 native ideas):
  1. Brood-cell comb: at the hit point a voronoiCell (f1, f2, cell id) turns hive cells into brood chambers — thin chitin walls where f2−f1→0 tinted neon (treble), ~55% wax-capped amber-metal domes lit by the key light, the rest open with a larva whose plasma glow beats on its own heartbeat (rate from Breathing Speed, bass-boosted, brightness from Neon Intensity). Holding the mouse uncaps brood near the gravity well.
  2. Peristaltic hemolymph pumping: every strut tube carries a travelling contraction wave (raised-cosine⁴ bolus along its world axis, pump rate from Breathing Speed + bass) that bulges the tube radius in the SDF; map() now returns the nearest strut's bolus (masked to tube surfaces), which drives neon vein emission ×(0.6 + 1.6·bolus) so plasma visibly surges through the veins.
FLOOR FIXES: legacy header replaced; fake FFT audio removed (extraBuffer[5..12] read under `> 13u` guard — outside 133..138); vein gain `1+bass+fft*0.5` → `1+bass*0.5+mids*0.3`; audio clamped 0..1; `plasmaBuffer[0].rgb` → clamped (bass,mids,treble); state guard `>= 139u` → `> 138u`; dataTextureA was raw HDR (non-ACES) → now same ACES display RGBA as writeTexture, with feedback recovering HDR via analytic ACES inverse (quadratic root) ÷ exposure, clamped to HDR_CEIL. C read already exact textureLoad (clamped). Mouse held / click ripples already present (loop min(config.y,50)). JSON: params array added; features + mouse-driven, upgraded-rgba (audio-reactive already present); updatedParams unchanged.
FORBID: extraBuffer indices outside 133..138 (no FFT bins), dataTextureB writes, textureSample on dataTextureC, storing non-ACES HDR in A, new springs, replacing the voronoi hive / strut lattice motif.
A PACKING: ACES display RGBA in A (feedback inverts ACES analytically to recover HDR trails)
VERIFY: naga ok / gate ok (naga OK, bindgroup compatible, 0 extraBuffer violations) / extraBuffer audit PASS (only guarded 133..137) / sliders x (breathing, flythrough, pump + heartbeat rate, trail advection), y (vein + larva emission), z (spore glow), w (gravity well strength/distance) live
