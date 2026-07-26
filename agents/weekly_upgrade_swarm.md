# Weekly Shader Upgrade Swarm — Batch 1

> **Goal:** Upgrade WGSL shaders to fix undersized generative effects, replace naive RGB-only patterns with RGBA-aware blending, and add meaningful alpha, audio reactivity, and missing params.
> **Constraint:** Do NOT modify `Renderer.ts`, `types.ts`, or bind groups. Do NOT install new npm packages.

---

## Recently Completed (150 shaders)

These shaders have been edited, their JSONs updated where needed, and `generate_shader_lists.js` validated the changes.

### Batch 16 (8 shaders) — 2026-07-26 — GENERATIVE EDITION 7

8-agent generative swarm, next 8 smallest with empty `updatedParams` (144–200 lines). Theme unchanged. **Uniform-semantics audit:** recon initially flagged `config.y` as delta_time (stale `docs/BINDING_CONTRACT.md`); verified against `src/renderer/UniformBuffer.ts` + `webgpu/frame.ts` — `config = [time, rippleCount, resW, resH]`, so the `min(u32(u.config.y), 50u)` ripples guard used since Batch 12 is CORRECT (docs are stale, engine source is truth). Special wins: `gen-ethereal-cyber-chrono-nebula-phoenix` had **dead audio** (`audio = u.config.y` = ripple count — rewired to real bass/treble) on an `audio-reactive`-tagged shader with only 2 controls (updatedParams mirrors exactly those 2); `liquid_magnetic_ferro` had a **dead Viscosity slider** (wired to real temporal field smoothing via A→C feedback) + center-pixel NaN normalize hardened; `bio_lenia_continuous` had a stuck spawn gate (`config.y > 0` forever after first click — now gated on mouse-down) + gained a second competing species in the free A.g channel; `bioluminescent-bloom` had **double ACES** (second pass removed); `chrono-voronoi-mycelium` had ALL 4 sliders trapped in `applyGenerativePrimaryControls` boilerplate (evicted — sliders now drive ageMix/clock/decay/voronoi-scale, defaults reproduce legacy look); `cosmic-jellyfish` computed temporal trails and **never displayed them** (now displayed at 0.6 mix) + flat-0.0 depth clobber fixed; `spec-quaternion-julia` had unclamped background alpha (~100!) + mislabeled Detail slider (now real DE iteration count); `tornado-vortex` had dead `vRadial`/`vVertical` physics (now advects debris) with its exemplary tonemap stack byte-identical. All 8 gate green (bindgroup + workgroup, 0 warnings; naga unavailable in this VM — deferred to CI), JSON contracts preserved, lists/dupes clean (1312 unique definitions), Jest 50 suites/344 pass. Briefs: `swarm-tasks/kimi-generative-briefs-2026-07-26-b16/`; notes: `swarm-outputs/kimi-generative-2026-07-26-b16/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 159 | `gen-ethereal-cyber-chrono-nebula-phoenix` | 16 | 144→218 (+74) | **Dead audio fixed** (config.y→bass/treble); hue-clamp 2.0 + ACES; spring-damper halo [133..137]; click wing-flare rings; sdPhoenix/Clifford constants verbatim. |
| 160 | `liquid_magnetic_ferro` | 16 | 190→240 (+50) | **Dead Viscosity wired** (temporal field smoothing A→C); honest bass/treble audio; safeNormalize epsilon guards; depth clamp ≥0; Rosensweig + 1/r³ verbatim. |
| 161 | `bio_lenia_continuous` | 16 | 192→266 (+74) | **Spawn gate fixed** (mouse-down); mids audio seasons; second species in A.g with cross-feeding; click seed bombs; bell()/clamp/A.r layout verbatim. |
| 162 | `bioluminescent-bloom` | 16 | 194→259 (+65) | **Double ACES removed** + hue-clamp 1.2; per-tendril FFT bins; spring-damper nutrient [133..137]; GS constants + A packing verbatim. |
| 163 | `chrono-voronoi-mycelium` | 16 | 194→253 (+59) | **Boilerplate evicted** — sliders→ageMix/clock/decay/scale (defaults = legacy); duplicate C read + dead B store removed; per-cell FFT seed jitter; spore rings. |
| 164 | `cosmic-jellyfish` | 16 | 195→267 (+72) | **Dead trails displayed** (0.6 mix, decay 0.96, clamp 1.2); honest hit-distance depth; bass pulse/treble tentacles; IQ palette + ACES; map() SDF verbatim. |
| 165 | `spec-quaternion-julia` | 16 | 195→246 (+51) | **Detail slider real** (DE iters 8–16); bg alpha clamped ≤1; log(r) guarded; bass morph/mids c.w drift; orbit-trap IQ palette; quaternion math verbatim. |
| 166 | `tornado-vortex` | 16 | 200→256 (+56) | **Dead physics activated** (vRadial/vVertical advect debris); click satellite vortices; per-bin treble lightning; Rankine/blackbody/OkLab/tonemap byte-identical. |

### Batch 15 (8 shaders) — 2026-07-26 — GENERATIVE EDITION 6

8-agent generative swarm, next 8 smallest with empty `updatedParams` (131–190 lines). Theme unchanged: formalize `updatedParams` from EXISTING params (preset contract), kill fake/boilerplate mappings, +2–3 tailored techniques, +50–90 lines. Special wins: `gen-crystalline-nebula-weaver-void-spider` had **dead audio** (`u.ripples[0].x` masquerading as a plasmaBuffer proxy — rewired to real bass/treble) plus fake sin/dot fbm → real value-noise fbm and its non-standard `controls[]` JSON schema preserved while gaining `updatedParams`; `gen-holographic-fracture` had the `zoom_config.xy` mouse bug (x = Time!) — swizzle fixed, honest crack-proximity depth replaces flat 0.0 (`supportsDepth: true` now earned); `liquid_crystal_birefringence` had `audioPulse = zoom_config.w` (mouse-down mislabeled as audio) — now bass→Frederiks compression, mids→twist, treble→Schlieren sparkle + 8-bin Newton-ring fringes; `kimi_quantum_field` had a **double tonemap** (Reinhard+pow stacked under ACES — removed, mids restored) and dead `psi()` deleted; `kimi_fractal_dreams` had a latent NaN (`cdiv` near-zero denom — epsilon-guarded); `supernova-core` kept its premultiplied alpha compositor byte-identical while rays became spectrum-driven with Sedov-Taylor click rings; `lava-lamp-blobs` aspect-corrected its mouse and gained per-blob FFT voices with its sim-state dataTextureA packing untouched. All 8 gate green (bindgroup + workgroup, 0 warnings; naga binary unavailable in this VM — deferred to CI), JSON contracts preserved, lists/dupes clean (1312 unique definitions), Jest 50 suites/344 pass. Briefs: `swarm-tasks/kimi-generative-briefs-2026-07-26-b15/`; notes: `swarm-outputs/kimi-generative-2026-07-26-b15/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 151 | `gen-crystalline-nebula-weaver-void-spider` | 15 | 131→221 (+90) | **Dead audio fixed** (ripples[0].x→plasmaBuffer bass/treble); real 4-octave fbm + IQ palette; hue-clamp 2.0 + ACES; controls[] schema preserved. |
| 152 | `gen_psychedelic_spiral` | 15 | 142→199 (+57) | Per-bin FFT drives superformula n2/n3; click petal-burst rings; hsv2rgb→IQ cosine palette + hue-clamp 1.2; historyUV transform chain verbatim. |
| 153 | `liquid_crystal_birefringence` | 15 | 181→269 (+88) | **Fake audio fixed** (mouse-down→real FFT); 8-bin Newton-ring fringes; click voltage fronts; spring-damper defect core [133..134]; wavelength/Mueller math verbatim. |
| 154 | `gen-holographic-fracture` | 15 | 183→267 (+84) | **Mouse bug fixed** (xy→yz); honest crack depth write; click crack fronts; spring-damper origin [133..135]; per-crack FFT iridescence; chunk library verbatim. |
| 155 | `kimi_quantum_field` | 15 | 184→244 (+60) | **Double tonemap removed** (Reinhard out, ACES kept); spectrum interferometer (per-bin source amps); dead psi() deleted; mislabeled sliders made honest (defaults = legacy look). |
| 156 | `kimi_fractal_dreams` | 15 | 186→276 (+90) | **NaN guard** on cdiv denom (1e-4); spring-damper Julia morph [133..136]; click zoom pulses; orbit-trap IQ palette + per-bin treble filaments; Burning-Ship core verbatim. |
| 157 | `supernova-core` | 15 | 187→275 (+88) | Spectrum-driven rays (per-bin plasmaBuffer); click Sedov-Taylor rings (r~t^0.4); spring-damper companion star [133..134]; premultiplied alpha compositor byte-identical. |
| 158 | `lava-lamp-blobs` | 15 | 190→250 (+60) | Aspect-corrected spring-damper mouse [133..136]; per-blob FFT voices + mids shimmer + treble rim sparkle; click heat-injection blobs; sim-state dataTextureA packing verbatim. |

### Batch 14 (8 shaders) — 2026-07-22 — GENERATIVE EDITION 5

Interrupted Kimi swarm recovered and completed. All eight shader/definition pairs were present; seven had agent notes and `spore-galaxy` was the unrecorded cutoff. The recovery pass verified the saved-preset contract, completed the missing note, regenerated shader lists, and closed the tracker. Special wins: `gen-bioelectric-pulse` fixes inverted mouse semantics and adds persistent kick envelopes; `gen_grok4_life` replaces the hardcoded 2048 wrap with resolution-aware toroidal sampling; `spore-galaxy` fixes mask-as-color feedback by moving display color to dataTextureA and masks to dataTextureB; `gravito-phononic-accretion` turns Lensing Strength into real UV deflection. Target gate 8/8 green (naga + bindgroup, 0 warnings), JSON contracts preserved, lists/dupes clean (1310 unique definitions), Jest 49 suites/339 pass. Full-fleet Naga scan is 1314/1315; the sole failure is the unrelated, unmodified `gen-luminescent-aether-plasma-astro-axolotl.wgsl`. Briefs: `swarm-tasks/kimi-generative-briefs-2026-07-22-b14/`; notes: `swarm-outputs/kimi-generative-2026-07-22-b14/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 143 | `gen-bioelectric-pulse` | 14 | 180→245 (+65) | Correct mouse-down/UV semantics; honest dataTextureC reaction trails; kick mega-pulse envelope in safe extraBuffer state. |
| 144 | `gen_grok4_life` | 14 | 176→251 (+75) | Resolution-aware toroidal wrap; FFT ecosystem zones; age-based prey palette; extinction bloom monitor. |
| 145 | `gen_reaction_diffusion` | 14 | 179→234 (+55) | Treble micro-stimulus; click spiral dipoles; disentangled diffusion control; raw signed sim state preserved. |
| 146 | `gravito-phononic-accretion` | 14 | 179→248 (+69) | True gravitational UV lensing; diffusion-controlled persistence; treble relativistic jet envelope. |
| 147 | `neural-mandala` | 14 | 177→235 (+58) | Mouse spring re-centering; click shock rings; per-ring spectrum; complexity-driven sub-symmetry fold. |
| 148 | `phosphorescent-jellyfish` | 14 | 180→263 (+83) | Hue-preserving HDR clamp + ACES; per-jelly spectrum; nearest-jelly click propulsion dart. |
| 149 | `spore-galaxy` | 14 | 179→229 (+50) | Feedback semantics fixed (display→A, masks→B); per-arm FFT voices; ripple-driven spore bursts. |
| 150 | `topological-acoustic-knots` | 14 | 180→247 (+67) | Honest defect-density quench; annihilation cascades/census pulse; mids-driven persistent polarizer. |

### Batch 13 (8 shaders) — 2026-07-22 — GENERATIVE EDITION 4

8-agent generative swarm, next 8 smallest with empty `updatedParams` (171–175 lines). Theme unchanged: formalize `updatedParams` from EXISTING params (preset contract), kill boilerplate mappings, +2–3 tailored techniques, +50–90 lines. Special wins: `retro_phosphor_dream` had a **latent bug** (`audioPulse` bound to MouseDown, plasmaBuffer never read — rewired to bass); `gen_kimi_nebula` + `gen_hyper_warp` had placeholder param1–4 + `applyGenerativePrimaryControls` boilerplate (sliders now drive real constants, defaults reproduce legacy look); `gen_hyper_warp` feedback (×1.1 sharpen @ 0.95 mix) stabilized with hard 1.2 pre-tint clamp; `gen-neural-dust` mouse coords fixed to engine convention (`zoom_config.yz`). Sim-state feedback layouts (coral-growth envelope, crystalline-fracture stress) preserved verbatim. All 8 gate green (naga + bindgroup, 0 warnings), JSON contracts preserved, lists/dupes clean (1310 defs), Jest 49 suites/339 pass. Briefs: `swarm-tasks/kimi-generative-briefs-2026-07-22-b13/`; notes: `swarm-outputs/kimi-generative-2026-07-22-b13/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 135 | `gen-neural-dust` | 13 | 171→224 (+53) | Comet-trail feedback (clamp 1.2), per-cell plasmaBuffer[1..8] band energy, depth parallax; mouse coords fixed to zoom_config.yz. |
| 136 | `gen_kimi_nebula` | 13 | 172→227 (+55) | Boilerplate evicted — sliders→density/time-multiplier/noise-scale/star-cutoff (defaults = legacy); mids/treble layer drift; extra fbm3 warp. |
| 137 | `gen_hyper_warp` | 13 | 173→223 (+50) | stabilizeHistory() hard 1.2 clamp + soft-knee, flow-advected feedback, boilerplate evicted (warp amp/time/palette/feedback-mix). |
| 138 | `supernova-remnant` | 13 | 174→232 (+58) | Blackbody age ramp (A-alpha age accumulator), click detonation rings via ripples[], inertial bass kicks; chromatic feedback untouched. |
| 139 | `coral-growth` | 13 | 175→241 (+66) | Mids-gated 2nd-order twigs, per-branch spectralBandEnergy() tips, clamped residue trail; bass-envelope sim state verbatim. |
| 140 | `crystalline-fracture` | 13 | 175→238 (+63) | Click stress rings (ripples[]), fbm weak grain boundaries, crack memory 0.98 (<1.0) + min(stress,6) clamp; stress/connectivity layout kept. |
| 141 | `retro_phosphor_dream` | 13 | 175→252 (+77) | **Bug fix**: audioPulse MouseDown→bass; treble scanline jitter + hum-bar roll; mouse curvature + degauss wobble (extraBuffer[133]). |
| 142 | `spec-analytic-noise-flow` | 13 | 175→231 (+56) | Iso-contour ridges from free analytic gradient (treble-sharpened), bass advection surge, temporal velocity smoothing; quintic math byte-identical. |

### Batch 12 (8 shaders) — 2026-07-22 — GENERATIVE EDITION 3

8-agent generative swarm, next 8 smallest (160–169 lines). Theme: formalize `updatedParams` from EXISTING params (preset contract) + 2–3 tailored techniques +50–90 lines. Special wins: `generative-turing-veins` had 4 **dead sliders** (WGSL never read zoom_params — wired for real); `bubble-chamber` z-param double-duty split + backwards Speed mapping fixed; `emergent-calligraphic-weave` boilerplate controls evicted. **Cross-batch fix:** during completion, discovered engine writes 128 FFT bins to `extraBuffer[5..132]` every frame audio is active — 9 shaders from Batches 10–12 stored persistent state there (plus `holographic-crystal` writing reserved [0]). All remapped to the safe zone `[133..255]` and re-gated 9/9 green. Index map documented in `agents/WGSL_BUILTINS_GENERATIVE.md`. All 8 gate green, JSON contracts preserved, lists/dupes clean (1309 defs), Jest 332 pass. Briefs: `swarm-tasks/kimi-generative-briefs-2026-07-22-b12/`; notes: `swarm-outputs/kimi-generative-2026-07-22-b12/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 127 | `emergent-calligraphic-weave` | 12 | 160→215 (+55) | Boilerplate evicted — sliders→real brush constants (viscosity/dry-brush/chaos); curl-noise stroke flow; treble edge sizzle. |
| 128 | `bubble-chamber` | 12 | 163→229 (+66) | Bragg-curve ionization falloff, Lorentz point-vortex mouse deflection, z-param double-duty split, backwards Speed fixed, clamp 1.2. |
| 129 | `generative-turing-veins` | 12 | 165→244 (+79) | **Dead sliders wired**: scale→kernel radius, feed→GS regime 0.03–0.07, glow→ridge gain; bass nutrient wave; click colony seeding; state [133..136]. |
| 130 | `molten-gold` | 12 | 165→234 (+69) | True Planckian blackbody ramp (Tanner-Helland, 1337K melt point), fresnel flow-ridge specular, bass heat waves (+420K), clamp 1.2. |
| 131 | `phase-memory-weave` | 12 | 165→233 (+68) | Opalescent phase-gradient iridescence (0.3), memory clamp+decay (anti-latch), click thermal ring [133..136]; optimizations preserved. |
| 132 | `atmos_volumetric_fog` | 12 | 166→233 (+67) | 10-step mouse-anchored god-ray march (fbm-occluded), 2nd fbm density breakup, shaft-revealed treble dust motes, clamp 1.2. |
| 133 | `mycelium-network` | 12 | 166→239 (+73) | Click nutrient pulse packets [133..136], growth tropism toward cursor, bass heartbeat, worley strand thickness; anti-moire LOD intact. |
| 134 | `gen_julia_set` | 12 | 169→254 (+85) | Bass Lissajous c-morph (mouse overrides), interior filament detail, 2-sample hash-jitter AA; smooth-iteration + 3 orbit traps intact. |

### Batch 11 (8 shaders) — 2026-07-22 — GENERATIVE EDITION 2

8-agent generative swarm, next 8 smallest with empty `updatedParams` (gen_capabilities skipped — system-monitor demo). Theme same as Batch 10: formalize `updatedParams` from EXISTING params (preset contract), +2–3 tailored techniques, +50–90 lines. **Bonus: fixed a real feedback bug in `gen_wave_equation`** (solver read height/velocity from dataTextureC but wrote finalColor to dataTextureA → feedback carried color, not state; now state→A, plus NaN-kill for stale color). Also revived dead sliders (plasma-orb `arcChaos`, holo_interference `depthWeight`). All 8 gate green (naga + bindgroup, 0 warnings), JSON contracts preserved, lists/dupes clean (1309 defs). Briefs: `swarm-tasks/kimi-generative-briefs-2026-07-22-b11/`; notes: `swarm-outputs/kimi-generative-2026-07-22-b11/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 119 | `gen_cyclic_automaton` | 11 | 138→200 (+62) | Wavefront leading-edge tracer, treble ignition sparks, directional mouse painting (extraBuffer[5..7]); GH state machine verbatim. |
| 120 | `holographic_interference` | 11 | 144→194 (+50) | Treble speckle grain, thin-film IQ palette tint, mouse-tilt parallax, carrier fringe; dead depthWeight slider wired; ACES deduped. |
| 121 | `holographic-crystal` | 11 | 148→219 (+71) | Phase dither anti-moiré, worley facet normals (cut-glass), treble glints, true chromatic dispersion on slider. |
| 122 | `gen_wave_equation` | 11 | 149→215 (+66) | **Feedback bug fixed** (sim state→dataTextureA, NaN-kill sanitizer), 9-point Laplacian, click droplets + bass rain; KG/SG term preserved. |
| 123 | `plasma-orb` | 11 | 149→223 (+74) | Worley F2−F1 arc branching (dead arcChaos wired), spring-damper orb drift (extraBuffer[5..8]), mids corona shimmer, glow clamp 1.2; ACES deduped. |
| 124 | `plasma-jet-stream` | 11 | 152→214 (+62) | Divergence-free curl perturbation, analytic bass surge wave, chromatic shear fringe at jet boundaries. |
| 125 | `sacred-geometry-torus` | 11 | 155→219 (+64) | Phyllotaxis golden-angle lattice (Phi Layers), per-strand cosine hue cycling (0.35), trail clamp 1.2, crossing bloom. |
| 126 | `acoustic-string-theory` | 11 | 157→239 (+82) | Click-to-pluck ring-down (extraBuffer[5],[10..13]), spring-damper gravity well [6..9], per-string audio spectral weighting, clamp 1.2. |

### Batch 10 (8 shaders) — 2026-07-22 — GENERATIVE EDITION

8-agent generative swarm. Pool scan: 99 generative shaders with empty/missing `updatedParams`; took the 8 smallest never-in-any-batch. Theme: **formalize `updatedParams` using the EXISTING JSON param ids/defaults (saved-preset contract)** — all 8 already read `u.zoom_params.x–w` in WGSL but had no UI sliders wired — plus rewire generic boilerplate mappings (`applyGenerativePrimaryControls` etc.) to shader-specific constants, +2–3 techniques each, +50–90 lines. All 8 pass `wgsl_precommit_gate.py` (naga + bindgroup, 0 warnings), JSONs parse with param contract preserved, lists/dupes clean (1309 defs), Jest 332 pass. Briefs: `swarm-tasks/kimi-generative-briefs-2026-07-22/`; notes: `swarm-outputs/kimi-generative-2026-07-22/`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 111 | `fire_smoke_volumetric` | 10 | 117→181 (+64) | Worley ember sparks (temp-gradient tinted), treble edge flicker, smoke feedback clamp 1.2; sliders→heat/density+trail/depth floor/turbulence. |
| 112 | `multi-scale-evolutionary-cellular-gardens` | 10 | 124→174 (+50) | 8-neighbor diffusion (dist-correct weights), colony-border bioluminescence, per-epoch rule drift; boilerplate controls→real sim constants. |
| 113 | `recursive-ancestral-terrains` | 10 | 124→182 (+58) | Ridged-fbm crest octave, IQ palette lineage strata (mix 0.3), radial bass mutation waves from mouse; sliders→real lineage/mutation constants. |
| 114 | `neural-synapse-web` | 10 | 126→205 (+79) | Spring-damper mouse attractor + click pulse ring (extraBuffer[133..141], reserved 0..4 untouched), treble synapse sparkle masked by signal. |
| 115 | `magnetic-flux-garden` | 10 | 128→197 (+69) | Curl-noise flux-line weave, IQ palette bloom (mix 0.3), trail clamp 1.2; sliders→line count/dipole gain/curl amp/bloom gain. |
| 116 | `generative-psy-swirls` | 10 | 129→189 (+60) | fbm domain-warp before polar twist (breathing arms), mids per-layer hue fan, layer-memory clamp 1.2; Frequency also drives warp. |
| 117 | `4d-projection-dream-weavers` | 10 | 132→221 (+89) | Spring-damper 4D slice angles (extraBuffer[5..8]), Worley dream-dust (treble, depth-faded), dimension tint 0.25; fixed unused `detail` bug. |
| 118 | `symbiotic-light-propagation-networks` | 10 | 133→185 (+52) | Frame-stamped seed rings (extraBuffer[5..9]), bass glow→radial wave from seed, accumulation clamp 1.2; sliders→growth/transmission/balance/seed. |

### Batch 9 (8 shaders) — 2026-07-21

8-agent swarm on the next-smallest unclaimed pool shaders. Theme: **wire 4 slider params (`u.zoom_params.x–w`) into shaders whose `updatedParams` was empty** + 2–3 techniques each (fbm/worley, IQ cosine palettes, plasmaBuffer audio bands, spring-dampers, feedback clamps). All 8 pass `wgsl_precommit_gate.py` (naga + bindgroup), JSONs parse, lists/dupes clean, Jest 321 pass. Briefs: `swarm-tasks/kimi-briefs-2026-07-21/`; notes: `swarm-outputs/kimi-upgrade-2026-07-21/`. Manifest now 1308 shaders.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 103 | `bitonic-sort` | 9 | 241→304 (+63) | 4 sliders (Sort Threshold/Warp Amplitude/Edge Glow/Sort Length); bass-lowered luma gate, pre-sort FBM warp, sentinel-key span edge glow. Sort network byte-for-byte untouched. |
| 104 | `temporal-rgb-smear` | 9 | 220→296 (+76) | 4 sliders; spring-damper mouse velocity bends smear, treble sparkle grain, feedback blowup clamp (luma-echo-warp lesson). |
| 105 | `elastic-chromatic` | 9 | 207→297 (+90) | 4 sliders; spring-damper overshoot mouse, click shockwave ring, IQ cosine palette over blackbody grade. |
| 106 | `data-slicer-interactive` | 9 | 189→240 (+51) | 4 sliders; branchless fBM slice jitter, bass/mids band fix, click shockwave honoring per-ripple strength. |
| 107 | `pixel-stretch-cross` | 9 | 223→283 (+60) | 4 sliders; velocity-steered H↔V stretch axis, bass-pulse amplitude, HDR crossing bloom pre-ACES. |
| 108 | `interactive-magnetic-ripple` | 9 | 223→302 (+79) | 4 sliders; Worley F2−F1 field lines, spring-damped oscillator envelope, treble crest sparkle. |
| 109 | `luma-pixel-sort` | 9 | 207→262 (+55) | 4 sliders; param sort angle, bass threshold drop, cosine palette span tint. 25-comparator network + early exits intact. |
| 110 | `pixel-depth-sort` | 9 | 197→252 (+55) | 4 sliders; param sort radius (default = old look), mids gain, span-seam chromatic fringe, feedback clamp, pre-ACES dither. |

### Batch 8b (6 shaders) — 2026-07-19

6-agent swarm on the smallest single-pass shaders after the v6.0 queue emptied. Recorded late (was logged only in `memory/2026-07-19.md`). Gate 6/6 green.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 97 | `ring_slicer` | 8b | — | 2–4 techniques each: fbm/curl/worley, IQ cosine palettes, plasmaBuffer audio, mouse-down wiring. Gate green. |
| 98 | `pixel-sort-explorer` | 8b | — | Same recipe; gate green. |
| 99 | `hex-mosaic` | 8b | — | Same recipe; gate green. |
| 100 | `luma-slice-interactive` | 8b | — | Same recipe; gate green. |
| 101 | `spectral-smear` | 8b | — | Same recipe; gate green. |
| 102 | `luma-echo-warp` | 8b | — | Same recipe + **fixed real feedback blowup** (sparkle into dataTextureA unclamped at 0.99 decay → 15–30× runaway; clamped pre-tint at 1.2). |

### Batch 8 (4 new generative geometry shaders) — 2026-07-12

Colorful polyhedral geometry pass — spectral palettes, neon edges, iridescent surfaces, mouse 3D orbit, audio reactivity. Manifest now 1296 shaders.

| # | Shader | Batch | Lines | Description |
|---|--------|-------|-------|-------------|
| 93 | `gen-rainbow-icosahedron-cascade` | 8 | ~168 | Nested icosahedral wireframe shells with spectral edge glow. |
| 94 | `gen-chromatic-zonohedron` | 8 | ~130 | Rhombic zonohedron facet tiling with rainbow cells and neon edges. |
| 95 | `gen-prismatic-mobius-helix` | 8 | ~132 | Möbius-strip helix with thin-film iridescence. |
| 96 | `gen-neon-stellated-octahedron` | 8 | ~160 | Star tetrahedron with neon rainbow edges and kaleidoscopic symmetry. |

### Batch 7 (5 shaders) — 2026-07-12

Mixed pass: 3 remaining small fireworks upgraded to Batch 6 optimizer standard (hex-bokeh, star field, temporal persistence, semantic alpha); 1 new generative firework created; 1 visual-effect upgrade. All pass `naga` and `wgsl_precommit_gate.py`; manifest now 1292 shaders.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 88 | `gen-fireworks-strobe-shell` | 7 | 123→153 (+30) | Hex-bokeh flash cores, star field, camera blend, improved persistence/alpha. |
| 89 | `gen-fireworks-crossette` | 7 | 116→153 (+37) | Hex-bokeh arm sparks, GRAVITY physics, star field, semantic alpha. |
| 90 | `gen-fireworks-comet-trail` | 7 | 116→141 (+25) | Hex-bokeh head/trail, unified sparkPos gravity, star field, persistence. |
| 91 | `gen-fireworks-dahlia-burst` | 7 | NEW→189 | **New shader.** Flat dahlia-disk petal rows, layered timing, mouse burst, audio reactivity. |
| 92 | `phantom-lag` | 7 | 105→137 (+32) | Spring-damper bass, chromatic echo taps, ACES tone map, vec4 alpha preservation. |

### Batch 6 (16 generative shaders) — 2026-07-12

4-agent Kimi generative swarm: 4 fireworks optimizers, 4 visualists, 4 interactivists, 4 algorithmists. Expanded undersized generative shaders by **+52 to +115 lines** with canonical 13-binding compute pipeline, semantic alpha, audio/depth reactivity, and role-specific techniques (SDF/orbit traps, Fresnel/OkLab, spring-damper mouse, hex-bokeh fireworks). Post-dispatch fixes: `target` reserved keyword → `goal` in spring_damper helpers; `hash22` swizzle typo `p.yzx` → `p3.yzx`; completed `gen-sierpinski-tetrahedron` upgrade Kimi had not started. All 16 pass `naga` and `wgsl_precommit_gate.py`.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 72 | `gen-ethereal-cyber-chrono-nebula-phoenix` | 6 | 55→144 (+89) | Clifford attractor orbit trap, phoenix SDF, domain-warped nebula, audio fracture. |
| 73 | `gen-prismatic-cyber-aurora-astral-dragonfly` | 6 | 168→241 (+73) | Dragonfly SDF, Worley layers, strange-attractor crystals, iridescent orbit trap. |
| 74 | `gen-physarum-sacred-geometry` | 6 | 190→242 (+52) | Curl-noise agents, hex sacred mask, Mandelbrot trap, extraBuffer simulation. |
| 75 | `gen-sierpinski-tetrahedron` | 6 | 197→262 (+65) | 2nd-order domain warp, curl advection, Worley accent, Fresnel sheen, spring-damper audio. |
| 76 | `gen-luminescent-aether-plasma-nebula-koi` | 6 | 199→301 (+102) | Fresnel rim, OkLab mixing, chromatic aberration, blackbody temperature. |
| 77 | `gen-luminescent-quantum-glass-phoenix-egg` | 6 | 197→306 (+109) | Glass SDF refraction, thin-film iridescence, quantum orbit trap, split-tone. |
| 78 | `gen-ethereal-chrono-plasma-void-manta` | 6 | 174→289 (+115) | Manta SDF glide, plasma void FBM, temporal feedback, hue-preserve clamp. |
| 79 | `gen-quantum-fluorescent-nebula-anemone` | 6 | 171→260 (+89) | Anemone tentacle SDF, fluorescent palette, domain-warped nebula, vignette. |
| 80 | `gen-cybernetic-mycelium-neural-web` | 6 | 191→249 (+58) | Spring-damper audio, click-seeded mutation, mycelial attraction, temporal feedback. |
| 81 | `gen-neural-bioluminescence-matrix` | 6 | 191→260 (+69) | Neural graph Voronoi, click shockwave, gravity well, spring-damper envelopes. |
| 82 | `gen-showcase-nebula-core` | 6 | 196→250 (+54) | Gravity-well mouse, Balmer-series palette, click bursts, spring-damper audio. |
| 83 | `gen-worley-cellular-noise` | 6 | 171→224 (+53) | Spring-damper reactivity, mouse warp, cellular Worley layers, temporal feedback. |
| 84 | `gen-fireworks-fan-shell` | 6 | 102→169 (+67) | Hex-bokeh fan glow, mouse personal fan, bass energy, temporal persistence. |
| 85 | `gen-fireworks-horse-tail` | 6 | 104→170 (+66) | Hex-bokeh brocade trails, gravity fall, mouse burst, audio tail length. |
| 86 | `gen-fireworks-kamuro-gold` | 6 | 111→173 (+62) | Hex-bokeh gold droplets, mouse cascade, branchless shell timing. |
| 87 | `gen-fireworks-ring-shell` | 6 | 107→170 (+63) | Hex-bokeh ring glow, mouse ring, bass radius, gravity secondary sparks. |

### Batch 4 (10 shaders) — 2026-05-17

Full rewrites of raw Phase A/B shaders: added `plasmaBuffer` audio reactivity, replaced hardcoded `vec4(..., 1.0)` with meaningful alpha, converted `if` blocks to branchless `select()`/`mix()`, added `writeDepthTexture` + `dataTextureA` writes.

| # | Shader | Batch | Changes Made |
|---|--------|-------|--------------|
| 46 | `electric-contours` | 4 | Sobel edge detection with bass-driven glow, mids spark multiplier, meaningful alpha from edge strength + spark + base texture alpha. |
| 47 | `luma-force` | 4 | Branchless attract/repel via `select()`, luma-weighted force, mids-driven swirl distortion, alpha blends toward 1.0 near mouse. |
| 48 | `contour-flow` | 4 | Gradient-perpendicular flow with bass-driven speed, mids highlight tint, alpha from flow intensity + mouse factor + source alpha. |
| 49 | `magnetic-edge` | 4 | Branchless edge pull with `select()` displacement, bass boost on pull strength, mids glow tint, alpha from glow + influence. |
| 50 | `pixel-stretch-interactive` | 4 | Branchless mode selection (Right/Left/Cross), chromatic aberration with mids scaling, jitter gated by `select()`, alpha boosted on stretch. |
| 51 | `magnetic-pixels` | 4 | Branchless repulsion with `select()`, bass force scaling, mids chromatic tint, chaos noise gated by `select()`, alpha from displacement magnitude. |
| 52 | `spirograph-reveal` | 4 | Guilloche pattern reveal with bass-driven rotation speed, mids background boost, alpha blends pattern mask with source texture alpha. |
| 53 | `psychedelic-noise-flow` | 4 | Per-channel noise displacement with bass speed scaling, mids distortion strength, clamped UV sampling, alpha from displacement + mouse influence. |
| 54 | `liquid-lens` | 4 | Spherical lens refraction with chromatic aberration, branchless rim darkening/specular via `select()`, bass strength boost, alpha from lens mask. |
| 55 | `polka-wave` | 4 | Halftone dots with wave ripple from mouse, bass amplitude boost, alpha preserves source texture in dots + transparent background. |

### Batch 5 (16 shaders) — 2026-07-12

4-agent Kimi swarm pass on unclaimed small shaders. First pass compacted code too aggressively; a retry enforced original-functionality preservation and **+30 to +80 line expansion**. Each shader was assigned a primary role (Algorithmist / Visualist / Interactivist / Optimizer), upgraded with canonical 13-binding compute pipeline, semantic alpha, audio/depth reactivity, and ACES + IGN dither where appropriate. All 16 pass `naga` and `wgsl_precommit_gate.py`; `generate_shader_lists.js` and `check_duplicates.js` are clean.

| # | Shader | Batch | Lines (HEAD→final) | Changes Made |
|---|--------|-------|-------------------|--------------|
| 56 | `hyb-kaleidoscope-pulse` | 5 | 112→167 (+55) | Domain-warped FBM, SDF star, strange-attractor orbit-trap, phase kaleidoscope rings, chromatic split. |
| 57 | `ambient-liquid` | 5 | 141→195 (+54) | Curl-noise advection, reaction-diffusion spots, SDF metaball ink, anisotropic specular, vignette/film grain. |
| 58 | `rain-ripples` | 5 | 126→186 (+60) | Domain-warped FBM micro-ripples, Voronoi raindrops, caustic refraction, wet-area SDF, thin-film rainbow. |
| 59 | `complex-exponent-warp` | 5 | 129→209 (+80) | Dual-layer domain-warped FBM, Julia orbit-trap, Newton fractal coloring, SDF cardioid, stereo chromatic split. |
| 60 | `neon-edge-radar` | 5 | 102→141 (+39) | Fresnel rim, volumetric fog, hue-preserve clamp, blackbody temperature. |
| 61 | `holographic-glitch` | 5 | 95→128 (+33) | Fresnel rim, split-tone, film grain, hue-preserve clamp. |
| 62 | `hyb-iridescent-fbm-glow` | 5 | 85→147 (+62) | Chromatic aberration, Fresnel rim, OkLab mixing. |
| 63 | `thermal-vision` | 5 | 102→143 (+41) | Blackbody temperature, split-tone, hue-preserve clamp, vignette. |
| 64 | `mouse-ink-bleed` | 5 | 129→202 (+73) | Spring-damper mouse follow, gravity well, click shockwave, vortex ink splash, temporal feedback. |
| 65 | `interactive-voronoi-lens` | 5 | 132→209 (+77) | Spring-damper follow, gravity on cell centers, neon shockwave, Voronoi lens distortion. |
| 66 | `cyber-rain` | 5 | 130→205 (+75) | Bass-driven intensity, bending streaks/drops, thunder flash, parallax depth layers, temporal persistence. |
| 67 | `optical-feedback` | 5 | 148→228 (+80) | Lagging feedback center, self-evolving hue phase, gravity well, click burst, emergent feedback loop. |
| 68 | `focal-pixelate` | 5 | 77→152 (+75) | Hex-bokeh sampling, anti-moiré LOD bias, shared-memory tiling hint, branchless focus select, depth compositing. |
| 69 | `neon-edge-diffusion` | 5 | 87→141 (+54) | Anti-moiré LOD, hex-bokeh glow, early-exit ripple gating, branchless select/mix, depth compositing. |
| 70 | `radial-hex-lens` | 5 | 94→163 (+69) | Fractional hex LOD, weighted hex-bokeh sampling, shared-memory tiling hint, depth-aware focal plane. |
| 71 | `temporal-halation-freeze` | 5 | 78→127 (+49) | LOD-biased hex-bokeh bloom, early-exit dark-pixel fallback, shared-memory tiling hint, branchless warm/cool selection. |

### Batch 3 (10 shaders) — 2026-05-17

Completion pass on Phase A/B shaders: added `dataTextureA` temporal feedback writes, `upgraded-rgba` header tags, and fixed `luma-slice-interactive` scalar→vec4 depth write bug.

| # | Shader | Batch | Changes Made |
|---|--------|-------|--------------|
| 36 | `volumetric-god-rays` | 3 | Added `dataTextureA` write with ray-accumulated RGBA. Header now tagged `upgraded-rgba`. |
| 37 | `virtual-lens` | 3 | Added `dataTextureA` write with chromatic-aberration lens RGBA. Header now tagged `upgraded-rgba`. |
| 38 | `cyber-lattice` | 3 | Added `dataTextureA` write with grid-glow RGBA. Header now tagged `upgraded-rgba`. |
| 39 | `luma-slice-interactive` | 3 | Fixed `textureStore(writeDepthTexture, coords, depth)` scalar bug → `vec4<f32>(depth, 0.0, 0.0, 0.0)`. Added `dataTextureA` write. Header now tagged `upgraded-rgba`. |
| 40 | `neon-ripple-split` | 3 | Added `dataTextureA` write with neon-split RGBA. Header now tagged `upgraded-rgba`. |
| 41 | `dynamic-halftone` | 3 | Added `dataTextureA` write with halftone-dot RGBA. Header now tagged `upgraded-rgba`. |
| 42 | `neon-flashlight` | 3 | Added `dataTextureA` write with edge-emission RGBA. Header now tagged `upgraded-rgba`. |
| 43 | `quantum-field-visualizer` | 3 | Added `dataTextureA` write with quantum-chaos RGBA. Header now tagged `upgraded-rgba`. |
| 44 | `holographic-edge-ripple` | 3 | Added `dataTextureA` write with holographic-foil RGBA. Header now tagged `upgraded-rgba`. |
| 45 | `spectrogram-displace-pass2` | 3 | Added `dataTextureA` write with spectrogram-displaced RGBA. Header now tagged `upgraded-rgba`. |

### Batch 2 (10 shaders) — 2026-05-17

| # | Shader | Batch | Changes Made |
|---|--------|-------|--------------|
| 26 | `pixel-sort-radial` | 2 | Upgraded to 94 lines. Branchless `select()`/`mix()` logic, `hash22()` jitter, chromatic aberration (R/G/B offset sampling), audio reactivity (bass scales stretch, mids drive twist, click triggers 2.5x burst), HDR bloom alpha, writes `dataTextureA` for temporal feedback. |
| 27 | `pixel-drag-smear` | 2 | Upgraded to 119 lines. Added curl noise jitter, ACES tone mapping, warm/cool velocity tint, `lumaMix()` helper, alpha boost from influence, `dataTextureA` writeback. |
| 28 | `thermal-touch` | 2 | Upgraded to 88 lines. Branchless thermal palette via `smoothstep`+`mix()`, `hash21()` shimmer scaled by mids, bass-driven pulse, meaningful alpha (cold=0.5, hot=1.0), colorMode preserves original texture alpha. |
| 29 | `luma-magnetism` | 2 | Upgraded to 87 lines. Anisotropic RGB stretch, chromatic aberration, `curl()` noise jitter, bass boosts strength 2x, mids drive swirl, click shockwave (`0.15/dist`), glow halo, safe normalize guard via `select()`. |
| 30 | `pixel-scattering` | 2 | Upgraded to 84 lines. Branchless `smoothstep` radius, time-breathing radius, depth-based scatter boost, directional glow, bass/mids reactivity, click burst 3x, `size` param controls concentration alpha. |
| 31 | `circular-pixelate` | 2 | Upgraded to 106 lines. Depth-based dot sizing, audio pulse on radius, per-cell `hash12()` tint, transparent gaps via `mix(vec4(0.0), dot_color, mask)`, ripple click boost, inner edge highlight. |
| 32 | `mirror-drag` | 2 | Upgraded to 83 lines. Branchless `select()` mirror logic, kaleidoscope mode, neon seam glow, bass-driven axis oscillation, mids-driven sector rotation, click flip pulse, edge feathering via `smoothstep`. |
| 33 | `hypnotic-spiral` | 2 | Upgraded to 86 lines. Branchless `hsv2rgb` via `mix()`+`fract()`, secondary counter-rotating spiral, `hash12` sparkle, bass drives rotation, mids drive color cycling, click reverses direction, ripple distortion. |
| 34 | `pixelate-blast` | 2 | Upgraded to 83 lines. Ripple boost on pixel size, audio radius expansion, chromatic aberration at block edges, scanline + vignette, color crunch quantization, click shockwave. |
| 35 | `temporal-distortion-field` | 2 | Upgraded to 105 lines. Temporal feedback via `dataTextureC` read + `dataTextureA` write, FBM warp twist, bass-driven warp strength, mids-driven ghosting, treble shimmer, depth-scaled field radius, warm/cool temperature shift, click freeze. |

### Batch 1 (25 shaders)

| # | Shader | Batch | Changes Made |
|---|--------|-------|--------------|
| 1 | `rgb-glitch-trail` | B | Fixed workgroup size `(8,8,1)`. `dataTextureA` now stores full RGBA trail color instead of `vec4(intensity,0,0,1)`. Replaced naive `.r`/`.b` channel sampling with `vec4` blending using `glitch_weight = intensity * color.a`. |
| 2 | `chroma-shift-grid` | B | Fixed workgroup size. Replaced separate `R/G/B` sampling with full `vec4` blending where `blend = strength * c0.a`. Alpha now mixes toward the shifted samples' max alpha. |
| 3 | `selective-color` | B | Fixed workgroup size. Added `feather_exp = mix(0.5,3.0,zoom_params.w)`. Output alpha is now preserved: `final_alpha = mix(color.a * (1.0 - desat*0.3), color.a, mask)`. Renamed JSON param4 to **Mask Feather**. |
| 4 | `echo-trace` | B | Fixed workgroup size. History decay now preserves alpha: `new_history_a = history.a * decay_rate`. Brush mixing also blends alpha. `vec4(new_history_rgb, new_history_a)` written to both textures. |
| 5 | `temporal-slit-paint` | B | Fixed workgroup size. Removed `finalColor.a = 1.0` so input/video alpha is preserved through brush strokes and history decay. |
| 6 | `signal-noise` | B | Fixed workgroup size. Refactored RGB split to sample full `vec4` at each offset and blend channels using `shift_weight = clamp(...) * c0.a`. Static noise intensity is also modulated by `c0.a`. |
| 7 | `sonic-distortion` | B | Fixed workgroup size. Replaced `.r`/`.g`/`.b` sampling with full `vec4` blending controlled by `aberration_weight = mask * c0.a`. Alpha fades with distortion strength. |
| 8 | `galaxy-compute` | B | Fixed workgroup size. Generated pattern now computes `pattern_alpha = 0.4 + pattern_mask * 0.6`. Mixes overlay using `pattern_opacity = 0.3 + zoom_params.w * 0.7`. Updated JSON param4 name to **Pattern Opacity**. |
| 9 | `radial-rgb` | B | Fixed workgroup size. Replaced radial channel split with full `vec4` sampling and `blend_weight = effect * c0.a`. Original alpha is preserved in undistorted regions. |
| 10 | `luma-echo-warp` | B | Fixed workgroup size. Removed `outputColor.a = 1.0` so alpha is preserved through echo decay and warped mixing. |
| 11 | `gen-astro-kinetic-chrono-orrery` | A | Fixed workgroup size. Added param-driven hue with `plasmaBuffer` bass reactivity. Alpha fades with ray depth: `alpha = 1.0 - (t/MAX_DIST)*0.5`. |
| 12 | `gen-raptor-mini` | A | Fixed workgroup size. Added `plasmaBuffer` bass to rage mode. Body/trail now write meaningful alpha (`body=0.9+`, `trail=0.2–0.8`). Added glow halo derived from rage. |
| 13 | `gen-cosmic-web-filament` | A | Fixed workgroup size. Alpha now scales with `filDensity` so dark voids are transparent. Added `plasmaBuffer` bass reactivity to `warpStrength`. |
| 14 | `gen_psychedelic_spiral` | A | Fixed workgroup size. Replaced RGB-only patterns with smooth HSV hue rotation. Added alpha falloff at spiral edges. Center follows mouse. Added plasmaBuffer bass reactivity. |
| 15 | `cymatic-sand` | A | Fixed workgroup size. Alpha proportional to sand presence/contrast. Added writeDepthTexture height-field output. Added plasmaBuffer mids reactivity to shake frequency. |
| 16 | `gen-vitreous-chrono-chandelier` | A | Fixed workgroup size. Alpha transmission based on ray depth and transmission param. Switched audio to plasmaBuffer bass. Added writeDepthTexture pass-through. |
| 17 | `gen-xeno-botanical-synth-flora` | A | Fixed workgroup size. Added petal-edge feathering to transparent alpha. Added plasmaBuffer mids reactivity to growth/bloom. Added glowSpread param4. |
| 18 | `gen-crystal-caverns` | A | Fixed workgroup size. Added ray-depth alpha fade with fogDensity param. Mouse light modulates alpha. Added plasmaBuffer bass reactivity. |

---

## Active Queue — 0 Shaders Remaining (all completed ✅)

### Batch A — Small Generative (0 remaining — all completed ✅)

| # | Shader ID | Size | Status | Primary Upgrades |
|---|-----------|------|--------|------------------|
| A6 | `interactive-fisheye` | 2,838 | ✅ completed | Fixed workgroup size. Preserves original alpha with vignette falloff at distortion edge. Added bulge curve and edge vignette params. Added plasmaBuffer bass reactivity. |

### Batch B — Small RGB-Limited / Alpha-Oblivious Effects (0 remaining — all completed ✅)

| # | Shader ID | Size | Status | Primary Upgrades |
|---|-----------|------|--------|------------------|
| B1 | `radial-blur` | 2,781 | ✅ completed | Fixed workgroup size. Added depth pass-through. Added sample exponent, decay, and glow params. Added plasmaBuffer bass reactivity. |
| B2 | `swirling-void` | 2,944 | ✅ completed | Fixed workgroup size. Converted to full vec4 sampling with alpha preservation through black-hole darkness. Added audio reactivity param. |
| B3 | `static-reveal` | 2,865 | ✅ completed | Fixed workgroup size. dataTextureA now stores mask in alpha. Noise alpha derived from mask for smoother transition. Added noise scale param and depth pass-through. |
| B4 | `entropy-grid` | 2,941 | ✅ completed | Fixed workgroup size. Changed non-standard texture_depth_2d to texture_2d<f32>. Fixed depth pass-through. Added plasmaBuffer bass reactivity. |
| B5 | `digital-mold` | 2,981 | ✅ completed | Fixed workgroup size. Removed forced alpha=1.0. Mold blend uses mask * decayRate * color.a. Preserves original alpha outside mask. Added depth pass-through and audio reactivity. |
| B6 | `pixel-sorter` | 2,987 | ✅ completed | Fixed workgroup size. Moved threshold to zoom_params.w and intensity to zoom_params.z. Added plasmaBuffer bass reactivity. Depth pass-through already present. |
| B7 | `magnetic-field` | 3,188 | ✅ completed | Fixed workgroup size. Added plasmaBuffer bass reactivity pulsing strength. Depth pass-through already present. Updated JSON params and features. |
| B8 | `kaleidoscope` | 3,204 | ✅ completed | Fixed workgroup size. Out-of-bounds pixels now transparent with smoothstep edge softness. Preserves sampled alpha inside bounds. Added edge softness param. |
| B9 | `synthwave-grid-warp` | 2,969 | ✅ completed | Fixed workgroup size. Alpha derived from grid line intensity so lines are translucent. Added plasmaBuffer bass reactivity. Depth pass-through already present. |
| B10 | `sonar-reveal` | 3,047 | ✅ completed | Fixed workgroup size. Preserves baseColor.a through reveal/ring mix. Added depth pass-through. Added plasmaBuffer bass pulse to ring intensity. |
| B11 | `concentric-spin` | 2,983 | ✅ completed | Fixed workgroup size. Added ring gap opacity param with smoothstep alpha fade at boundaries. Added plasmaBuffer bass pulse to rotation speed. Depth pass-through already present. |
| B12 | `interactive-fresnel` | 3,069 | ✅ completed | Fixed workgroup size. Replaced naive RGB split with full vec4 sampling blended by aberration * cG.a. Added depth influence param and depth pass-through. Added plasmaBuffer bass pulse to displacement. |
| B13 | `time-slit-scan` | 2,835 | ✅ completed | Fixed workgroup size. Standardized all variable names to renderer conventions. Added plasmaBuffer bass reactivity to drift speed. Fixed ripples array size to 50. |
| B14 | `double-exposure-zoom` | 2,925 | ✅ completed | Fixed workgroup size. Replaced RGB-only screen blend with RGBA-aware blend preserving per-layer alpha. Added edge fade and audio reactivity params. Added depth pass-through and plasmaBuffer bass modulation. |
| B15 | `velocity-field-paint` | 2,906 | ✅ completed | Fixed workgroup size. Added depth pass-through. Replaced unused param4 with Audio Reactivity. Added plasmaBuffer bass reactivity to force calculation. |
| B16 | `pixel-repel` | 2,993 | ✅ completed | Fixed workgroup size. Replaced naive RGB split with full vec4 sampling and blend using aberration * c0.a. Preserves source alpha. Added plasmaBuffer bass reactivity to repel displacement. |
| B17 | `lighthouse-reveal` | 3,016 | ✅ completed | Fixed workgroup size. Reforced alpha preservation through beam reveal using texColor.a * visibility. Added depth pass-through. Added plasmaBuffer bass reactivity to beam rotation speed. |

### Batch C — Larger High-Impact Shaders (0 remaining — all completed ✅)

| # | Shader ID | Size | Status | Primary Upgrades |
|---|-----------|------|--------|------------------|
| C1 | `gen-quantum-mycelium` | 6,564 | ✅ completed | Fixed workgroup size. Added alpha falloff with edgeSoftness param. Added plasmaBuffer treble reactivity to node flicker. Added writeDepthTexture pass-through. |
| C2 | `gen-stellar-web-loom` | 6,535 | ✅ completed | Fixed workgroup size. Thread intensity drives alpha via opacity exponent param. Added plasmaBuffer bass reactivity to thread pulse. Added writeDepthTexture pass-through. |
| C3 | `gen-supernova-remnant` | 7,424 | ✅ completed | Fixed workgroup size. Replaced hard alpha=1.0 with density-based alpha via gasOpacity param. Added plasmaBuffer bass pulse to expansion/brightness. |
| C4 | `gen-cyber-terminal` | 9,107 | ✅ completed | Fixed workgroup size. Added glyph edge alpha anti-aliasing via SDF smoothstep. Added scanline bloom param. Used plasmaBuffer for cursor jitter and decode speed. Added writeDepthTexture pass-through. |
| C5 | `gen-bioluminescent-abyss` | 11,949 | ✅ completed | Fixed workgroup size. Added depth-based alpha fog via water clarity param. Bioluminescence glow affects alpha. Added plasmaBuffer bass reactivity. |
| C6 | `gen-chronos-labyrinth` | 14,095 | ✅ completed | Fixed workgroup size. Added distance-field alpha fade via atmospheric perspective param. writeDepthTexture matches ray depth. Added plasmaBuffer bass reactivity. |
| C7 | `gen-quantum-superposition` | 17,672 | ✅ completed | Fixed workgroup size. Probability-cloud alpha proportional to |ψ|² density via wavefunction opacity param. Added plasmaBuffer reactivity to quantum jitter. |

---



---

## Wolfram Alpha Reference Data (Batch 1)

> Computational constants and kernels gathered via Wolfram Alpha MCP for this week's shader upgrades.

### 1. Fresnel Reflectance (Schlick's R₀)

Normal-incidence reflectance for common materials:

| Material | n | R₀ |
|---|---|---|
| Water | 1.333 | 0.0201 |
| Glass | 1.500 | 0.0400 |
| Diamond | 2.420 | 0.1724 |

WGSL helper:
```wgsl
const FRESNEL_R0_WATER: f32 = 0.0200593122;
const FRESNEL_R0_GLASS: f32 = 0.04;
const FRESNEL_R0_DIAMOND: f32 = 0.1723949249;

fn schlickFresnel(cosTheta: f32, R0: f32) -> f32 {
    return R0 + (1.0 - R0) * pow(1.0 - cosTheta, 5.0);
}
```

### 2. Blackbody Color Temperatures

Approximate RGB values for shader use:

| Temperature (K) | RGB (normalized) |
|---|---|
| 2000 | `vec3<f32>(1.000, 0.526, 0.153)` |
| 4500 | `vec3<f32>(1.000, 0.828, 0.701)` |
| 6500 | `vec3<f32>(1.000, 0.976, 0.932)` |
| 9500 | `vec3<f32>(0.839, 0.912, 1.000)` |

### 3. Physical Constants

| Constant | Value | WGSL Symbol |
|---|---|---|
| Planck constant (h) | 6.626×10⁻³⁴ J·s | `PLANCK_H` |
| Reduced Planck constant (ℏ) | 1.055×10⁻³⁴ J·s | `PLANCK_HBAR` |
| Capillary wave speed* | 0.2477 m/s | `CAPILLARY_SPEED` |
| Sedov-Taylor radius exponent | 2/5 = 0.4 | `SEDOV_EXPONENT` |
| Rayleigh cross section (air, 550nm) | 1.188×10⁻³⁰ m² | `RAYLEIGH_SIGMA` |

*For λ=0.01m, γ=0.0728 N/m, ρ=1000 kg/m³, g=9.81 m/s²

### 4. Bessel J₀ Zeros (Airy Disk / Diffraction)

First 5 zeros for radial wave patterns:
```wgsl
const BESSEL_J0_ZEROS: array<f32, 5> = array<f32, 5>(
    2.4048255577,
    5.5200781103,
    8.6537279129,
    11.7915344390,
    14.9309177085
);
```

### 5. Golden Angle & Fibonacci

```wgsl
const GOLDEN_ANGLE: f32 = 2.3999632297; // radians, (3 - sqrt(5)) * π
const FIBONACCI: array<f32, 12> = array<f32, 12>(
    1.0, 1.0, 2.0, 3.0, 5.0, 8.0,
    13.0, 21.0, 34.0, 55.0, 89.0, 144.0
);

// Phyllotaxis spiral
fn phyllotaxis(i: f32) -> vec2<f32> {
    let r = sqrt(i) * 0.01;
    let theta = i * GOLDEN_ANGLE;
    return vec2<f32>(r * cos(theta), r * sin(theta));
}
```

### 6. Image Convolution Kernels

#### 3×3 Gaussian Blur (σ=1, normalized)
Sum = (2+√e)²/e ≈ 4.89764
```wgsl
const GAUSSIAN_3X3: array<f32, 9> = array<f32, 9>(
    0.0204, 0.1238, 0.0204,
    0.1238, 0.2042, 0.1238,
    0.0204, 0.1238, 0.0204
);
```

#### 3×3 Laplacian (edge detection)
```wgsl
const LAPLACIAN_3X3: array<f32, 9> = array<f32, 9>(
    0.0,  1.0, 0.0,
    1.0, -4.0, 1.0,
    0.0,  1.0, 0.0
);
```

#### Sobel Operators
```wgsl
const SOBEL_GX: array<f32, 9> = array<f32, 9>(
    -1.0, 0.0, 1.0,
    -2.0, 0.0, 2.0,
    -1.0, 0.0, 1.0
);
const SOBEL_GY: array<f32, 9> = array<f32, 9>(
    -1.0, -2.0, -1.0,
     0.0,  0.0,  0.0,
     1.0,  2.0,  1.0
);
```

### 7. Color Science & Fog Formulas

```wgsl
// Linear ↔ sRGB conversion
fn linearToSRGB(c: f32) -> f32 {
    return select(1.055 * pow(c, 1.0/2.4) - 0.055, c * 12.92, c <= 0.0031308);
}

fn sRGBToLinear(c: f32) -> f32 {
    return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
}

// Exponential fog
fn expFog(color: vec3<f32>, fogColor: vec3<f32>, depth: f32, density: f32) -> vec3<f32> {
    let fogFactor = exp(-depth * density);
    return mix(fogColor, color, fogFactor);
}

// Premultiplied alpha blend (over operator)
fn blendPremultiplied(dst: vec4<f32>, src: vec4<f32>) -> vec4<f32> {
    return vec4<f32>(dst.rgb + src.rgb * (1.0 - dst.a), dst.a + src.a * (1.0 - dst.a));
}
```

### 8. Signed Distance Functions (SDF)

```wgsl
fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// Polynomial smooth minimum for SDF blending
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
```

### 9. Seawater Attenuation Coefficients

| Wavelength | Coefficient (m⁻¹) |
|---|---|
| 450 nm (blue) | 0.03 |
| 550 nm (green) | 0.08 |
| 650 nm (red) | 0.35 |

```wgsl
const WATER_ATTENUATION: vec3<f32> = vec3<f32>(0.35, 0.08, 0.03); // R, G, B
```
## Detailed Code Suggestions

### A1 — `gen_psychedelic_spiral`
- Fix `@workgroup_size(16, 16, 1)` → `(8, 8, 1)`.
- If the shader computes color as `vec3<f32>(...)`, append alpha based on distance from spiral center:
  ```wgsl
  let alpha = 1.0 - smoothstep(0.3, 0.8, dist_from_center);
  textureStore(writeTexture, coords, vec4<f32>(col, alpha));
  ```
- Add mouse-driven focal point by offsetting the spiral center with `u.zoom_config.yz`.

### A2 — `cymatic-sand`
- Fix workgroup size.
- Where particles are written, set alpha proportional to speed:
  ```wgsl
  let speed_alpha = clamp(length(velocity), 0.0, 1.0);
  textureStore(writeTexture, coords, vec4<f32>(col, speed_alpha));
  ```
- Write depth based on particle height/pseudo-Z:
  ```wgsl
  textureStore(writeDepthTexture, coords, vec4<f32>(speed_alpha, 0.0, 0.0, 0.0));
  ```
- Add `plasmaBuffer[0].x` (bass) to the vibration frequency.

### A3 — `gen-vitreous-chrono-chandelier`
- Fix workgroup size.
- For glass surfaces, compute a Fresnel-like term and use it to lower alpha:
  ```wgsl
  let fresnel = pow(1.0 - abs(dot(normal, rd)), 2.0);
  let transmission = u.zoom_params.w;
  let alpha = mix(1.0, 0.4, fresnel * transmission);
  textureStore(writeTexture, coords, vec4<f32>(col, alpha));
  ```
- Add param4 in JSON as "Transmission" (0.0–1.0).

### A4 — `gen-xeno-botanical-synth-flora`
- Fix workgroup size.
- At petal edges (where `dist_to_edge` is small), feather alpha:
  ```wgsl
  let edge_alpha = smoothstep(0.0, 0.05, dist_to_edge);
  textureStore(writeTexture, coords, vec4<f32>(col, edge_alpha));
  ```
- Add `plasmaBuffer[0].y` (mids) to the growth/bloom pulse multiplier.

### A5 — `gen-crystal-caverns`
- Fix workgroup size.
- After raymarching, fade alpha with depth:
  ```wgsl
  let fog = u.zoom_params.w; // fog density
  let alpha = exp(-t * 0.05 * fog);
  textureStore(writeTexture, coords, vec4<f32>(col, alpha));
  ```
- Add JSON param4 "Fog Density".

### A6 — `interactive-fisheye`
- Fix workgroup size.
- The shader already samples full `vec4`, but can be enhanced with a vignette alpha at the radius edge:
  ```wgsl
  let edge_fade = smoothstep(radius, radius * 0.8, dist);
  color.a = color.a * edge_fade;
  textureStore(writeTexture, vec2<i32>(global_id.xy), color);
  ```

### B1 — `radial-blur`
- Fix workgroup size.
- The accumulator already averages full `vec4` samples, so alpha is preserved correctly. Add depth pass-through:
  ```wgsl
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
  ```
- Add `zoom_params.w` as "Sample Curve" to control `t` exponent:
  ```wgsl
  let curve = 0.5 + u.zoom_params.w * 2.0;
  let t = pow(f32(i) / f32(samples - 1), curve);
  ```

### B2 — `swirling-void`
- Fix workgroup size.
- Replace `.rgb` sampling and forced alpha:
  ```wgsl
  var color = textureSampleLevel(readTexture, u_sampler, new_uv, 0.0);
  // Apply darkness to rgb only
  if (dist < hole_size) {
      color.rgb = vec3<f32>(0.0);
  } else if (dist < hole_size * 2.0) {
      color.rgb *= smoothstep(hole_size, hole_size * 2.0, dist);
  }
  textureStore(writeTexture, coord, color);
  ```

### B3 — `static-reveal`
- Fix workgroup size.
- Store full mask in alpha:
  ```wgsl
  textureStore(dataTextureA, global_id.xy, vec4<f32>(mask, 0.0, 0.0, mask));
  ```
- Let noise alpha follow the inverse of the mask for smoother transitions:
  ```wgsl
  let noiseColor = vec4<f32>(vec3<f32>(noiseVal), 1.0 - mask);
  let finalColor = mix(noiseColor, videoColor, mask);
  ```

### B4 — `entropy-grid`
- Fix workgroup size.
- Change `readDepthTexture` binding type from `texture_depth_2d` to `texture_2d<f32>` (match standard bindings) and update depth read:
  ```wgsl
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  ```

### B5 — `digital-mold`
- Fix workgroup size.
- Preserve original alpha and blend mold with it:
  ```wgsl
  let moldAlpha = mask * decayRate * color.a;
  let decayed = mix(pixelColor, moldColor.rgb, colorShift);
  color = mix(color, vec4<f32>(decayed, 1.0), moldAlpha);
  ```

### B6 — `pixel-sorter`
- Fix workgroup size.
- Already preserves alpha. Add depth pass-through:
  ```wgsl
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
  ```
- Add `zoom_params.w` as "Sort Threshold" to replace mouse-Y dependency:
  ```wgsl
  let threshold = u.zoom_params.w;
  ```

### B7 — `magnetic-field`
- Fix workgroup size.
- Add depth pass-through and audio reactivity:
  ```wgsl
  let bass = plasmaBuffer[0].x;
  let strength = u.zoom_params.x * (1.0 + bass * 0.5);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
  ```

### B8 — `kaleidoscope`
- Fix workgroup size.
- Make out-of-bounds transparent:
  ```wgsl
  var color = vec4<f32>(0.0, 0.0, 0.0, 0.0);
  if (final_uv.x >= 0.0 && final_uv.x <= 1.0 && final_uv.y >= 0.0 && final_uv.y <= 1.0) {
      color = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0);
  }
  ```
- Add `zoom_params.w` as "Edge Softness" if a new param slot is desired (currently `w` is unused).

### B9 — `synthwave-grid-warp`
- Fix workgroup size.
- Derive alpha from grid line brightness so video shows through dark grid cells:
  ```wgsl
  let alpha = 0.2 + gridLine * 0.8;
  var finalColor = mix(videoColor * 0.5, gridColor, gridLine);
  finalColor += vec3(0.0, 1.0, 1.0) * warp * 2.0;
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  ```
- Add depth pass-through.

### B10 — `sonar-reveal`
- Fix workgroup size.
- Preserve input alpha through the reveal:
  ```wgsl
  var finalColor = mix(dimColor, baseColor.rgb, reveal);
  finalColor = finalColor + ringColorVec * ring * intensity;
  let final_alpha = mix(baseColor.a * 0.5, baseColor.a, reveal);
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, final_alpha));
  ```

### B11 — `concentric-spin`
- Fix workgroup size.
- Add ring-gap opacity using `zoom_params.w`:
  ```wgsl
  let gap_opacity = u.zoom_params.w;
  let ring_frac = fract(ringVal);
  let in_gap = smoothstep(0.45, 0.55, ring_frac);
  color.a = mix(color.a, color.a * gap_opacity, in_gap);
  textureStore(writeTexture, vec2<i32>(global_id.xy), color);
  ```
- Add depth pass-through.

### B12 — `interactive-fresnel`
- Fix workgroup size.
- Replace naive RGB split with full `vec4` blending:
  ```wgsl
  let c0 = textureSampleLevel(readTexture, u_sampler, baseUV, 0.0);
  let c_r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0);
  let c_b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0);
  let ab_weight = aberration * c0.a;
  var finalColor = c0;
  finalColor.r = mix(c0.r, c_r.r, ab_weight);
  finalColor.b = mix(c0.b, c_b.b, ab_weight);
  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  ```
- Add depth pass-through.

### B13 — `time-slit-scan`
- Fix workgroup size.
- Rename texture variables for consistency (optional but recommended):
  ```wgsl
  // Change: input_texture -> readTexture, output_texture -> writeTexture,
  // data_texture_a -> dataTextureA, data_texture_c -> dataTextureC,
  // depth_texture_read -> readDepthTexture, depth_texture_write -> writeDepthTexture
  ```
- Add audio reactivity to drift:
  ```wgsl
  let bass = plasma_buffer[0].x;
  let drift = vec2<f32>(drift_speed * 0.1 * (1.0 + bass), 0.0);
  ```

### B14 — `double-exposure-zoom`
- Fix workgroup size.
- Replace hard alpha with screen-blended alpha:
  ```wgsl
  let blended_rgb = 1.0 - (1.0 - col1.rgb) * (1.0 - col2.rgb);
  let blended_alpha = 1.0 - (1.0 - col1.a) * (1.0 - col2.a);
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(blended_rgb, blended_alpha));
  ```
- Add depth pass-through.

### B15 — `velocity-field-paint`
- Fix workgroup size.
- Add `plasmaBuffer` bass to force:
  ```wgsl
  let bass = plasmaBuffer[0].x;
  let force = u.zoom_params.z * 0.5 * (1.0 + bass);
  ```
- Add depth pass-through:
  ```wgsl
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  ```

### B16 — `pixel-repel`
- Fix workgroup size.
- Replace naive RGB split with full `vec4` blending:
  ```wgsl
  let c0 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let c_r = textureSampleLevel(readTexture, u_sampler, clamp(uv - displacement * (1.0 + aberration), vec2(0.0), vec2(1.0)), 0.0);
  let c_g = textureSampleLevel(readTexture, u_sampler, clamp(uv - displacement, vec2(0.0), vec2(1.0)), 0.0);
  let c_b = textureSampleLevel(readTexture, u_sampler, clamp(uv - displacement * (1.0 - aberration), vec2(0.0), vec2(1.0)), 0.0);
  let ab_weight = aberration * c0.a;
  var color = c0;
  color.r = mix(c0.r, c_r.r, ab_weight);
  color.g = mix(c0.g, c_g.g, ab_weight);
  color.b = mix(c0.b, c_b.b, ab_weight);
  textureStore(writeTexture, vec2<i32>(global_id.xy), color);
  ```

### B17 — `lighthouse-reveal`
- Fix workgroup size.
- Preserve input alpha:
  ```wgsl
  let finalColor = mix(texColor.rgb * ambient, texColor.rgb, mask);
  let finalAlpha = mix(texColor.a * ambient, texColor.a, mask);
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
  ```

### C1 — `gen-quantum-mycelium`
- Add alpha falloff at thread edges:
  ```wgsl
  let edge_dist = abs(d - thread_radius);
  let alpha = 1.0 - smoothstep(0.0, 0.02, edge_dist);
  ```
- Add `plasmaBuffer[0].z` (treble) to node brightness/flicker.

### C2 — `gen-stellar-web-loom`
- Let thread intensity drive alpha:
  ```wgsl
  let opacity_exp = u.zoom_params.w * 3.0 + 0.5;
  let alpha = pow(intensity, opacity_exp);
  textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
  ```
- Add JSON param4 "Thread Opacity Exponent" and `plasmaBuffer` bass reactivity.

### C3 — `gen-supernova-remnant`
- Replace hard `alpha = 1.0` with density-based alpha:
  ```wgsl
  let density = smoothstep(0.0, 1.0, nebula_val);
  let alpha = density * 0.7 + 0.3;
  textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
  ```
- Add `plasmaBuffer[0].x` to expansion radius.

### C4 — `gen-cyber-terminal`
- Add glyph edge AA using smoothstep against glyph SDF:
  ```wgsl
  let glyph_sdf = ...; // existing distance
  let glyph_alpha = smoothstep(0.05, 0.0, glyph_sdf);
  textureStore(writeTexture, id.xy, vec4<f32>(col, glyph_alpha));
  ```
- Add param4 "Scanline Bloom" mapped to `zoom_params.w`.
- Drive cursor jitter with `plasmaBuffer[0].x`.

### C5 — `gen-bioluminescent-abyss`
- Add depth-based fog alpha:
  ```wgsl
  let clarity = u.zoom_params.w * 5.0 + 0.1;
  let alpha = exp(-t * 0.05 * clarity);
  textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
  ```
- Add JSON param4 "Water Clarity".

### C6 — `gen-chronos-labyrinth`
- Add distance-field alpha fade:
  ```wgsl
  let atmo = u.zoom_params.w; // atmospheric perspective
  let alpha = exp(-t * 0.02 * atmo);
  textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
  ```
- Add JSON param4 "Atmospheric Perspective".

### C7 — `gen-quantum-superposition`
- Probability-cloud alpha:
  ```wgsl
  let psi_density = length(quantum_val);
  let opacity = u.zoom_params.w * 2.0 + 0.2;
  let alpha = clamp(psi_density * opacity, 0.0, 1.0);
  textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
  ```
- Add JSON param4 "Wavefunction Opacity".

---

## Execution Checklist (for swarm agents)

For each shader in the Active Queue:
- [ ] Read WGSL and JSON.
- [ ] Apply the specific upgrades above.
- [ ] Update JSON if new params/features are added.
- [ ] Run `node scripts/generate_shader_lists.js` and fix any errors.
- [ ] Mark the shader as **DONE** in this file and move it to the "Recently Completed" table.
- [ ] If the active queue drops below 25, add new candidates from the smallest-shaders list to replenish.

## Candidate Pool for Replenishment

Next smallest shaders not yet in any batch:
- `pixel-sand` (3,208)
- `crt-magnet` (3,230)
- `scan-distort-gpt52` (3,236)
- `digital-lens` (3,238)
- `chromatic-mosaic-projector` (3,242)
- `chrono-slit-scan` (3,242)
- `mosaic-reveal` (3,247)
- `quad-mirror` (3,256)
- `spiral-lens` (3,266)
- `tile-twist` (3,267)
- `page-curl-interactive` (3,284)
- `tesseract-fold` (3,286)
- `polar-warp-interactive` (3,287)
- `echo-ripple` (3,307)
- `scanline-wave` (3,315)
- `quantum-ripples` (3,331)
- `oscilloscope-overlay` (3,340)
- `spectral-brush` (3,353)
- `magnetic-interference` (3,355)
- `voxel-grid` (3,357)
- `polka-dot-reveal` (3,362)
- `scanline-sorting` (3,363)
- `neon-cursor-trace` (3,373)
- `directional-glitch` (3,382)
- `stereoscopic-3d` (3,386)
- `cyber-ripples` (3,390)
- `quantized-ripples` (3,400)
- `data-scanner` (3,405)
- `vertical-slice-wave` (3,411)
- `phantom-lag` (3,412)
- `xerox-degrade` (3,425)
