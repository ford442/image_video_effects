# Neon / neural generative ten — Idea Cards (2026-09-14)

Contract: CONTRACT.md. Two native ideas each; identities kept; no new springs. Naga 10/10, precommit gate 10/10, extraBuffer audit PASS, dead-slider audit PASS, updatedParams/params unchanged 10/10. Real-GPU QA external.

SHADER: gen-koch-snowflake-storm
IDENTITY: 2-5 Koch-style polar snowflakes orbit through fbm-warped turbulence on a pale ice sky. Each has a steel-blue crystal body, an icy edge glow, and chromatic-dispersion tinting past the edge. The flakes drift toward the mouse, and bass speeds the orbit and the turbulence.
KEEP VERBATIM: hash21/noise2/fbm, snowflake_sdf (sinusoidal 3^n lobe recursion), turbulence warp, orbit law (angle/dist/size), mouse offset, inside/glow/edge colouring, CA tint, depth = 1 - edge*0.8, all four param mappings.
ADD (2 native ideas):
  1. Koch self-similar offspring: each flake buds three 1/3-scale copies of itself at its primary lobes (sin(3a)=1), which is the Koch generator applied at flake scale. They use recursion n-1 and counter-rotate. They fade in as Recursion Depth passes its first step, and bass pushes them outward.
  2. 22-degree ice halo: a hexagonal-prism minimum-deviation ring around every flake at 2.4x its radius. Red sits at the sharp inner edge, green in the middle, and blue in a diffuse outer skirt. Strength follows Chromatic Dispersion and treble.
FLOOR FIXES: header replaced (the old header claimed upgraded-rgba but was unverified); double ACES (aces_tonemap then acesToneMap) -> single aces pass; alpha was density*turbStrength*2.5 -> ice coverage (body + edge glow + halo + gust); mids/treble added (only bass was read) and all clamped 0..1; mids now drives flake flutter/rocking, treble drives halo + edge glow; added click ripples as gust fronts that blow the storm outward, spin flakes and flash; a held mouse strengthens flake attraction (0.4 -> 0.75); depth w written as 0; uniforms comment lists sliders. No extraBuffer, dataTextureB, or dataTextureC use. JSON: added `params` array (turbulence, recursionDepth, snowflakeCount, chromaticDispersion) matching updatedParams, features [] -> audio-reactive, mouse-driven, upgraded-rgba.
FORBID: extraBuffer use, dataTextureB writes, fake audio, new springs, replacing snowflake_sdf with a generic fractal/noise.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer audit PASS / sliders x (turbulence warp), y (recursion + offspring), z (flake count), w (CA tint + halo strength) live


---

SHADER: gen-langton-ant
IDENTITY: Langton's Ant: three turmites on a toroidal 128-column grid, flipping cells and leaving a heat trail. The heat-map palette runs blue > cyan > yellow > red > white. Bass speeds up trail build-up. Holding the mouse moves ant 0, and depth zooms the view.
KEEP VERBATIM: heatColor palette, dirVec, hashf seeding (Seed Pattern), multi-pass state packing (cell state in A, ant trackers at (k*cellSize,0)), flip-behind-ant rule, heat decay (Trail Decay), mouse-held ant relocation, depth zoom, chromatic split, applyGenerativePrimaryControls mappings.
ADD (2 native ideas):
  1. Colony territories: A.b (previously a write-only isAntHere) now stores the id of the ant that last flipped each cell. Cells take that colony's hue (amber/cyan/magenta), and borders between colonies glow as seams (mids gain), found from neighbour-cell loads of C.
  2. Oriented ant glyphs: each ant is drawn in its cell as head, thorax, abdomen and two antennae along its heading. Antenna length and glow follow treble.
FLOOR FIXES: Header replaced and uniforms comment lists the sliders. ACES now runs after the slider shaping; before, pow() ran after ACES and could push values past 1. Audio is clamped, and mids/treble were added. Turn rule fixed: ants used to turn by the state of their tracker pixel (really their encoded x position), and now turn by the colour of the cell they stand on (inverse depth mapping, row 0 skipped). The vertical wrap now uses the visible grid height, so ants no longer wander off-screen. Tracker alpha 1.0 means moved and 0.75 means idle, so a paused ant does not flip the same cell twice. Evolution Speed was only a flicker and now also gates stepping: the default 0.2 still steps every frame, lower values slow the ants, and bass kicks them. Added click ripples: a young ripple paints a patch of black cells (idempotent) plus a ring glow. Alpha no longer goes to zero when depth is 0. Added a bounds check and a cellSize>=1 guard. Every C read is an exact textureLoad. No extraBuffer, no B writes, no fake audio found.
FORBID: extraBuffer use, dataTextureB writes, fake audio, overwriting A with display colour (destroys CA), generic noise overlays.
A PACKING: raw CA state (flip state, heat, colony id/4, 1.0); trackers at (k*cellSize,0) = (x/128, y/128, dir/4, 1.0 moved | 0.75 idle); ACES display RGBA on writeTexture only
VERIFY: naga ok / gate ok / extraBuffer AUDIT PASS / sliders x (flip boost + intensity), y (step gate + pulse), z (seed + contrast), w (decay + mouse influence) live


---

SHADER: gen-lenia-2
IDENTITY: 4-species Lenia ecosystem: 4 kernel types with 8-sample radial convolution, bell growth for each species, a 4x4 predator-prey matrix, and cross-species DNA mixing. Species masses are colour-mapped from DNA traits. Holding the mouse injects food, and clicks seed species in rotation.
KEEP VERBATIM: bell, kernel_gaussian, kernel_mexican_hat, kernel_sample_8, species_interaction, species_to_color, seeding, update rule (0.94 decay + growth*speed*0.035), crossMix gbra swap, mouse food injection, ripple inoculation, chromatic dispersion over state, slider mappings.
ADD (2 native ideas):
  1. Growth-field membranes: the zero crossing of each species' growth mapping G(U) is drawn as a glowing cell wall where that species is present. Walls are brighter on the advancing front (dM/dt>0). Wall width follows Cross-Species Mix and glow follows mids.
  2. Mass-field gel relief: the total-mass gradient from 4 exact C loads (offset scales with Kernel Radius) gives each creature a normal. Creatures get diffuse shading lit from the mouse direction, a specular glint driven by treble, and Beer-Lambert absorption through thick bodies by DNA colour.
FLOOR FIXES: Header replaced and uniforms comment lists the sliders. ACES added; writeTexture was raw linear before. Audio is clamped. The pulse used to modulate frequency (sin(time*12*(1+bass*0.5)), which caused phase jumps). It now keeps a fixed frequency with bass scaling the amplitude, and bass=0 gives the same result as before. Bass nudges the growth centre mu by +0.03, and mids/treble are now used (they were unused before). Alpha is density plus membrane coverage. No fake audio found: config.y is used only for the ripple count and config.zw only for resolution. No extraBuffer, no B writes, and C was already an exact textureLoad.
FORBID: extraBuffer use, dataTextureB writes, writing display colour into A (destroys species state), changing kernel/growth core.
A PACKING: raw sim state (species R mass, G mass, B mass, A mass); ACES display RGBA on writeTexture only
VERIFY: naga ok / gate ok / extraBuffer AUDIT PASS / sliders x (growth mu), y (kernel radius + relief offset), z (evolution speed), w (cross mix + membrane width) live


---

SHADER: gen-neon-snowfall
IDENTITY: three parallax layers of chromatic neon snow falling through a dark sky, treble twinkle, per-flake motion-blur streaks, temporal streak persistence.
KEEP VERBATIM: 3-layer depth parallax loop, hash/palette flake colouring, bass_env smoothing, 6-step motion-blur trail, twinkle, temporal persistence mix, slider mappings (density 20..180, fall 0.08..2, chroma 0.2..2, streak 0..1).
ADD (2 native ideas):
  1. Nakaya crystal habit per falling column: hexagonal plates (with rib lines) <-> stellar dendrites (6 arms + 60-degree side branches tapering to the tip); mids = supersaturation pushes the habit toward dendrites; silhouette fades in once a cell is >= ~4-12 px, gaussian core otherwise.
  2. Habit-dependent fall dynamics: plates sink faster (terminal velocity 1.3x) and flutter wide/fast with a specular basal-face glint as the swing passes level; dendrites drift slowly (0.72x) with small flutter; flutter lateral velocity feeds the streak direction. Click ripples = radial wind gusts (near layer pushed most), mouse-held = eddy around the cursor.
FLOOR FIXES: extraBuffer[0] bass envelope relocated to guarded extraBuffer[133]; textureSampleLevel(dataTextureC) -> clamped exact textureLoad; A was (flake,trail,0,1) but read back as colour -> A now final ACES display RGBA, same as writeTexture; alpha was hardcoded 1.0 -> snow coverage (flakes+streaks+glints+luma); depth was 0 -> near-layer-weighted coverage; plasmaBuffer audio clamped 0..1; click ripples + mouse-held added (were missing); header/uniform comments; JSON features [] -> required three + params array.
FORBID: extraBuffer outside 133..138, dataTextureB writes, reading u.config.y/zw as audio, replacing flakes with generic noise.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x,y,z,w live


---

SHADER: gen-neon-stellated-octahedron
IDENTITY: neon star tetrahedron (stellated octahedron) — two interpenetrating tetrahedra, rainbow edges, facet-plane glow, intersection ridge, vertex spike glow, 6-fold kaleidoscope, mouse yaw/pitch.
KEEP VERBATIM: stellatedOctaSDF (edges/faces/ridge), neon(), rotX/rotY, kaleidoscope fold, edge/facet/ridge/spike colour terms, slider mappings, 4% feedback from C.
ADD (2 native ideas):
  1. Tomographic section through the true solid compound (each tetra = intersection of its 4 face half-spaces): slice plane sweeps along the view axis (tip triangles -> hexagram), the shared regular-octahedron core (max(tA,tB)) is lit apart from the 8 stellation spikes, tetra A warm / tetra B cool with thickness shading; click ripples dent the slice plane locally, mouse-held locks the slice at the central hexagram.
  2. Kepler cube hull: the 8 star tips are the vertices of a cube — its 12-edge frame is drawn faintly, with corner beacons coloured by bipartite parity (sign of x*y*z: tetra A tip vs tetra B tip), treble-pulsed.
FLOOR FIXES: slice plane was fixed at z=1.5 outside the star (vertex radius <= 1.56), so edge/ridge terms were effectively dead -> sweeping slice makes them visible; dataTextureA held pre-ACES HDR -> now the same final ACES RGBA as writeTexture; C load coords clamped; plasmaBuffer audio clamped 0..1; click ripples + mouse-held added (were missing); header + uniform slider comments. JSON unchanged (features/params already compliant; snake_case param ids kept).
FORBID: extraBuffer use, dataTextureB writes, renaming param ids, replacing the polyhedron motif.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x,y,z,w live


---

SHADER: gen-neon-tropical-paradise
IDENTITY: Psychedelic neon lagoon at sunset: tropical-sunset sky gradient, five electric aurora bands, twinkling stars, fbm neon sand dune, three swaying palms, three neon flowers, bioluminescent water with wavelength-dependent (R 0.3 / G 0.05 / B 0.02) light attenuation, coral fluorescence on treble, bass wave surge, floating particles, temporal max-feedback trails, saturation boost and red/blue chromatic offset.
KEEP VERBATIM: noise/fbm/palettes, auroraBand, palmTrunk/palmFrond/palmTree, neonFlower, twinkleStar, bioWater attenuation/depth colours/waves/sparkles/coral glow/reflection band, particles, dataTextureC feedback, saturation + CA, slider mappings (Intensity / Speed / Scale / Color Shift).
ADD (2 native ideas):
  1. Underwater caustic net from wave-lens focusing: four dispersive (w ~ sqrt(g|k|)) surface waves give an analytic Hessian; caustic brightness = 1/|det(I + D*Hessian)| with focusing depth D growing below the waterline. Filaments are filtered by the existing attenuation vector, sharpen with bass (wave amplitude), and scale with Scale (caustic frequency) and Intensity.
  2. Noctiluca dinoflagellate mechanical-stress flashes: a per-cell threshold grid of 475nm sparks fires where shear stress exceeds each cell's threshold. Stress comes from click-ripple fronts (new ripple loop over the water plane with foreshortening), the held-mouse water ripple, and breaking surf where the wave slope plus bass surge is steep. Flash gain follows Intensity, treble adds flicker, and ripple fronts also add a cyan ring glint.
FLOOR FIXES: legacy double header replaced; uniforms comment lists sliders; mouse was u.zoom_config.yz / res (collapsed to ~0, so the mouse water ripple was dead) and is now uv mapped to aspect space; audio clamped 0..1; click ripples added (loop to min(config.y,50)); alpha was length(color) (luma-like) and is now scene coverage (sand/water/palms/flowers) + aurora glow + bio emission; depth was hardcoded 0 and is now a scene layer depth; writeTexture/A write the same RGBA. Already OK: single ACES, exact textureLoad(dataTextureC), no extraBuffer, no dataTextureB write, no fake audio. JSON: features + camelCase params added; updatedParams untouched.
FORBID: extraBuffer use, dataTextureB writes, fake audio, new springs, replacing the palm/aurora/lagoon motif with generic noise or bloom.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer audit PASS / sliders x (aurora, particles, bio glow, caustics, dino flash), y (animation rate), z (tree scale, water depth scale, caustic + cell frequency), w (aurora/bio/particle hue) live


---

SHADER: gen-neural-bioluminescence-matrix
IDENTITY: Raymarched infinite lattice of fbm-warped neuron capsules (x/y/z axons smooth-min'd at nodes) flown through on +z. A global pulse wave drives proximity glow in cyan-magenta, with mouse magnetic repulsion, click-held mutation seed, bass/mid/treble low-pass envelopes, chromatic offset, and dataTextureC feedback trails.
KEEP VERBATIM: smin/hash33/noise/fbm/sdCapsule/rot/spring_damper, map (repulsion, fbm warp, lattice capsules), calcNormal, camera + rotation, 80-step march with pulseWave, diffuse/AO/SSS shading, glowCol, fog, CA, feedback mix (0.2 + bass*0.1), slider mappings.
ADD (2 native ideas):
  1. Saltatory action potentials: each axon (dominant local axis per lattice cell) is myelinated with 4 nodes of Ranvier. A per-neuron spike front (rate from Pulse Speed, seeded by the click mutation seed) lights only the node it just reached. The node flashes with a sharp depolarization rise and fast decay, then a refractory hyperpolarized undershoot that dims the ambient pulse, so the spike visibly hops node to node.
  2. Aequorin -> GFP energy transfer: Ca2+-triggered photoprotein flashes emit 469nm blue at firing nodes and along new click calcium waves (ripple rings in screen space that also lens the view). In the feedback trail, lingering light is re-emitted as 509nm GFP green (transfer rate nudged by mids), so blue flashes decay into green afterglow.
FLOOR FIXES: header replaced; ACES added (none before), and feedback now runs in display space on the exact textureLoad of C; alpha was luma-based and is now tissue hit coverage + glow density + flash, feedback-smoothed. extraBuffer[0..6] (reserved/FFT zone; [5],[6] were written from every pixel) relocated to guarded 133..138, written only at pixel (0,0): 133-135 audio envelopes, 136-137 prev mouse, 138 = clickCount*2 + held (count mod 100, which keeps fract(n*0.13) exact). Mouse was zoom_config.y / config.z (resolution misuse) and is now uv. Audio clamped 0..1; pulse audio gain reduced from 1+2*a to 1+0.5*a. Node Density is guarded against /0. Click ripples added (min(config.y,50)). Depth was a readDepthTexture passthrough and is now raymarch distance. Unused velocity springs unchanged (no new springs). JSON: features + camelCase params added; updatedParams untouched.
FORBID: extraBuffer outside 133..138, dataTextureB writes, fake audio, new springs, replacing the capsule lattice / raymarch with 2D noise.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer audit PASS / sliders x (lattice spacing + spike cell size), y (pulse wave + spike hop rate), z (audio displacement/pulse + CA), w (glow, spike glow, calcium flash) live


---

SHADER: gen-neural-dust
IDENTITY: Drifting luminous dust field. Domain-warped FBM carries a jittered particle grid with gaussian mote glow and cosine-palette colour, and each cell listens to its own FFT band. Depth-gradient parallax pushes motes around silhouettes, holding the mouse adds gravity/glow, and comet trails come from frame feedback.
KEEP VERBATIM: hash12/valueNoise/fbm2/palette/glow, cellBandEnergy (now per-cell lane over plasmaBuffer[0].xyz), depth-gradient parallax, domain warp, grid/offset/drift law, mouse gravity + glow, vignette, trail decay/inject/1.2 clamp, Hue Shift trail tint, all four param mappings.
ADD (2 native ideas):
  1. Leaky integrate-and-fire motes: each mote charges at its own rate. Its FFT band, bass, and a held mouse raise the input current. On firing it gives a sharp cyan-white action-potential flash (the glow radius widens), then a refractory bioluminescent afterglow in the palette colour. Click ripples act as stimulus electrodes: the expanding front force-fires every mote it crosses and leaves a faint electrode ring.
  2. Axon filaments: hash-gated links (Dust Density sets how many) join each mote to its +x/+y neighbour. A spike from the source mote travels along the fibre at a finite conduction velocity (treble speeds it up). Fibre brightness follows mids, and fibre width follows Glow Radius.
FLOOR FIXES: header replaced; dataTextureC textureSampleLevel -> clamped exact textureLoad; A now holds the ACES display RGBA (same as writeTexture) and the trail feedback decodes it with an analytic inverse ACES and un-tint, so the trail stays linear with no fixed-point runaway; hardcoded alpha 1.0 -> dust density (mote cores + axons + trail luma); audio clamped 0..1; coordinator removed plasmaBuffer[1..8] "FFT bin" reads (binding 12 holds plasma balls, not bins) -> per-cell bass/mids/treble lane; added click ripples (loop to min(config.y,50)); uniforms comment lists sliders. No fake audio, extraBuffer, or dataTextureB use found. JSON: added "upgraded-rgba" to features (params/updatedParams untouched).
FORBID: extraBuffer use, dataTextureB writes, fake audio, new springs, replacing the FBM dust motif, sampling C with a filter.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer audit PASS / sliders x (grid density, parallax, axon link count), y (flow, drift, trail decay), z (glow radius, injection, axon width), w (palette phase, trail tint) live


---

SHADER: gen-kimi-crystal
IDENTITY: Hexagonal-grid ice crystals growing/rotating with physical light transmission (IOR 1.31 Fresnel-Schlick, Beer absorption by purity/thickness), gold spectral-dispersion Fresnel edges, vertex sparkles.
KEEP VERBATIM: odd-row hex offset grid, sdHexagon, fresnelSchlick, hueLimit, transmission block (crystalMask/F0/pathLength/absorption/transmission), spectral edge glow with IOR_ICE_R/G/B, slider mappings x..w.
ADD (2 native ideas):
  1. Nakaya habit transition: as growthPhase advances (and treble = supersaturation rises) the hex plate core shrinks and six-fold stellar dendrite arms with 60-degree sidebranches (parallel to neighbour arms) grow out (sdDendrite, wedge-folded).
  2. 22-degree ice halo + parhelia around the mouse "sun": ring radius from minimum deviation through a 60-degree ice prism D = 2 asin(n sin 30deg) - 60deg per channel (1.31/1.32/1.33 -> red inner edge, blue skirt), darker sky inside, sun dogs left/right; mouse-held and purity strengthen, bass lifts.
FLOOR FIXES: fake audio removed (plasmaBuffer[1..8] per-row "FFT" -> plasmaBuffer[0].y mids row shimmer); bass/mids/treble clamped; single ACES on full display (was ACES on crystal then un-tonemapped input mix); semantic alpha (ice opacity via transmission + edge/halo/frost glow) written identically to writeTexture and dataTextureA (A previously held a different alpha); added click-ripple nucleation fronts (cells swept snap to full growth + frost ring flash); header/uniform comments; no C/B/extraBuffer use.
FORBID: replacing hex grid motif, generic bloom/noise overlays, writing dataTextureB, extraBuffer use.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x,y,z,w live (w also sets dendrite arm width)


---

SHADER: gen-kimi-nebula
IDENTITY: Purple/blue fbm gas-cloud nebula with domain warp, mids/treble strata drift, twinkling stars with gas-tinted halos, mouse stellar wind swirl, bass chromatic offset.
KEEP VERBATIM: hash3/noise3/fbm3, NebulaControls slider mapping (Intensity gain, Speed timescale, Scale frequency, Detail star cutoff), wind swirl + warp, 3-layer density, 5-colour palette ramp, star/halo logic, bass chromatic offset.
ADD (2 native ideas):
  1. Stromgren-sphere ionization around the mouse O-star: R_s ~ 0.5 Q^(1/3) (n/0.5)^(-2/3) per local density, n^2 recombination glow — [OIII] teal core, H-alpha red sphere, [SII] at the ionization front; mouse-held and bass raise Q.
  2. Dust lanes with 1/lambda extinction (tau * (0.55,0.8,1.25)) dimming/reddening gas, stars and the input layer behind them, plus photoevaporated bright rims on globule faces pointing toward the star (dust gradient along star direction).
FLOOR FIXES: added bounds guard; ordered 13-binding block; plasmaBuffer[0] bands clamped; hardcoded alpha max(input.a,0.85) -> semantic alpha (gas density + emission measure + dust column + stars + shell); dataTextureA now gets the same RGBA as writeTexture (was alpha=density); depth now gas/dust column mixed over input depth (was passthrough); added click response: Sedov-Taylor (R ~ t^0.4) supernova-remnant filament shells that compress gas; no C/B/extraBuffer use.
FORBID: replacing fbm cloud motif, generic bloom/IQ palettes, writing dataTextureB, extraBuffer use, changing slider ids/defaults.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x,y,z,w live (x also scales dust optical depth)


---

