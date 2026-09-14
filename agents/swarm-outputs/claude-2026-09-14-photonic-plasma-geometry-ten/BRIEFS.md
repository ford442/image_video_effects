# Photonic / plasma / geometry generative ten — Idea Cards (2026-09-14)

Contract: CONTRACT.md. Two native ideas each; identities kept; no new springs. Naga 10/10, precommit gate 10/10, extraBuffer audit PASS, updatedParams unchanged 10/10, no params ids renamed. Real-GPU QA external.

SHADER: gen_orb (JSON id "gen-orb", name "Lorenz Strange Attractor")
IDENTITY: Audio-reactive Lorenz strange attractor — RK4-integrated streams (8..14) projected with velocity-sized glow, bioluminescent depth halos, persistent scent trail.
KEEP VERBATIM: hash3, lorenzDerivative, rk4Step, acesToneMapping, stream loop (warmup 500 / 400 steps), hue ramp, halo/line glow, butterfly wing highlights, vignette, σ/ρ/β mappings.
ADD (2 native ideas):
  1. Lobe-switch sparks — white-hot pinpoints where a trajectory crosses x=0 (hop between the two wings), treble-brightened.
  2. Unstable fixed-point eyes C± = (±√(β(ρ−1)), ±√(β(ρ−1)), ρ−1) — projected cores + rings whose radius tracks √(β(ρ−1)) (moves with the σ/ρ/β sliders), bass-swelled.
FLOOR FIXES: plasmaBuffer[0].xyz clamped; textureSampleLevel(dataTextureC) -> exact clamped textureLoad; trail now feeds back the ACES display RGBA (same RGBA to writeTexture + dataTextureA, previously A held an HDR trail != output); readTexture composite removed (pure generative output, alpha = glow presence / trail coverage); resolution bounds check added; mouse added (hold+drag orbits/tilts camera; no effect when not held so default look unchanged); click ripples added (butterfly-effect kick on jitter amplitude + faint expanding ring, loop min(config.y,50)); projection factored into projectLorenz (identical math); header replaced; Uniforms comment lists sliders. JSON already compliant (params + updatedParams + features) — unchanged.
FORBID: extraBuffer use, dataTextureB writes, plasmaBuffer beyond [0], ripples[i].w scaling.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x(σ),y(ρ),z(β),w(trail persistence) live

---

SHADER: gen-percolation-threshold
IDENTITY: Site percolation on an 80x60 square lattice near p_c ≈ 0.5927; iterative min-label connected-component flood fill, jewel-tone cluster colours, HDR bloom on the spanning cluster.
KEEP VERBATIM: hash12, acesToneMap, p = p_c + bass/slider shift, latticeZoom/bloom/grain mappings, jewel hue from label, edgeCount rim tint + chromatic offset, grain, clusterProxy alpha, depth output.
ADD (2 native ideas):
  1. Backbone conduction pulses — on the spanning cluster, current pulses travel left->right (bass speeds them, treble brightens); weight (1 − edgeCount/4)^2 so dangling ends carry little current.
  2. Critical opalescence — multi-scale (1/4/16-site) fluctuation haze on empty sites and milky tint on finite clusters, strength exp(−40|p − p_c|) so it blooms as threshold slider / bass push p to p_c.
FLOOR FIXES: removed all extraBuffer use (extraBuffer[gid.y], [latticeH+gid.y], [i]/[latticeH+j] reads — forbidden indices, stomped by audio upload). Spanning now detected via touchesLeft/touchesRight flags propagated through the flood fill in texture state (A->C exact textureLoad). Epoch stamp in state resets labels/flags on reseed (old code leaked min labels across epochs). Occupancy made a stateless function (hash + mouse/ripple doping) shared by sim and display. Mouse paint (previously overwritten next frame = dead) -> held mouse forces a 2.5-site doped disk; click ripples added (expanding doped rings, 3 s). plasmaBuffer clamped, mids/treble used. Background branch now ACES-mapped, writes A and depth (previously early-return without A). JSON: params array added, features = audio-reactive, mouse-driven, upgraded-rgba (was []).
FORBID: extraBuffer outside 133..138 (none used), dataTextureB writes, textureSampleLevel on C.
A PACKING: texels [0..79]x[0..59] = (cluster label, epoch stamp, touchesLeft, touchesRight) raw sim state; all other texels = ACES display RGBA
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x(threshold),y(zoom),z(bloom),w(grain) live

---

SHADER: gen-phase-transition-memory-weave
IDENTITY: Landau order-parameter field switching between fluid (blue), chaotic (red-purple) and crystalline (white-gold hex lattice) phases, with true hysteresis via dataTextureC feedback (order relaxes toward a diffused copy of its past), spring-smoothed mouse stir/press nucleation, click crystallization fronts.
KEEP VERBATIM: orderParameter, fluidFlow, chaoticPattern, phaseColor, 5-tap C diffusion + memK relaxation, spring mouse in extraBuffer[133..138], ripple nucleation fronts, memory-weave ghost, vignette, slider mappings.
ADD (2 native ideas):
  1. Schmitt-latch hysteresis loop: per-pixel phase latch (A.b) freezes only above freezeT=0.5+w and melts only below meltT=0.5-w (w=0.12, narrowed by bass); latched crystal persists down to meltT. Transitions release (+) / absorb (-) latent heat stored signed in A.a, decaying 0.93/frame -> warm flash on freezing, cold flash on melting.
  2. Polycrystalline grains: Voronoi of hashed nucleation sites gives each grain its own hex-lattice orientation (0..60 deg); crystallineLattice now rotated per grain; grain boundaries suppress lattice and glow as seams in crystalline regions (treble-scaled).
FLOOR FIXES: removed fake-audio/forbidden extraBuffer[6..13] FFT reads (replaced by plasmaBuffer[0].y/.z proxies); plasmaBuffer bands clamped 0..1; extraBuffer 133..138 guarded with literal arrayLength(&extraBuffer) > 138u; ACES tone map added (replaces hard clamp); straight semantic alpha (luma + phase boundary + crystal fraction) instead of premultiplied output; header/uniform comments standardized; JSON params array + features added.
FORBID: extraBuffer outside 133..138, textureStore to dataTextureB/C, replacing the order-field feedback, scaling clicks by ripple.w.
A PACKING: raw sim state (R=order, G=memory weave, B=hysteresis latch 0/1, A=signed latent heat); ACES display RGBA on writeTexture (A must stay state so the C hysteresis feedback survives)
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x (viscosity: memK + weave), y (phase scale), z (transition sharpness), w (glow) live

---

SHADER: gen-photonic-crystal-brain
IDENTITY: Raymarched infinite cubic lattice of crystal "neurons" (smooth-unioned rods + nodes) flown through along z, cosine/OkLab volumetric synapse glow, blackbody + Fresnel rim shading, mouse pulls the lattice.
KEEP VERBATIM: map SDF (rods/sphere/disp), OkLab/blackbody/cosine palette functions, camera wobble, glow accumulation, lighting/fog, applyGenerativePrimaryControls post (default look).
ADD (2 native ideas):
  1. Bragg-reflection structural color: lambda = 2*n_eff*d*cos(theta) (n_eff 1.45, d from lattice spacing slider), 1st+2nd order mapped to spectral RGB; stop band drifts red->blue with viewing angle, vanishes outside visible. Treble scales strength.
  2. Line-defect waveguide spikes: sparse hashed cells (45%) carry a Gaussian photon packet travelling along one of their rods (random axis/direction), rate driven by mids — firing axons inside the crystal.
FLOOR FIXES: added dataTextureA write (same RGBA as writeTexture); ACES then controls, final clamp 0..1; semantic alpha = hit coverage (distance-fogged) + glow density (was luma+0.2); raymarched depth instead of passing readDepthTexture through; div-by-zero guard on spacing (4/max(x,0.05)); glow was plasma-bass-only (black at silence) -> 0.25 + bass*0.35; bands clamped; added click ripples (action-potential shells expanding through lattice in world XY, min(config.y,50)); added mouse-held (stronger lattice pull + stimulation glow); Mouse Influence slider now scales pull (0.4*w, default 0.5 == old 0.2). config.y had no prior reads (note matched zoom_config.y). No extraBuffer / C use.
FORBID: extraBuffer use, dataTextureB writes, replacing the lattice motif, ripple.w scaling.
A PACKING: ACES display RGBA in A (C unused)
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x (spacing + primary intensity), y (pulse speed), z (distortion + contrast), w (glow + mouse pull) live

---

SHADER: gen-phyllotaxis-galaxy-spiral
IDENTITY: Vogel golden-angle phyllotaxis (r = c*sqrt(n), theta = n*137.5deg) where each of 350 florets is a Gaussian star in a rotating disk galaxy; Lin-Shu density-wave radial perturbation; Hubble palette (young blue / main-seq yellow / old red / supernova candidate), treble supernova flares, per-star dust extinction, depth fade, chromatic aberration on giants, mouse-held viewpoint offset.
KEEP VERBATIM: PHI/TAU, hash11, star loop (theta/r/wave/rWave/depth/size/starShape early-out), Hubble palette thresholds, supernova flare, depthFade/dust/extinction, maxDepth depth output, CA block, mouse-held viewOffset = (mouse-0.5)*1.5, mids disk-rotation offset.
ADD (2 native ideas):
  1. Sersic (n=2) bulge + exponential-disk unresolved starlight: warm bulge exp(-3.67*sqrt(r/0.25)) and a cool exponential disk (h=0.38) whose surface brightness is lifted on the density-wave crest (same 2-arm phase 2*phi + 40r as the stars), mids-lifted.
  2. Density-wave arm anatomy: a trailing dust lane just upstream of each crest (phase +0.9) absorbs up to 60% of the light, and hashed HII emission knots (pink H-alpha) sit on the crests; both scale with Wave Density, knots pulse with mids and flare under click shocks.
FLOOR FIXES: double ACES removed (inline ACES + applyGenerativePrimaryControls ACES) -> single acesToneMap; writeTexture and dataTextureA now receive the identical RGBA (previously A got a different, un-controlled color); audio clamped 0..1; generic applyGenerativePrimaryControls removed and its default-equivalent parts folded in (Star Size keeps the twinkle-pulse rate, hover glow kept at its default w=0.5 strength; x intensity and z gamma were identity at defaults); dead sliders z (Disk Rotation) and w (Wave Density) wired natively; click ripples added (star-formation shock rings, min(config.y,50), age from ripples[i].z, ignite young blue stars); no config.y misuse existed beyond ripple count; no extraBuffer, no dataTextureB, no C use; uniforms comment lists sliders; JSON params array + features added (updatedParams untouched).
SLIDERS: x Star Spread -> c = 0.012 + x*0.015 (unchanged); y Star Size -> size*(1+y) + twinkle rate mix(0.25,5,y) (unchanged); z Disk Rotation -> rotAngle = time*0.08*(z/0.3) (default 0.3 == old 0.08 rate); w Wave Density -> densityWaveAmp = (0.15+bass*0.25)*(2w) and dust/HII/disk-arm strength (default 0.5 == old amplitude).
FORBID: plasmaBuffer beyond [0]; scaling clicks by ripples[i].w; dataTextureB writes; extraBuffer; re-adding a second ACES pass.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok (naga OK, bindgroup compatible) / extraBuffer ok (AUDIT PASS, 0 violations) / sliders x,y,z,w live / JSON ok, updatedParams byte-exact

---

SHADER: gen-physarum-sacred-geometry
IDENTITY: Physarum slime-mold chemotaxis (three-sensor sense/turn/move/deposit, blurred decaying pheromone trail) feeding on domain-warped video, laid over hexagonal sacred-geometry masks with Mandelbrot orbit-trap accents, cosine-palette trail colouring composited over the source video; mouse repels agents.
KEEP VERBATIM: hash21/valueNoise/fbm/domainWarp/curlNoise, hexDist/sacredMask, mandelbrotTrap, sense() (only change: trail channel .r -> .a), old branchless turn decision (forwardWins/pinWheel/leftWins/rightWins/randomDir, turnSpeed = 0.5 + bass*2), 3x3 border-weighted blur loop, deposit 0.5*(1+geo), cosine palette a/b/c/d and t = trail*2 + geo*0.6 + accent*0.4, video composite, depth mix, applyGenerativePrimaryControls, mouse repel band smoothstep(R, 0.667R).
ADD (2 native ideas):
  1. Flower-of-Life compass construction with stateless hashed agents: 3 agents per circle ride circles of radius S centred on a triangular lattice (the Flower-of-Life construction), orbit direction/phase hashed per lattice point, radius wobbled by curlNoise; each frame the agent senses the previous trail (C.a) with the three sensors and the old turn decision bends it sideways (+-0.07S) onto the stronger strand, so neighbouring vesica arcs fuse into a shared network. Pixels gather deposits from lattice points within reach (annulus + per-agent cull before sensing).
  2. Tero flux-adaptive tubes: conductance = smoothstep(0.06,0.6,blurred trail) raises persistence (decay 0.94 -> 0.985) and deposition gain (0.6 -> 1.5), so used strands thicken and idle ones are pruned; high-conductance tubes get a protoplasmic-streaming glow (mids-lifted).
FLOOR FIXES: agent state in extraBuffer[agentIdx*4+k] (forbidden and overwritten every frame by the audio upload; sim never live) removed entirely -> stateless analytic agents + trail feedback in A/C alpha; fake audio u.config.y (click count) removed from curl bias, move speed and accent (accent now 0.5 + treble*0.5, same at silence); dataTextureA now receives the same ACES display RGBA as writeTexture (previously raw trail .r with alpha 1, writeTexture had no ACES); ACES added; alpha now semantic = pheromone density (was 1.0-ish); plasmaBuffer clamped; unused hash(u32) removed; mouse-held added (oat-flake food source: attracts orbits + warm glow); click ripples added (compass circle of radius S drawn into the trail, min(config.y,50)); uniforms comment lists sliders; JSON params array + features added (updatedParams untouched).
SLIDERS: x Intensity -> sensorAngle = x (default 0.5 == old 0.5 rad) + deposit gain mix(0.55,1.45,x) + primaryIntensity (1.0 at default, unchanged); y Speed -> orbit speed 1.5*(y/0.5) px/frame at 720p (default == old moveSpeed 1.5) + sensor distance + old pulse rate; z Scale -> lattice spacing S = res.y*mix(0.04,0.12,z) + old detailContrast gamma (unchanged); w Mouse Influence -> repel radius 240*w px (default 120px == old band) + old hover gain (unchanged).
FORBID: any extraBuffer index; dataTextureB writes; storing trail anywhere but A.a (display overlays in rgb are fine, alpha must stay pure trail); u.config.y as audio; plasmaBuffer beyond [0].
A PACKING: ACES display RGBA in A (alpha = pheromone trail density, fed back from C.a as the Physarum trail field)
VERIFY: naga ok / gate ok (naga OK, bindgroup compatible) / extraBuffer ok (AUDIT PASS, 0 violations, no extraBuffer refs) / sliders x,y,z,w live / JSON ok, updatedParams byte-exact

---

SHADER: gen-plasma-mandala
IDENTITY: Radially folded plasma mandala — dihedral angular fold (symmetry sectors with mirror), trig-sum plasma + FBM detail, cosine hue cycling, glow ring at r=0.5, fold-seam highlight, mouse-held pulls center.
KEEP VERBATIM: plasma(), fbm2()/noise2()/hash21(), sector fold math, hue cycling, seam highlight, vignette, spark, slider mappings (symmetry mix(3,12), spin mix(0.1,1), zoom mix(0.5,3), glow mix(0.5,3)), ACES on col*glow_scale*1.05.
ADD (2 native ideas):
  1. Diocotron-instability ring — the glow ring radius is perturbed by an azimuthal mode locked to the petal group (one wavelength per mirrored sector) plus a first-harmonic roll-up; rotates with spin (E x B drift), amplitude grows with bass; thin vortex-core highlight on the crests.
  2. Dihedral click pulses — each u.ripples[i] origin is folded into the same D_n fundamental domain as the pixel, so one click's expanding wavefront echoes in every petal (loop min(u32(config.y),50), age<2.5, never uses ripple.w). Adds to color and alpha.
FLOOR FIXES: plasmaBuffer[0].xyz now clamped 0..1; removed duplicate unused aces() helper; added click-ripple response (had none); Uniforms comment lists slider names; header refreshed (2026-09-14). Already OK: 13 bindings, ACES + semantic alpha (luma/ring/seam/pulse), same RGBA to writeTexture + dataTextureA, depth written, no dataTextureB/C writes, no extraBuffer use, no fake audio, all 4 sliders live, JSON params/features present (ids untouched).
FORBID: fake audio (config.y/zw/zoom_config.x), extraBuffer outside 133..138, dataTextureB writes, replacing the fold/plasma motif, renaming param ids.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (AUDIT PASS) / sliders x,y,z,w live

---

SHADER: gen-plasma-psychedelic-wormhole
IDENTITY: 1/r wormhole tunnel with contra-rotating multi-octave plasma, fbm swirl, radial bands and spiral arms, blackbody-temperature palettes (bass drives K), Doppler hue along travel, center glow, edge rings, streaming stars/streaks, temporal trail.
KEEP VERBATIM: blackbodyColor/plasmaPalette/hotPlasmaPalette, noise/fbm/stars, tunnel coordinate math, contra-rotating octave loop, Doppler hue, all existing layers, slider usage (intensity/speed/scale/colorShift), decay 0.96 / mix 0.25 trail, ACES(temporal*1.1), presence alpha.
ADD (2 native ideas):
  1. Photon-sphere subrings at the throat — three nested rings around throatR = 0.09 + scale*0.03 whose offsets/widths shrink by e^-pi per extra half-orbit (unstable circular orbit Lyapunov exponent); blackbody 6500..10000K with treble, scaled by Brightness.
  2. Click-spawned transient lensing masses — each ripple drops a point mass; thin-lens deflection alpha = thetaE^2/b pulls the tunnel coordinates toward it, with a hot Einstein-ring caustic; thetaE blooms then evaporates over 3s (bass +40%).
FLOOR FIXES: A previously held the raw HDR trail (differed from writeTexture) — now the same ACES display RGBA goes to writeTexture and dataTextureA; feedback recovers the HDR trail via analytic inverse ACES (/1.1) so the trail integration and look are preserved. dataTextureC load coords clamped. plasmaBuffer[0].xyz clamped 0..1. Added click-ripple response (had none). Depth store uses i32 pixel. Uniforms comment lists slider names; header refreshed (dropped legacy "temporal" from header Features line to match contract format; JSON features untouched). Already OK: 13 bindings, no extraBuffer, no fake audio, no dataTextureB writes, 4 sliders live, JSON params present.
FORBID: fake audio, extraBuffer outside 133..138, dataTextureB writes, textureSampleLevel on C, replacing the tunnel motif, renaming param ids.
A PACKING: ACES display RGBA in A (feedback recovers HDR trail via analytic inverse ACES)
VERIFY: naga ok / gate ok / extraBuffer ok (AUDIT PASS) / sliders x,y,z,w live

---

SHADER: gen-polar-rainbow-explosion
IDENTITY: Mouse-directed polar explosion of 36 neon rainbow rays, particle bursts, 3 spiral arms, center glow, bass-driven radial shock front (Mach split ahead/behind), treble ripple, heavy temporal trail.
KEEP VERBATIM: neonSpectrum, fbm/vnoise, ray loop (wavelength-scaled RGB ray widths, Mach ahead/behind split), particle bursts, spiral arms, center glow, shock glow ring, mouse-held burst, vignette, C feedback mix, CA offset, radius depth.
ADD (2 native ideas):
  1. Cauchy-dispersed click shock rings — each click (u.ripples, loop to min(config.y,50)) launches a polar front with per-channel radius age*v/n(lambda), n = 1 + 0.04/lambda^2, so red leads and violet trails; speed slider sets v, bass boosts.
  2. Descartes rainbow bows around the explosion origin — primary bow (red 42.3deg outside -> violet 40.6deg inside) and fainter reversed secondary (50.4 -> 53.4deg) mapped r = 0.5*tan(theta), Alexander's dark band darkening between them, faint inner-sky brightening; gain driven by mids and Intensity.
FLOOR FIXES: plasmaBuffer[0].xyz clamped 0..1; mids now used; A previously held pre-ACES HDR (different from writeTexture) -> same ACES display RGBA now written to writeTexture and dataTextureA; click ripples added (none before); legacy "Wolfram" header merged into contract header; Uniforms comment lists slider names. Already OK: 13 bindings, exact textureLoad C, no extraBuffer, no dataTextureB write, no fake audio, sliders x/y/z/w all live, JSON params/features already correct (unchanged).
FORBID: generic bloom/IQ palette overlays, renaming params ids (color_shift kept), writing dataTextureB, extraBuffer use, plasmaBuffer beyond [0].
COORDINATOR FIX: trail feedback decodes the stored ACES display via acesInverse(prev)/1.1 before the HDR mix, so the 75% persistence trail matches the pre-upgrade HDR trail.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (0 violations) / sliders x,y,z,w live

---

SHADER: gen-prism-tide
IDENTITY: Refractive spectral tide — concentric RGB interference wavefronts with crests, foam, sparkle, OkLab prism palette mix, animated caustics, Mie haze, split-tone grade, ACES, premultiplied output.
KEEP VERBATIM: palette/OkLab/ACES/huePreserveClamp/ignDither, noise/fbm, mieScattering, caustics, per-channel dispersionR/G/B phase, crest/foam/sparkle, palette overlay, caustics, haze, split tone, alpha/depth formulas, premultiplied output.
ADD (2 native ideas):
  1. Cauchy prism dispersion — per-channel phase offset (n(lambda) - n_green) * |refraction field| * waveScale, n = 1 + 0.012/lambda^2, so RGB wavefronts split into spectral fringes where the water refracts (violet bends most); treble widens the split; vanishes when Refraction = 0.
  2. Click tide packets with water-wave dispersion — each click sums 4 wavenumbers obeying w^2 = g k tanh(k h) (long waves outrun short, packet spreads), height perturbs the tide phase; packet steepness past the Miche limit (~0.142) spills breaking foam.
FLOOR FIXES: textureSampleLevel(dataTextureC, uv) -> clamped exact textureLoad; dataTextureA previously held (crest, foam, sparkle, alpha) while C feedback read it as color -> now same final RGBA as writeTexture; plasmaBuffer[0].xyz clamped; click ripples added (none before); mouse-held added (cursor acts as a denser prism lens boosting local refraction); params array added to JSON (waveScale/refraction/pulse/saturation, values copied from updatedParams); header replaced; Uniforms comment lists slider names.
FORBID: replacing the concentric tide motif, extraBuffer use, dataTextureB writes, plasmaBuffer beyond [0], changing updatedParams.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (0 violations) / sliders x,y,z,w live

---

