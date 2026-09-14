# Magnetic / fractal / evolutionary generative ten — Idea Cards (2026-09-14)

Contract: CONTRACT.md. Two native ideas each; identities kept; no new springs. Naga 10/10, precommit gate 10/10, extraBuffer audit PASS, updatedParams byte-exact 10/10. Real-GPU QA external.

SHADER: gen-magnetic-field-warp
IDENTITY: Image-warp driven by a magnetic field: mouse dipole + domain-warped FBM turbulence + curl-noise vorticity + Clifford strange-attractor displacement, with a plasma-colour remix of the warped image.
KEEP VERBATIM: valueNoise, fbm, warpedFBM, curl2D, clifford, acesToneMap; dipole/curl/attractor field composition; readTexture warp sampling; readDepthTexture passthrough; param mappings (Warp Strength / Plasma Mix / Turbulence / Attractor Mix).
ADD (2 native ideas):
  1. Larmor gyration: the sample point circles its guiding centre at cyclotron frequency ω_c ∝ |B| with Larmor radius r_L = v⊥/ω_c — tight fast spin in strong-field regions, wide lazy loops in weak gaps. v⊥ from Warp Strength, heated by treble.
  2. Synchrotron emission tint (replaces the bogus plasmaBuffer[luma*255] "spectral" lookup): emissivity j ∝ B^1.75 (power-law p≈2.5), critical frequency ν_c ∝ γ²B picks ember→magenta→blue-white colour, bass pumps γ; linear polarisation ⊥ B revealed by a rotating polariser (mids) as cos² fringes. Plasma Mix blends it in.
FLOOR FIXES: header replaced; uniforms comment lists sliders; bass/mids/treble clamped 0..1 with controlled gains (bass was ×(1+bass) full-gain); removed out-of-range plasmaBuffer[0..255] read (buffer holds 150 vec4 of plasma-ball data, not a palette); added mouse-held (energised dipole ×(1+held·1.2)); added click ripples as Alfvén-wave transverse kinks (loop to min(config.y,50)); alpha now = radiated field energy (field/attractor/emissivity/Alfvén/gyration) instead of mixing source alpha; depth now field-modulated; readTexture load coords clamped; A = same ACES RGBA as writeTexture. No dataTextureB/C, no extraBuffer. JSON: params array, features (+audio-reactive, mouse-driven, upgraded-rgba, click-reactive, depth-aware), workgroup_size 8→16 to match WGSL; updatedParams unchanged.
FORBID: plasmaBuffer indices other than 0, extraBuffer outside 133..138, dataTextureB writes, textureSample on dataTextureC, fake audio from config.y/zw/zoom_config.x, generic bloom/IQ palette overlays.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok (naga OK, bindgroup compatible, 0 extraBuffer violations) / extraBuffer audit PASS / sliders x (dipole + v⊥ gyration), y (synchrotron mix), z (turbulence warp), w (attractor weight) live


---

SHADER: gen-magnetic-kelp
IDENTITY: Subsea kelp forest: lanes of swaying strands (pendulum modes + FBM), fronds, bioluminescent tips, drifting spores, cursor magnetism bending the forest, smoothed-bass envelope, temporal persistence.
KEEP VERBATIM: hash/noise/fbm, bass_env, palette, lane/seed layout, swayBase/swayHarmonic/current/fbmSway/organicWidth, magneticPull, frond/tip/spore rendering and colours, temporal mix, param mappings (Strand Density / Current Speed / Magnetism / Biolume).
ADD (2 native ideas):
  1. Holdfast-anchored cantilever: sway and surge are shaped by the Euler-Bernoulli cantilever profile w(s) ∝ s²(3−s) from the seafloor holdfast (s=0) to the free tip, stiffened by bladder buoyant tension; drag load grows with Current Speed. Tips/glow moved to the free (surface) end; stipes fade in at the holdfast.
  2. Pneumatocyst gas bladders: per-stipe floats alternating sides at blade bases (spacing from Strand Density), bobbing with the swell (smoothed bass), amber translucent body with bioluminescent rim (Biolume, mids) and gas specular highlight (treble); their lift is the tension term in idea 1.
FLOOR FIXES: header replaced; uniforms comment lists sliders; extraBuffer[0] (engine-reserved) bass-envelope state relocated to extraBuffer[133], read and write guarded by arrayLength > 138u; textureSampleLevel(dataTextureC) → exact clamped textureLoad; hardcoded alpha 1.0 → canopy coverage alpha; dataTextureA was packing (strand, frond, glow, 1) → now same ACES RGBA as writeTexture; depth was 0 → canopy height/bladder depth; audio clamped 0..1; mouse X now aspect-corrected; added mouse-held (magnetism ×(1+held·1.5)) and click ripples as radiating surge waves loaded through the cantilever (loop to min(config.y,50)). No fake audio found. JSON: params array, features (+audio-reactive, mouse-driven, upgraded-rgba, click-reactive, depth-aware, temporal); updatedParams unchanged.
FORBID: extraBuffer indices outside 133..138, dataTextureB writes, textureSample on dataTextureC, fake audio, new springs, replacing the strand motif with generic noise.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok (naga OK, bindgroup compatible, 0 extraBuffer violations) / extraBuffer audit PASS / sliders x (lane density + bladder spacing), y (sway speed + drag bend), z (magnetic pull), w (frond/tip/rim glow) live


---

SHADER: gen-magnetic-storm
IDENTITY: Mouse-positioned magnetic pole in a turbulent curl-noise storm; divergence-free flow drawn as sin field-line bands (cyan), FBM energy, orange corona and purple energy rings around the pole, treble sparkle, vignette.
KEEP VERBATIM: hash12/hash22, vnoise, curl, fbm, aces, hsv2rgb; dipole 1/r² pole field, curl flow, field-line bands, corona, rings, sparkle, vignette, depth from pole proximity; param mappings (Field Scale / Flow Speed / Line Density / Storm Power).
ADD (2 native ideas):
  1. Alfvén-wave kinks: transverse waves travel along the local field direction with phase speed v_A ∝ √|B| (|curl + dipole|), so band coordinates ripple fast near the strong pole and crawl in weak gaps. Wavenumber from Line Density, amplitude from Storm Power + mids, speed from Flow Speed.
  2. Storm-expanded auroral oval: precipitation oval around the pole whose radius grows equatorward with Storm Power, bass and mouse-held (substorm); curtain folds from FBM in pole angle + curl flow; sharp inner 557.7 nm oxygen-green edge, diffuse outer 630 nm red crown, field-aligned ray striations flickering with treble.
FLOOR FIXES: header replaced; uniforms comment lists sliders; removed duplicate acesToneMap (was double-tonemapped: aces() then acesToneMap()) — now single ACES and same display RGBA to writeTexture and dataTextureA; audio clamped 0..1 with softened gains; no fake audio found (config.y only as ripple bound); added click ripples (none before) as sudden-storm-commencement shock fronts that compress field-line bands; mouse-held now strengthens the pole, corona and aurora (previously only an alpha multiplier); alpha includes aurora/shock energy. No dataTextureC/B/extraBuffer usage. JSON: params array added, features audio-reactive/mouse-driven/upgraded-rgba/click-reactive; updatedParams unchanged.
FORBID: extraBuffer indices outside 133..138, dataTextureB writes, textureSample on dataTextureC, fake audio from config.y/zw/zoom_config.x, second tonemap pass, generic bloom/palette overlays.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok (naga OK, bindgroup compatible, 0 extraBuffer violations) / extraBuffer audit PASS (no use) / sliders x (field scale), y (flow + Alfvén speed), z (line density + kink wavenumber), w (storm power, kink amplitude, oval radius, aurora gain) live


---

SHADER: gen-mandelbox-explorer
IDENTITY: 2D slice through the 3D Mandelbox (boxFold + sphereFold + scale, c = (x,y,0)), orbit-trap min/avg coloring (warm/cool metal, AO from orbit min, HDR specular highlight), mouse-x rotation, subtle temporal persistence, chromatic offset, ACES.
KEEP VERBATIM: boxFold, sphereFold, fractalDimension, acesToneMap; escape-time loop and orbit traps, warm/cool/AO/highlight/edge tint, chromatic offset, depth, mouse rotation; param mappings (Box Scale / Iterations / Slice Thickness / Specular).
ADD (2 native ideas):
  1. Running-derivative distance estimate: mandelboxDE tracks dr (box folds isometric, sphere folds scale by fold factor, ×|scale|+1), DE = |z|/|dr|. Four samples (center + x/y/slice-axis offsets, shared 28-iteration cap) give a true 3D gradient normal → diffuse + Blinn metallic lighting on the boundary shell (shininess and strength from Specular, treble glint) plus faint iso-distance contours. Shading only — no marching, so no Lipschitz risk.
  2. Fold itinerary coloring: per-orbit counts of box-fold reflections (per clamped component), sphere-shell inversions and core (min-radius) scalings; reflection-dominated orbits tint brushed steel, inversion-dominated gold, core-scaled violet (mids widen the blend), with an escape-iteration parity band on escaping orbits.
FLOOR FIXES: header replaced (legacy multi-line feature list removed); uniforms comment lists sliders; textureSampleLevel(dataTextureC, drifting uv) → exact clamped textureLoad; feedback moved to display space; dataTextureA previously got pre-tonemap HDR — now same ACES display RGBA as writeTexture; mids/treble added (only bass before), bass→scale gain reduced 0.25→0.06 and clamped; no fake audio sources found; added click ripples (none before) as a fold-radius shock that swells the sphere fold min radius as a ring passes; mouse-held now scrubs the slice along the third axis with mouse.y (rotation preserved); alpha includes DE shell + shock. JSON: params array added, features audio-reactive/mouse-driven/upgraded-rgba/click-reactive/temporal; updatedParams unchanged.
FORBID: extraBuffer indices outside 133..138, dataTextureB writes, textureSample on dataTextureC, fake audio, raymarching with a non-conservative DE, generic noise/bloom overlays.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok (naga OK, bindgroup compatible, 0 extraBuffer violations) / extraBuffer audit PASS (no use) / sliders x (box scale), y (iterations), z (slice depth), w (specular + DE lighting shininess) live


---

SHADER: gen-metaball-soft-body
IDENTITY: 3–6 orbiting liquid-metal metaballs (r²/d² implicit field), mouse gravitational attraction (3x when held), Fresnel/spec metal shading, subsurface interior, gradient caustics, merge glow, treble sparkle, video luma-flow distortion, display-space trail.
KEEP VERBATIM: acesToneMapping, hash12, bass_env, orbit/radius/gravity formulas for body centres, luma-flow distortion, mouse-held shockwave, gradient/fresnel/spec/surfaceMask shading stack, baseMetal/subSurf/caustic/mergeGlow/treble sparkle, trail mix, slider mappings (Ball Count / Surface Roughness / Metal Hue / Caustic Strength).
ADD (2 native ideas):
  1. Rayleigh droplet shape-oscillation modes: each body's radius is angularly modulated by capillary modes l=2 (squash) and l=3 (trefoil) ringing at ω_l ∝ √(l(l−1)(l+2)); l=2 amplitude from bass envelope + mouse held, l=3 from treble; click ripples send a pressure wave that excites nearby bodies on arrival, decaying with viscous damping set by Surface Roughness. Normals include the deformation.
  2. Rayleigh–Plateau neck beading: for the two dominant contributors, a varicose perturbation with wavelength 9.02 × neck radius runs along the bridge axis, growing as the bridge stretches (gap/radii); crests render as cool satellite-droplet glints on the surface (mids drive amplitude/drift).
FLOOR FIXES: header replaced; bounds check added; plasmaBuffer bass/mids/treble clamped 0..1 (mids now used); textureSampleLevel(dataTextureC, uv) -> clamped exact textureLoad; per-pixel bass envelope formerly packed into A.r relocated to guarded extraBuffer[133] (single writer pixel 0,0); A previously held (bassEnv, r, g, alpha) -> now identical ACES display RGBA to writeTexture; output no longer a pre-mix with inputColor (input kept as flow distortion + metal env reflection); alpha = surface/interior coverage + glints/rings + trail persistence; click ripples added (loop min(config.y,50)) — lacked them before; mouse attraction now aspect-corrected; no fake audio found (config.y only ripple bound); no dataTextureB writes. JSON: features (was []) + params array added, updatedParams byte-identical.
FORBID: extraBuffer outside 133..138, dataTextureB writes, textureSample on dataTextureC, fake audio, generic bloom/noise overlays, replacing the metaball motif.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok (naga OK, bindgroup compatible, 0 extraBuffer violations) / extraBuffer audit PASS / sliders x (ball count), y (spec exponent + mode viscosity), z (metal hue), w (caustic) live


---

SHADER: gen-micro-cosmos
IDENTITY: Raymarched microscopic current: domain-repeated translucent ellipsoid cells drifting in an audio-driven helical flow, rim/SSS glow, membrane runners, organelle specks, marine snow, click-spawned microbe blooms, advected wake history.
KEEP VERBATIM: sdEllipsoid, rotate2D, hash, map (helical current, domain repetition, per-cell rotation/wobble/bump), calcNormal, raymarch, camera path + mouse ray perturbation, diffuse/rim/SSS/membraneRunner/innerGlow/fog shading, marine snow loop, ripple bloom loop, helical wake advection, slider mappings (Population Density / Fluid Activity / Membrane Glow / Color Shift).
ADD (2 native ideas):
  1. Zernike phase-contrast imaging: optical thickness through each cell (12 interior SDF samples) -> phase shift -> phase-dark intensity + wavelength-dependent thin-specimen interference tint (mids scale OPD); near-miss rays render the characteristic phase-contrast halo outside cell edges (treble lift). Mouse held swaps the condenser to darkfield around the cursor: background goes black, only edge-scattered light and marine snow shine.
  2. Binary fission cell cycle: each cell (rand > 0.35) runs its own cycle; late in the cycle the body splits into two daughter ellipsoids joined by a smooth-min whose blend radius shrinks — a cleavage furrow pinches and daughters drift apart (bass pushes them). Division progress rides in the material id and warms the furrow rim.
FLOOR FIXES: "COPY PASTE THIS HEADER" junk replaced with standard header; g_audio clamp 0..2 -> 0..1 via named bass/mids/treble; audio removed from time multipliers (was time*(…+audio), causing phase jumps) -> additive phase offsets; textureSampleLevel(dataTextureC, uv) -> clamped integer textureLoad with rounded pixel advection; no ACES before -> ACES display colour; alpha hardcoded 1.0 -> specimen coverage/optical density + snow/bloom/halo + wake persistence; A and writeTexture now receive identical RGBA; mouse-held (zoom_config.w) had no effect -> darkfield condenser; config.y only ripple bound (no fake audio); no extraBuffer use; no dataTextureB writes. JSON: upgraded-rgba feature + params array added, updatedParams byte-identical.
FORBID: extraBuffer outside 133..138, dataTextureB writes, textureSample on dataTextureC, fake audio, generic bloom/palette overlays, replacing the microorganism motif.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok (naga OK, bindgroup compatible, 0 extraBuffer violations) / extraBuffer audit PASS (no extraBuffer use) / sliders x (grid density), y (flow, fission rate, wake), z (glow, halo, phase tint), w (palette, interference offset) live


---

SHADER: gen-minimal-surface-soap-iridescence
IDENTITY: Parametric catenoid↔helicoid minimal surface morphing by Bonnet rotation, evaluated per pixel in (u,v) parameter space, with hsv thin-film interference, Fresnel rim, tension-controlled specular, SSS, curvature caustics, HDR bloom, dataTextureC trails, fog, grading, ACES; mouse-held dimple.
KEEP VERBATIM: surfacePoint / surfaceTangentU / surfaceTangentV, rotateY, hsv thin-film phase model, lighting stack (rim/spec/sss/caustics), bloom, temporal memory, fog, grain, colorTemperature/splitTone, genChromaticShift, mouse dimple, param mappings (Bonnet Rotation / Surface Tension / Y Rotation / Caustic Glow).
ADD (2 native ideas):
  1. Gravity drainage + Marangoni marginal regeneration: film thickness follows a Mysels-type sqrt(depth-below-top) drainage profile (thin top, thick bottom wedge); swirling fbm plumes of thinner film rise from the bottom border (marginal regeneration), speed/strength from Surface Tension, swirl from mids. Where h → 0 the film becomes Newton black film (interference colour suppressed ~93%, coverage alpha reduced). No new thin-film overlay — it modulates the existing filmThick fed to the existing phase model.
  2. Culick rupture holes on click: each ripple punctures the film; hole radius grows at Culick speed ∝ sqrt(σ/h) using local drained thickness (holes race through black/thin film, stall in the thick wedge), toroidal liquid rim (width ∝ sqrt(radius)) beads into droplets via a Rayleigh–Plateau angular modulation whose bead count grows with radius; film re-wets after ~3 s. Rim brightness from Caustic Glow + treble, hole speed kicked by bass; holes zero alpha/depth.
FLOOR FIXES: header replaced with standard format; Uniforms comment lists sliders; plasmaBuffer bass/mids/treble clamped 0..1 (no fake audio found); dataTextureC textureLoad now uses clamped coords; click ripples added (loop to min(u32(u.config.y), 50u)) — shader had none; alpha extended with black-film/hole/rim semantics; same ACES RGBA to writeTexture and dataTextureA (already), no dataTextureB writes, no extraBuffer use. JSON: params array added; features + mouse-driven, upgraded-rgba (audio-reactive already present); updatedParams unchanged.
FORBID: extraBuffer indices outside 133..138, dataTextureB writes, textureSample on dataTextureC, fake audio from config.y/zw/zoom_config.x, generic thin-film/rainbow overlays on top of the existing interference.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok (naga OK, bindgroup compatible, 0 extraBuffer violations) / extraBuffer audit PASS (no use) / sliders x (Bonnet morph + grading), y (tension: rim/spec/fog + drainage plume speed + Culick speed), z (Y rotation), w (exposure/bloom/trail decay + rupture rim glow) live


---

SHADER: gen-molten-planetary-core
IDENTITY: Orthographic molten iron sphere: fbm Bénard convection mapped through a blackbody ramp, bass-driven mantle plumes, treble crust cracks, dark crust lid, atmospheric limb rim; mouse-held view offset.
KEEP VERBATIM: hash21/hash31/noise2/fbm3, convectionCell, acesToneMap, sphere mask/normal/sUV, blackbody ramp, plume field, crack/crust logic, rim glow, mouse-held tilt, param mappings (Convection / Plume Intensity / Crust Thickness / Glow).
ADD (2 native ideas):
  1. Busse columnar convection (busseColumns): rotation-aligned convection columns forming a cartridge belt of alternating cyclones/anticyclones outside the tangent cylinder (s > 0.35), sheared by thermal-wind differential rotation (prograde equator / retrograde inward, drift + mids), shear-line glow between columns, and a spiral polar vortex inside the tangent cylinder. Column count m = 6..16 from Convection (higher Rayleigh number); perturbs the existing temperature field.
  2. Plume-head coronae (coronae): in conformal stereographic coords (circles stay circular), cellular plume heads run a life cycle — dome heat + radial dike swarm → annular trough + concentric fracture ring → quiet. Plume Intensity sets how many are active and dome heat, bass boosts strength, treble/quake light the dikes, troughs thicken the dark lid (scaled by Crust Thickness).
FLOOR FIXES: header replaced with standard format (was older upgraded-rgba tag but did not meet floor); Uniforms comment corrected (y=RippleCount) with slider names; plasmaBuffer clamped 0..1; DOUBLE ACES removed (was toneMap → fake post-tonemap constant "CA" offset → toneMap again) — now single ACES with a pre-tonemap limb dispersion; alpha now coverage × incandescence + limb halo (was near-constant 0.9); pixel-centre uv; click ripples added (none before) as seismic P-wave rings that shake cracks open and thin the lid; same RGBA to writeTexture and dataTextureA, no dataTextureB/dataTextureC/extraBuffer use. JSON: features was [] → audio-reactive, mouse-driven, upgraded-rgba; params array added; updatedParams unchanged.
FORBID: extraBuffer indices outside 133..138, dataTextureB writes, textureSample on dataTextureC, fake audio from config.y/zw/zoom_config.x, generic bloom/noise overlays, replacing the blackbody sphere motif.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok (naga OK, bindgroup compatible, 0 extraBuffer violations) / extraBuffer audit PASS (no use) / sliders x (convection speed + Busse column count), y (plumes + coronae population/dome heat), z (crack width + trough lid), w (glow gain incl. column shear + coronae) live


---

SHADER: gen-multi-scale-evolutionary-cellular-gardens
IDENTITY: Three-species evolving cellular automaton (teal coral, magenta fungal network, amber lichen) on a regenerating resource substrate; rule thresholds drift over time (evolving genetics), near+far multi-scale neighbourhood competition, mouse-held invasive seeding.
KEEP VERBATIM: hash12/hash13/smoothNoise, growthKernel, speciesColor (colours, substrate glow, iridescence), rulePhase/rulePhase2/rulePhase3 drift, near/far 0.7/0.3 weighting, competition terms, resource regen/consumption, mouse dominant-species burst + resource injection, low-population random seeding, clamps, slider mappings (Mutation Rate, Species Competition, Fertility, Diversity), depth = totalPop*0.4.
ADD (2 native ideas):
  1. Mycorrhizal hyphal transport: where the fungal species (s2) is dense, substrate flows from the far (3-texel) neighbourhood toward local deficit (conductance smoothstep(avgS2) * (0.2 + mids*0.1)); coral fed by the network gets a small mutualist growth bonus.
  2. Red Queen frequency-dependent rule drift: each species' evolved rule phase is pushed up by its local dominance fraction (s_i/pop * 0.25*(0.5+Mutation Rate)*(1+treble*0.4), capped 1.3), narrowing the activation/inhibition band for the commonest genotype and curbing monocultures.
FLOOR FIXES: all ~17 textureSampleLevel(dataTextureC) reads -> exact clamped textureLoad; state moved out of raw A packing into an exactly invertible display encoding (see A PACKING); separate premultiplied writeTexture output replaced by identical RGBA to writeTexture and dataTextureA; ACES added; audio clamped 0..1; audio "genetic pressure" was a flat +0.06*bass added to every pixel every frame (spontaneously fills bare substrate) — now halved and gated by local presence of that species; click ripples added (founder-spore rings seeding the locally rarest species, min(config.y,50)); uniforms comment lists sliders; hash22 p3/p4 typo fixed; no extraBuffer, no dataTextureB; JSON params array + features added.
FORBID: drawing non-invertible overlays into the output (tip glow / boundary glow / dither / bass-scaled exposure would feed back as fake species); premultiplying RGB by alpha (amplifies decode error); dataTextureB writes; extraBuffer.
A PACKING: ACES display RGBA in A — RGB = ACES(1.1 * floored vignette * speciesColor(s1,s2,s3,res,colorPhase)), alpha = 1-exp(-(0.9*pop+0.45*res+0.05)) (Beer-Lambert canopy+substrate coverage). Next frame decodes state from C via analytic inverse ACES + inverse pigment matrix (colorPhase is audio-free so encode/decode match). CPU round-trip check with float32 storage: max error 8e-6. Trade-off: the old tip-glow / competition-boundary / resource-glow overlays were dropped from the image because they cannot be decoded; the vignette is floored at 0.35 to stay invertible. Sim is also slightly sharper than before (old bilinear corner sampling acted as a blur).
VERIFY: naga ok / gate ok / extraBuffer ok (AUDIT PASS) / sliders x,y,z,w live / JSON ok, updatedParams byte-exact


---

SHADER: gen-murmuration-phantom
IDENTITY: Starling murmuration against a twilight sky: curl-noise advected flock volume, golden-ratio spiral density, morphing sphere/torus/wave/fbm envelopes, silver edge glints, indigo/violet/sunset palette, persistent trails, mouse predator disturbance, click scatter.
KEEP VERBATIM: h2/h3/n2/n3/fbm2/fbm3/pot/curl, acesToneMap, huePreserveClamp, ign, flock centre drift, shape morph chain, spiral mask, density fbm, edge derivative, palette build, scatter ripple response, trail decay 0.93-bass*0.04 and 5% colour history mix, chromatic offset, slider mappings (Flock Size, Shape Morph, Glint Intensity, Cohesion).
ADD (2 native ideas):
  1. Predator-triggered banking agitation waves: bands travel outward from the predator (sin(dist*18 - t*6)) modulating apparent density 0.35..1.25 as birds tilt wing-on (dark) vs edge-on (light); agitation = hover baseline + mouse-held stoop + recent click + bass, fading with distance; edge-on bands boost glints.
  2. Marginal-opacity self-regulation: flock optical depth saturates (tau = tauMax*d/(d+0.15), tauMax scaled by Cohesion) so the core transmits ~20-30% of a vertical twilight sky gradient through dark silhouettes; alpha = 1 - T (sky coverage).
FLOOR FIXES: textureStore(dataTextureB) removed; textureSampleLevel(dataTextureC) -> exact clamped textureLoad; writeTexture (was premultiplied outCol*a) and dataTextureA (was outCol + raw trailDensity) now receive the identical ACES RGBA; trail density now recovered from C.a by inverting the coverage function; audio clamped 0..1; mids was read but unused -> now nudges Shape Morph (+0.15) as the description promised; mouse-held (zoom_config.w) was ignored -> now a stronger/wider predator stoop plus full banking waves; ripple loop bounded by min(u32(config.y),50u); no fake audio found (config.y only ripple count); no extraBuffer; header replaced; JSON params + features added.
FORBID: dataTextureB writes, extraBuffer, replacing flock motif, generic bloom/noise overlays.
A PACKING: ACES display RGBA in A (alpha = flock coverage 1-T plus transmitted glint/scatter; C.rgb = colour history, C.a inverted as approximate trail density — glint contributions slightly overestimate it, decays geometrically at 0.93).
VERIFY: naga ok / gate ok / extraBuffer ok (AUDIT PASS) / sliders x,y,z,w live / JSON ok, updatedParams byte-exact


---
