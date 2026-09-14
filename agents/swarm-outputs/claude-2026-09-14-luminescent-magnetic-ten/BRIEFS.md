# Luminescent / magnetic generative ten — Idea Cards (2026-09-14)

Contract: CONTRACT.md. Two native ideas each; identities kept; no new springs. Naga 10/10, precommit gate 10/10, extraBuffer/dead sliders 0, catalog 1,379 no dupes. Real-GPU QA external.

SHADER: gen-luminescent-quantum-silicate-diatom
IDENTITY: Raymarched lattice of octahedral silica frustules with simplex pores, volumetric bioluminescent cytoplasm, Fresnel iridescence, mouse-held micro-gravity well, camera drifting at Pulse Speed.
KEEP VERBATIM: rot, hash33, simplex3d, octahedron+simplex-pore map core, get_normal, cytoplasm volumetric accumulation, Fresnel iridescent_col, bio_col shift, mouse gravity well (factored into frustuleLocal), fog + soft bloom.
ADD (2 native ideas):
  1. Hexagonal areolae pore lattice — each octahedral valve face is flattened onto the plane orthogonal to (1,1,1) and tiled with a hex lattice; areolae pits are carved into the shell band (density follows Pore Density, depth pulses with bass) and leak cytoplasm light through the open pores.
  2. Frustule valve-thickness thin-film interference — silica n=1.43, optical path 2*n*d*cos(theta_t) evaluated at 650/530/450 nm; valve is thin in areolae and thick on ribs (range scaled by Iridescence Spread, treble nudges thickness), blended 65% into the existing Fresnel iridescence.
FLOOR FIXES: fake audio textureSampleLevel(dataTextureC) removed -> plasmaBuffer[0].xyz bass/mids/treble with controlled gains (u.config.z/w only used for aspect/bounds, not audio); exact clamped textureLoad(dataTextureC) mild afterglow; ACES tone map; semantic alpha (shell coverage/Fresnel/rib vs pore, cytoplasm density on miss, ripple rings); same RGBA to writeTexture + dataTextureA; depth written; click ripples added (silica-deposition rings, loop to min(u32(u.config.y),50u)); header replaced. No extraBuffer use. JSON: original "parameters" kept byte-exact; params + updatedParams (same values) + features added.
FORBID: generic noise/bloom overlays, dataTextureB writes, extraBuffer outside 133..138, changing slider defaults/ranges.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (AUDIT PASS) / sliders x (pores+areolae), y (pulse/time), z (iridescence+film thickness), w (bio shift + ripple tint) live


---

SHADER: gen-luminescent-quantum-void-anglerfish
IDENTITY: Raymarched biomechanical deep-space anglerfish (brass capsule body + tail, hinged hollow jaw with needle-teeth instances, cyan esca lure, magenta aether-particle swarm, translucent sin-wave fins) in a Beer's-law dark-matter void.
KEEP VERBATIM: rot/smin/hash33/sdSphere/sdBox/sdCapsule, body/tail/jaw/teeth/lure/particle/fin SDFs, mouse gaze rotation of body + camera, 100-step march, material palette, Beer's-law absorption.
ADD (2 native ideas):
  1. Esca bacterial pulse (escaBacterialPulse): symbiotic-bacteria colonies (cell hash over the esca bulb) flicker on individual phases; a quorum-sensing sync term pulls them into one breathing pulse, sync strength rises with bass; click shock flares the lure.
  2. Lateral-line photophores (lateralLinePhotophores): two rows of spaced photophore spots on the body flanks (body-space position carried out of map via new MapData.bp), lit by a head-to-tail travelling wave; treble sparkles, click ripples send a flash down the line.
FLOOR FIXES: removed fake audio u.config.y (lure bloom "audio") and fract(u.config.y) shockwave -> plasmaBuffer bass/mids/treble (clamped, gains 0.2-0.45) + real u.ripples loop (min(u32(config.y),50u)) driving swarm shockwave and screen rings; mouse held (zoom_config.w) gapes jaw wider; Reinhard+alpha 1.0 -> ACES + semantic alpha (hit coverage/diffuse/spec + photophore + volumetric glow, attenuated by void absorption); same RGBA to writeTexture + dataTextureA; real depth (1 - t/30) instead of 0; afterglow via clamped textureLoad(dataTextureC); no dataTextureB write; no extraBuffer use; dead unused noiseVec removed. Header standardized. JSON: updatedParams byte-exact, params array added, features [] -> audio-reactive/mouse-driven/upgraded-rgba.
FORBID: u.config.y/zw or zoom_config.x as audio; textureSampleLevel on dataTextureC; dataTextureB writes; extraBuffer outside 133..138; replacing the anglerfish SDFs.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (AUDIT PASS) / sliders x (jaw), y (lure, photophores, rings), z (void density), w (rust) live


---

SHADER: gen-luminescent-quantum-void-astral-turtle
IDENTITY: Raymarched crystalline space-turtle (fBm-displaced ellipsoid shell, head, flapping front flippers, glowing quantum core) drifting through an fBm volumetric nebula with cyan->pink plasma shell glow.
KEEP VERBATIM: hash12/hash33/rot2D/noise/fbm/sdSphere/sdEllipsoid/smin, mouse orbital distortion, shell/head/fin/core SDFs, plasma glow mapping, look-at camera, 100-step half-step march, nebula accumulation.
ADD (2 native ideas):
  1. Carapace scutes with growth-ring annuli (carapaceScutes): 2D Voronoi over the upper carapace (turtle-space via new MapResult.lp) gives keratin scute plates; each plate grows concentric annuli whose density follows Fractal Detail and whose growth wave is pushed by mids; seams glow warm with treble/click; per-plate cyan/magenta tint.
  2. Flipper wake vortex rings (flipperWake): each front flipper sheds a train of expanding, counter-rotating vortex tori drifting aft, accumulated as volumetric glow; bass strengthens shedding, mouse hold drives a harder/faster power-stroke (flipper beat + amplitude) and stronger wake, clicks flash it.
FLOOR FIXES: fake audio u.config.y (click count) -> plasmaBuffer (audio = bass*0.8+mids*0.2, clamped); core gain 2.0 -> 0.5, nebula audio gain halved; header cleaned (Uniforms-above-header + "COPY PASTE THIS HEADER" junk removed, standard header, Uniforms comment lists 4 sliders); added click ripples (u.ripples loop -> nebula shock rings + wake/seam flash) and mouse-held response (previously none); Reinhard+gamma+alpha 1.0 -> ACES + semantic alpha (surface coverage/fresnel + scute glow + volumetric glow); same RGBA to writeTexture + dataTextureA; depth now written; nebula persistence via clamped textureLoad(dataTextureC); no dataTextureB / extraBuffer use. JSON: updatedParams byte-exact, params array added, features [] -> audio-reactive/mouse-driven/upgraded-rgba.
FORBID: u.config.y as audio; textureSampleLevel on dataTextureC; dataTextureB writes; extraBuffer outside 133..138; replacing the turtle motif/SDFs.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (AUDIT PASS) / sliders x (shell fBm + annuli density), y (plasma glow, fresnel, scutes, wake), z (void density, rings), w (acoustic reactivity) live


---

SHADER: gen-luminescent-silica-diatom-swarm
IDENTITY: Fly-through of a domain-repeated swarm of spinning porous (Voronoi-punched) silica sphere-shells with glowing cyan cores, subsurface glow halo, mouse-held ray warp and warm hue shift, deep-ocean fog.
KEEP VERBATIM: rot, hash33, voronoi3D, map shell/holes/core construction and per-cell rotation, calcNormal, raymarch loop, shell Fresnel/spec shading, core warm-glow mouse shift, subsurface glow block, mouse warp, fog.
ADD (2 native ideas):
  1. Colony chain linkage — columns of cells (hash on cellIndex.xz) form Skeletonema-style chains: linking spines (new material 3) run along world-y in unrotated cell space with an interlocking collar where neighbours meet; spines thicken slightly with audio and get a mucilage rim glow (Bioluminescence, mids).
  2. Chloroplast plastid chlorophyll-a fluorescence — two parietal plastid plates (banded by |n.y|) tint the core fucoxanthin-gold and re-emit deep red ~685 nm proportional to excitation from the mouse light (hover proximity + held influence) and bass.
FLOOR FIXES: fake audio textureSampleLevel(dataTextureC) removed -> plasmaBuffer[0].xyz (Audio Reactivity scales bass/mids; treble on spec); Reinhard+gamma replaced by ACES; exact clamped textureLoad(dataTextureC) faint glide-trail feedback; semantic alpha (shell Fresnel coverage, plastid core, spine rim, glow density, fog-attenuated); same RGBA to writeTexture + dataTextureA; depth written; Glass Refraction now also refracts readTexture; click ripples added (flash wave, loop to min(u32(u.config.y),50u)); header replaced. No extraBuffer use. JSON: original "uniforms" kept byte-exact; params + updatedParams (same values) + features added.
FORBID: generic noise/bloom overlays, dataTextureB writes, extraBuffer outside 133..138, changing slider defaults/ranges.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (AUDIT PASS) / sliders x (density/scale), y (core, glow, spines, ripples), z (refraction), w (audio gain) live


---

SHADER: gen-luminous-cauldron
IDENTITY: Radiant alchemical cauldron: violet/amber convection swirl in a round pot, heat-shimmered caustics, rising SDF bubble froth, treble spark glitter.
KEEP VERBATIM: sat, hash21/hash22, noise, fbm, bass_env, acesToneMap, sdSphere, causticPattern, heatShimmer; bowl/swirl/convectionWaves, 3-layer bubble grid, sparks, base color stack, C feedback mix; slider mappings (Boil Rate, Convection, Foam, Radiance).
ADD (2 native ideas):
  1. Minnaert bubble-collapse capillary rings: per-surface-cell bubbles burst on staggered phases and radiate decaying rings with fine capillary ripple (collapseRing); bass lowers the burst threshold, Foam scales strength. Click ripples drop a large collapsing bubble ring at the click.
  2. Meniscus rim caustic at the pot lip: bright double band just inside the bowl edge (meniscus climb + focused caustic line), wobbling with convection, flickering via causticPattern, lifted by Radiance and treble.
FLOOR FIXES: extraBuffer[0] (out of range) bass envelope relocated to guarded extraBuffer[133]; textureSampleLevel(dataTextureC) -> clamped textureLoad; dataTextureA was storing data channels (waves/bubbles/sparks/caustics) -> now final display RGBA identical to writeTexture; alpha was 1.0 -> bowl coverage + froth + collapse + rim + glow; depth was 0 -> surface height; audio clamped 0..1 with controlled gains; added click ripples (min(config.y,50)); mouse-held (zoom_config.w) stirs extra swirl and boils faster; config.z/w only used for dims/aspect (no fake audio); no dataTextureB writes; JSON params array + features added.
FORBID: writing dataTextureB, extraBuffer outside 133..138, replacing the pot/bubble motif, generic bloom/palette overlays.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (AUDIT PASS) / sliders x,y,z,w live


---

SHADER: gen-luminous-fluid-chladni-resonator
IDENTITY: Bioluminescent liquid Chladni plate: curl-fluid warped multi-mode Chladni figures, Voronoi ridge veins, blackbody warm/cool OkLab glow on nodal lines.
KEEP VERBATIM: hash21, noise, fbm, curl2D, voronoiRidge, chladni_multi, blackbodyRGB, OkLab helpers, aces, ign, acesToneMap; n/m bass modulation, mouse damping, settle mix, warm/cool color build, alpha formula core; slider mappings (Mode N, Mode M, Fluidity, Glow Intensity).
ADD (2 native ideas):
  1. Sand accumulation on nodal lines (sandGrains): 180-cell grain lattice; grains are packed where plate displacement vanishes, sparse airborne grains flicker over antinodes (treble agitation); warm sand tint scaled by Glow.
  2. Faraday subharmonic ripples (faradayRipples): square standing-wave lattice at half the drive frequency, gated by a bass threshold (smoothstep 0.35..0.8) and confined to antinodes; feeds back into c_val and adds a cool shimmer.
FLOOR FIXES: textureSampleLevel(dataTextureC).r -> clamped textureLoad, and prior field now derived from A alpha (nodal-ness) so feedback is consistent with A holding display RGBA; audio clamped 0..1, bass intensity gain reduced 1.0 -> 0.5; added click ripples (circular flexural waves, min(config.y,50)); mouse held widens the finger damping zone; depth now plate displacement (was passthrough of input depth); pow guarded with max(0); config.z/w only resolution/aspect (no fake audio); no extraBuffer use; no dataTextureB writes; JSON params array + features added, workgroup_size aligned to WGSL 16,16,1.
FORBID: writing dataTextureB, extraBuffer use, replacing Chladni motif, generic noise overlays.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (AUDIT PASS) / sliders x,y,z,w live


---

SHADER: gen-magnetic-dipole-field
IDENTITY: Analytic 2D magnetic dipole (m along +y) with stream-line field bands, charged particles riding dipole shells r = L·sin²ψ, orbiting ghost dipole, field-magnitude contours, velocity-aligned motion-blur feedback along B, mouse-held repositions the dipole.
KEEP VERBATIM: dipoleB, field_palette, valueNoise, sampleField field-line/contour/colour logic, ghost dipole, analytic chromatic split, storm shimmer, B-aligned textureLoad(dataTextureC) motion-blur trail, param mappings (Field Strength / Particle Speed / Line Density / Color Shift).
ADD (2 native ideas):
  1. Lorentz gyro-helix + magnetic-mirror bounce (gyroMirrorParticle): particles bounce harmonically between conjugate mirror points set by a per-particle equatorial pitch angle; projected gyration wiggles perpendicular to B with gyroradius ∝ v⊥/|B| (tight near poles) and cyclotron freq ∝ log|B|, ions/electrons gyrate oppositely. Pitch < loss-cone fraction (bass + substorm widen it) → particle precipitates down to the footpoint and fades. Particle parameterisation corrected so ψ is measured from the moment axis, i.e. particles actually ride the dipoleB field.
  2. Auroral oval at field-line footpoints (auroralOval): dark planet body (R=0.045) at the dipole centre; curtains glow on pixels whose shell L = r/sin²ψ matches L_aur just above the limb — 557.7 nm green base, 630 nm red tops, ray structure from coherent noise. Flux ∝ loss-cone fraction (+treble, ×1.35 mouse held); Field Strength moves the oval poleward (bigger magnetosphere). Click ripples = substorms: loss cone opens, oval brightens and shifts equatorward, a dipolarization front ring sweeps out from the click.
FLOOR FIXES: merged two stacked legacy headers into one standard header; removed out-of-range extraBuffer[6,7,8,11,12,13] fake-FFT reads entirely (fftLo → mids-driven ionDrive, fftHi → treble) — no extraBuffer access remains; plasmaBuffer audio clamped 0..1; added click ripples (previously none) looped to min(u32(u.config.y),50u); mouse dipole mapping fixed to the same aspect-correct centred space as uv; A now receives the same ACES display RGBA as writeTexture (was HDR pre-tonemap); alpha includes aurora/front energy; depth includes planet body. u.config.z/w only used as resolution. JSON: params array added, features + mouse-driven, upgraded-rgba; updatedParams unchanged.
FORBID: extraBuffer indices outside 133..138, dataTextureB writes, textureSample on dataTextureC, fake audio from config.y/zw/zoom_config.x, replacing the dipole motif with a generic aurora overlay.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok (naga OK, bindgroup compatible, 0 extraBuffer violations) / extraBuffer audit PASS (no extraBuffer use) / sliders x (moment, particle count, oval L), y (speed, drift, blur), z (line density), w (hue) live


---

SHADER: gen-magnetic-ferrofluid-sculpture
IDENTITY: Raymarched liquid-metal sculpture: noise-rippled sphere with 6 orbiting cone spikes, fine spherical-harmonic spikes, mouse magnetic bulge, orbiting droplet, 3-light chrome + thin-film iridescence.
KEEP VERBATIM: ferrofluid() sphere/noise/cone spike loop/fine spikes/mouse bulge/orbiting droplet; iridescent(); lighting stack; depth fog; temporal persistence.
ADD (2 native ideas):
  1. Taylor-cone droplet pinch-off — on bass (eject = sat((bass-0.3)*2.2)) each spike tip ejects a droplet along its spike axis on a per-spike phase; a capsule neck thins and snaps at cycle ~0.55 (Rayleigh-Plateau); Fluid Viscosity slows the cycle and fattens the neck.
  2. Field-induced dipole chain bridges — beaded chains (head-to-tail particle chains) bridging neighbouring spike tips in a ring, bowing outward along field lines, bead pattern crawling; strength from Magnetic Pull, boosted while mouse held and by bass. Off-bulk surfaces (chains/droplets) get a cyan field-line glint.
FLOOR FIXES: textureSampleLevel(dataTextureC) -> clamped exact textureLoad; out-of-range extraBuffer[0] bass envelope relocated to guarded extraBuffer[133]; hardcoded alpha 1.0 -> semantic (coverage faded by fog depth + pulse glow + prev.a); added click ripples (loop to min(u32(config.y),50): magnetic field pulse raises a travelling surface swell ring on the fluid + screen shell); mouse held now boosts magnetic pull + chains; plasmaBuffer clamped; dead AO constant replaced by march-step AO; header/Uniforms comments per contract; u.config.z/w only resolution (no fake audio). JSON: added params array + features (was empty); updatedParams untouched.
FORBID: dataTextureB writes; extraBuffer outside 133..138; textureSampleLevel on dataTextureC; generic overlays; removing cone spikes.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer audit PASS / sliders x (spike count/noise freq), y (viscosity: spike width, pinch speed/neck), z (iridescence), w (mouse pull + chain strength) live


---

SHADER: gen-magnetic-ferrofluid
IDENTITY: Raymarched dark-metal ferrofluid sphere with sin-product spikes, orbiting merge droplet, sprung orbit camera, iridescent fresnel, click magnetic shells, temporal polish.
KEEP VERBATIM: map() base sphere + sin-product spike displacement + oscillation + orbiting droplet smin; calcNormal; sprung mouse camera (extraBuffer[133..138] state); lighting/iridescence/env reflection; click-shell ripple loop; vignette; dataTextureC temporal mix.
ADD (2 native ideas):
  1. Rosensweig hexagonal spike lattice — three plane waves 120 deg apart (triplanar over the mass), sharpened into cusps; appears only above critical field Hc=0.22 (H = Magnetic Strength * (1 + bass*0.45)) with supercritical sqrt(H-Hc) amplitude; spacing set by capillary wavenumber kc from Fluid Density, tightening slightly with field excess. Peak tips get field-aligned glint (treble).
  2. Labyrinthine fingering instability — while mouse held the field tips tangential: the hex lattice gives way to meandering, branching stripe domains (domain-warped cos stripes at the critical wavelength, animated by Oscillation Speed); domain walls glow magenta.
FLOOR FIXES: header replaced with contract format; extraBuffer[133..138] READS now guarded by arrayLength > 138 (writes already guarded, state kept); plasmaBuffer bass/mids/treble clamped 0..1 and reused (no raw plasmaBuffer[0].y/z inline); no fake audio found (u.config.y only ripple count, z/w only resolution); mouse held (zoom_config.w) now honored (tangential field); alpha = hit coverage + peak/wall density + click shell; march step 0.75 -> 0.62 for added relief Lipschitz; Uniforms comment lists slider names. JSON: added params array + audio-reactive/mouse-driven/upgraded-rgba features (updatedParams untouched).
FORBID: dataTextureB writes; extraBuffer outside 133..138; generic noise/bloom overlays; replacing the sin-product spikes.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer audit PASS / sliders x (spikes + Rosensweig onset), y (radius, kc spacing), z (speed, labyrinth drift), w (iridescence) live


---

SHADER: gen-magnetic-field-lines
IDENTITY: 1–5 orbiting, rotating dipoles drawn as analytic sin²ψ shell families (N blue / S red), 18 charged-particle streaks advected along B, mouse as auxiliary dipole source (full strength when held), click CME wavefronts, field-advected auroral history.
KEEP VERBATIM: dipoleField, particleOnFieldLine, fieldColor, shell-family line rendering, particle streak loop, mouse halo/source, CME ripple loop, field-advected dataTextureC history, vignette, param mappings (Field Strength / Particle Speed / Number of Dipoles / Trail Length).
ADD (2 native ideas):
  1. Iron-filing line-integral convolution (ironFilingLIC): smooth iron-dust noise convolved with a tent kernel along the true total-B streamline (6 RK1 steps each way, re-evaluating the full dipole+mouse field), so grains chain into filaments; chain length ∝ log|B| (long combed chains near poles, loose grains in weak gaps) and scaled by Trail Length. Steel-grey tint, mids shimmer.
  2. Magnetic reconnection X-point flash: finite-difference Jacobian of total B, Newton step δ = −J⁻¹B to the nearest null; det J < 0 (X-type saddle) and away from source cores → hot magenta-white core at the null plus cyan light along the two separatrices (eigen-directions of the symmetric Jacobian). Reconnection-rate pulse from Particle Speed + treble; amplitude grows with mouse held (mouse source vs dipoles) and bass.
FLOOR FIXES: header replaced with standard format; uniforms comment lists sliders; plasmaBuffer bass/mids/treble now clamped 0..1 (u.config.y confirmed used only as ripple loop bound — legit, no fake audio found); A now receives the same ACES display RGBA as writeTexture (was HDR pre-tonemap); alpha/depth include filings + X-flash energy; exact textureLoad on C already present. JSON: params array added, features + upgraded-rgba; updatedParams unchanged.
FORBID: extraBuffer indices outside 133..138, dataTextureB writes, textureSample on dataTextureC, fake audio from config.y/zw/zoom_config.x, generic noise/bloom overlays not derived from B.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok (naga OK, bindgroup compatible, 0 extraBuffer violations) / extraBuffer audit PASS (no extraBuffer use) / sliders x (field strength, LIC chain + null geometry), y (speed, reconnection rate), z (dipole count), w (trail + chain length) live


---

