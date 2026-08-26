# MEMORY.md - Long-Term Curated Memory (Spark Engine)

**Last updated:** 2026-08-26 (progress audit + issues #1179–#1185)

## 2026-08-26 — Balanced premium eight-shader upgrade complete

- Upgraded `magnetic-edge`, `cyber-lattice`, `contour-flow`,
  `dynamic-halftone`, `circular-pixelate`, `holographic-glitch`,
  `luminance-wind`, and `temporal_echo` under the canonical 13-binding,
  16x16x1, exact-C, A-only, ACES, three-band-audio, four-live-control contract.
- Magnetic and lattice alone own guarded single-writer spring state in
  `extraBuffer[133..138]`. Wind and Temporal keep raw HDR A/C state with
  tone-mapped presentation; the other six keep display history. Saved params
  remain exact and all metadata is additive/aligned.
- Naga/strict/schema gates, duplicates, catalog baseline gate, uniforms,
  TypeScript, 84 Jest suites, and production build pass. Fresh relative
  catalogs pass URL policy; unrelated deploy-URL catalog drift was restored.
  Real-GPU interaction, temporal stability, composition, and performance QA
  remains external.

## 2026-08-26 — Progress audit: foundation before the next content wave

- Catalog ~1,347 unified IDs / 1,360 defs / 1,382 WGSL. Thumbs 353 (26.2%).
  Generative volume is not the bottleneck. Closed #1123–#1129 over-claimed:
  several original holes are still in tree. Previously-open board was only
  #1080 (WASM real-GPU promotion/demotion — still needs a workstation).
- **Healthy and frozen:** adapter ladder, TimedWaitAny, `compatibleSurface=nullptr`,
  canvas opaque + preferred format + C++ Fifo second configure, B→C then A→C,
  CMake/build.sh sharing `src/contracts/wasm_exports.json`, optional features
  `[3]` including subgroups, format-tier probe + main rgba16 packing, scanners
  adopting the renderer device. WASM stays Tier B. CRA+CRACO stays.
- **Still broken / unfinished:** WASM bridge is 10 JS files with no copy-drift
  CI; dead `react-app-rewired` / `customize-cra` / `webpack-cli`; TS workgroup
  fallback 8×8 vs C++ 16×16; 26 leftover 8×8 shaders; C++ `emptyTexture_`
  r32float + 16-byte rgba write; gpu-chores preview-only; audio mapper slot-0
  generative-only; extraBuffer 93 known + 32 dynamic-index; new dead slider
  `hyper-space-jump-blackbody`; README 1,291 vs 1,347; Physics Lab set 2 never
  became GraphRunner graphs.
- Filed **#1179–#1185** (plus leftover #1080):
  1. #1179 TS the WASM JS glue, drop dead CRA deps, `verify:wasm-bridge-sync`
  2. #1180 workgroup fallback 16×16 + empty-placeholder packing
  3. #1181 gpu-chores opt-in source auto-exposure
  4. #1184 extraBuffer / dead sliders / catalog count+ID SoT
  5. #1185 thumbs 26% → 50%+ with deferral manifest
  6. #1182 all-slot audio + OSC/WebMIDI VJ 2.0
  7. #1183 later: naga-WASM compile gate, Physics Lab set 2 graphs,
     GraphRunner C++ only after #1080, opt-in display-p3

## 2026-08-23 — Generative Hyper / Geometry batch complete

## 2026-08-23 — Generative Hyper / Geometry batch complete

- Upgraded five existing Hyper effects and created the five absent exact-ID
  ice, moire, iris, Islamic tiling, and Julia effects independently. Hyper Warp
  keeps its legacy underscore filenames and URL; Rain Matrix keeps numeric
  preset compatibility while receiving effect-specific labels.
- All ten use bindings 0–12, 16x16x1, exact C loads, A-only raw HDR feedback,
  ACES display output, semantic alpha/depth, bass/mids/treble, and four aligned
  live named controls. No target reads or writes extraBuffer or stores B/C.
- Proof: actual Naga 30.0.1 and static contract audits 10/10, no dead sliders or
  extraBuffer violations, relative catalogs at 453 generative / 1,345 unified,
  clean uniforms/URLs/TypeScript, Jest 81/81 (545 pass, 1 skip), and successful
  SKIP_WASM_BUILD production compile. Batch briefs, shader packing notes, and
  coordinator review are recorded; real-GPU tuning remains external.

## 2026-08-23 — Generative Hyper / Geometry batch requested

- Upgrade five existing effects in place: Hyper Rainbow Vortex, Hyper
  Refractive Rain Matrix, Hyper Warp, Hyperbolic Crystal Symbiosis, and
  Hyperbolic Tessellation. Preserve the legacy `gen_hyper_warp.*` filename and
  catalog URL plus saved numeric parameter compatibility.
- Add five independent exact-ID effects: Ice Crystal Lattice, Interference
  Moire Field, Iris Bloom Fractal, Islamic Geometric Tiling, and Julia Set
  Classic. Do not rename or repurpose nearby catalog entries.
- All ten require the canonical bindings 0–12, 16x16x1 workgroups, exact
  unfiltered C feedback, A-only raw HDR RGBA history, ACES display output,
  semantic alpha, generated depth, genuine bass/mids/treble response, four
  live named controls, and no greenfield extraBuffer use. Expected regenerated
  totals: 453 generative and 1,345 overall. Require Naga/static/dead-slider,
  catalogs/uniforms/TypeScript/Jest/build proof; visual and performance tuning
  remains a real-GPU browser handoff.

## 2026-08-23 — Remaining simulation / field / growth / decay batch requested

- Upgrade ten named simulations: two decay systems, terrain erosion, crystal
  phase growth, fire temperature, EM field, multi-state ecosystem, RGBA
  cellular automata, Lenia-on-video, and digital moss. Preserve original saved
  parameters and enforce the canonical 13-binding ABI, exact bounded C loads,
  A-only feedback, all three audio bands, held pointer and click ripples,
  semantic alpha, ACES, bounded optional state, and actual Naga validation.

## 2026-08-23 — Remaining simulation / field / growth / decay batch complete

- Upgraded all ten requested simulation shaders while retaining their distinct
  domain models: dual corrosion, hydraulic erosion, crystal phase growth,
  combustion, EM propagation, two ecosystems, Lenia, and digital moss.
- Replaced all filtered or unbounded C feedback with exact bounded loads, wired
  every saved slider and all three audio bands, added held input plus traveling
  click fronts, ACES, semantic alpha, and truthful four-channel A/C packing.
  No B or extraBuffer writes were introduced.
- Saved params compare exact 10/10. Naga/bindgroup passes 10/10; strict buffer
  and dead-slider audits, catalog URLs, uniform layout, TypeScript, all 81 Jest
  suites (545 pass, 1 skip), and the production build pass. The unified catalog
  remains 1,333 shaders. Real-GPU visual/stability tuning remains external.

## 2026-08-23 — Codex (g) wave / smoke / ink / volumetric batch complete

- Upgraded all ten requested effects with distinct stateful solvers: wave tank,
  condensation glass, volumetric steam, subtractive wet ink, thermal smoke,
  fire/soot fog, HDR aerogel scatter, heat haze, atmospheric fog, and magnetic
  EM ripples.
- All ten use the exact renderer 13-binding ABI, explicit 16×16×1 dispatch,
  bounded exact C loads, A-only feedback writes, `plasmaBuffer[0].xyz`, held
  pointer and capped age-guarded `u.ripples`, semantic alpha, and ACES. No
  shader-owned `extraBuffer` state was needed.
- Original saved `params` are exact 10/10. Updated metadata, category lists,
  the 1,333-entry unified manifest, and coordinator notes are present. Actual
  Naga is 10/10; strict buffer/dead-slider audits, URL/uniform/type gates, all
  81 Jest suites (545 pass, 1 skip), and the production build pass. Real-GPU
  visual and performance tuning remains the handoff.

## 2026-08-23 — Gemini batch — optical / glass / holographic / lens set (10) complete

- Completed all 10 advanced-hybrid optical, glass, holographic, and lens shaders to the full Gemini-style contract:
  1. `holographic-interferometry.wgsl`
  2. `holographic-interferometry-bilateral.wgsl`
  3. `holographic-failure-iridescence.wgsl`
  4. `frosted-glass-lens-iridescence.wgsl`
  5. `glass-refraction-prismatic.wgsl`
  6. `glass-wall-prismatic.wgsl`
  7. `anamorphic-flare-iridescence.wgsl`
  8. `dynamic-lens-flares-prismatic.wgsl`
  9. `photonic-caustics-iridescence.wgsl`
  10. `chroma-lens-iridescence.wgsl`
- Architectural rigor:
  - Canonical 13-binding WGSL compute header `@workgroup_size(16, 16, 1)` with out-of-bounds guards.
  - ACES tone mapping on output RGB.
  - Semantic alpha (transmission, depth, fringe confidence, or specular glow).
  - A-only writeback to `dataTextureA` and `writeTexture`; B remains untouched.
  - Exact `textureLoad(dataTextureC, pixel, 0)` previous frame feedback without filtering.
  - Three-band audio from `plasmaBuffer[0].x` (bass), `.y` (mids), `.z` (treble).
  - Single-writer spring-damper dynamics in `extraBuffer[133..138]`.
  - Capped click-ripple shockwave interaction with age guards `time - r.z`.
  - Naga-clean WGSL (removed undefined `saturate`, fixed audio indexing bugs, removed unneeded barriers).
- Definitions & manifest:
  - Saved parameters preserved byte-exact in all 10 JSON definition files in `shader_definitions/advanced-hybrid/`.
  - Added aligned `updatedParams`, features, tags, and feedback packing.
  - Regenerated multipass registry, category shader lists, and unified manifest (`1326` shaders cataloged with relative paths).
- Validation:
  - WGSL precommit gate 10/10 passed.
  - `typecheck`, `verify:uniforms`, `audit:extrabuffer` (0 new violations), `audit:dead-sliders` (0 new dead sliders), and `verify:shader-list-urls` all green.
  - Jest test suite: 81/81 passed (545 passed, 1 skipped).
  - Production build: compiled successfully.


- Current scope is ten effects: Wave Equation, Steamy Glass, Volumetric Steamy
  Glass, RGBA Ink Diffusion, Thermal Smoke Trails, Fire/Smoke Volumetric Fog,
  Aerogel Smoke HDR, Heat-Haze Volumetric, Atmospheric Volumetric Fog, and
  Interactive Magnetic Ripple EM. Apply the same strict contract as Codex (e):
  full bindings, ACES, semantic alpha, A-only feedback, bounded exact C loads,
  bass/mid/treble audio, optional state only at `extraBuffer[133..138]`, full
  pointer/held/click interaction, and actual Naga validation.

## 2026-08-23 — Codex (e) ferro / melt / tensor / fluid-sim batch requested

- Upgrade ten named effects: Liquid Jelly Fluid, Liquid Metal Prismatic,
  Liquid Oil Iridescence, Liquid Smear Structure, Melting Oil Blackbody, Honey
  Melt Blackbody, Viscous Drag Bilateral, Hyper Tensor Fluid, Coupled Fluid
  Feedback, and Ripple Tank. Enforce the full 13-binding contract, ACES,
  semantic alpha, A-only writeback, exact C loads, all three plasma audio bands,
  bounded persistent state only at `extraBuffer[133..138]`, preserved
  mouse/held/click-ripple response, and actual Naga validation.

## 2026-08-23 — Codex (e) ferro / melt / tensor / fluid-sim batch complete

- Closed all ten targets with thirteen Naga-clean WGSL modules. Legacy smear,
  thermal oil, honey, bilateral drag, tensor fluid, coupled fluid, and Ripple
  Tank code now uses distinct A/C state, exact bounded C loads, A-only writes,
  all-band audio, ACES, semantic alpha, and full interaction. The three already
  premium Batch 59 liquid shaders were contract-refined and revalidated.
- Ripple Tank retains seven graph passes while replacing its B handoff and
  broad scratch grid with A→C barriers and per-pixel capillary/foam state.
  Saved params remain exact; strict buffer/dead-control audits, catalogs,
  uniforms, TypeScript, 81 Jest suites, and production build are green. Real-GPU
  QA remains external.
- Nine unrelated optical/holographic shader edits appeared concurrently during
  this batch and were preserved untouched; do not attribute them to Codex (e).
**Last updated:** 2026-08-23 (Holographic / Hyper + Optical / Glass / Iridescence cohorts synced)

## 2026-08-23 — Holographic / Hyper generative cohort

- Upgraded Holographic Fracture, Lens-Flare Matrix, Membrane, Plasma Geode,
  Rainbow Surface, Hopf Fiber Bundle, Bismuth Clockwork, Bismuth Matrix,
  Tesseract Labyrinth, and Hyper Labyrinth under the canonical exact-C,
  A-only, three-band audio, pointer/held/click, semantic-alpha, and depth
  contract with all saved parameter values preserved.
- Lens-Flare Matrix, Membrane, and Hyper Labyrinth intentionally retain raw A
  state; the other seven store exact ACES display RGBA. Fracture's spring is
  guarded at `[133..137]`, Matrix's bass envelope moved from slot 0 to `[133]`,
  and Hyper Labyrinth no longer reads engine FFT slots.
- Forty named controls are live. Focused Naga/contract audits, catalog/uniform/
  TypeScript checks, Jest 84/84, and the production build pass. Real-GPU
  interaction, composition, stability, and performance QA remains external.

## 2026-08-23 — Optical / Glass / Holographic / Iridescence Upgrade Batch (10 shaders)

- Upgraded 10 optical / glass / holographic / iridescence shaders:
  1. `spec-iridescence-engine` (advanced-hybrid): Thin-film interference & spectral optics with per-wavelength FFT audio, resolved mask write (now stores display RGBA to dataTextureA), ACES tonemap, exact C loads, and spring cursor in `extraBuffer[133..138]`.
  2. `spec-prismatic-dispersion` (advanced-hybrid): 4-band spectral Cauchy dispersion with CIE color matching, resolved metadata write to dataTextureA (stores display RGBA), ACES tonemap, exact C loads, and spring cursor. Added aligned updatedParams.
  3. `frost-reveal-crystal` (advanced-hybrid): Anisotropic dendritic frost & crystal growth phase field with exact 4-neighborhood C loads, ACES tonemap, and spring cursor. Added aligned updatedParams.
  4. `fractal-glass-distort-bilateral` (advanced-hybrid): Recursive fractal glass rotation with bilateral edge-preserving filter, added writeback to dataTextureA, ACES tonemap, exact C loads, and spring cursor. Added aligned updatedParams.
  5. `bubble-lens-coupled` (advanced-hybrid): Fluid-coupled magnifying bubble lens with semi-Lagrangian advection, exact C loads, ACES tonemap, and spring cursor. Added aligned updatedParams.
  6. `chroma-depth-tunnel-prismatic` (advanced-hybrid): Deep prismatic chromatic tunnel with held pointer pull, axial packets, ACES tonemap, exact C loads, and spring cursor.
  7. `chromatic-focus-coupled` (advanced-hybrid): Fluid-coupled chromatic DOF with semi-Lagrangian advection, exact C loads, ACES tonemap, and spring cursor. Added aligned updatedParams.
  8. `chromatic-focus-guided` (advanced-hybrid): Depth-guided 7-band chromatic dispersion preventing edge bleeding, added writeback to dataTextureA, ACES tonemap, exact C loads, and spring cursor. Added aligned updatedParams.
  9. `distortion-gravitational-prismatic` (advanced-hybrid): Einstein-ring gravitational lensing with 4-band Cauchy dispersion, accretion disk, resolved metadata write to dataTextureA (stores display RGBA), ACES tonemap, exact C loads, and spring cursor. Added aligned updatedParams.
  10. `multi-fractal-compositor-lens` (advanced-hybrid): Multi-layer fractal compositor with gravitational lensing, clean rewrite from mangled source, added writeback to dataTextureA, ACES tonemap, exact C loads, and spring cursor. Added aligned updatedParams.
- Agent contract applied 10/10: Full 13-binding layout, ACES tonemapping, semantic alpha, writeback only to dataTextureA (and writeTexture/writeDepthTexture), exact textureLoad from dataTextureC, plasmaBuffer three-band audio reactivity, bounded extraBuffer[133..138] state only (single-writer), preserved mouse / held / click-ripple interactivity, and naga-clean WGSL.
- Preserved saved parameter contracts byte-for-byte in JSONs with aligned updatedParams.
- Proof: Naga 10/10, wgsl_precommit_gate 10/10, extraBuffer audit PASS, dead-sliders audit PASS (all 4 sliders live across all 10), URL policy PASS, Jest 84/84 suites (559 pass, 1 skip), and SKIP_WASM_BUILD=1 production build PASS. Real-GPU visual QA remains external handoff.


## 2026-08-23 — Optical / Prism / Crystal / Lens / Caustic Upgrade Batch (10 shaders)

- Upgraded 10 optical / prism / crystal / lens / caustic shaders:
  1. `prism-displacement` (distortion): Anamorphic spectral lens dispersion with depth-weighted magnification, rotation, ACES tonemap, exact C loads, and spring cursor in `extraBuffer[133..138]`. Added aligned updatedParams.
  2. `prismatic-mosaic` (distortion): Multi-layer prismatic facet tiles with volumetric fog, chromatic dispersion, vortex distortion, ACES tonemap, exact C loads, live saturation boost slider, writeback to dataTextureA, and spring cursor. Added aligned updatedParams.
  3. `refraction-tunnel` (distortion): Curvature-warped prismatic tunnel with hoop rails, liquid-rainbow caustics, ACES tonemap, exact C loads, and spring cursor.
  4. `spec-bicubic-crystal` (distortion): Bicubic Catmull-Rom crystalline distortion, resolved mask write to dataTextureA (stores display RGBA), ACES tonemap, exact C loads, and spring cursor. Added aligned updatedParams.
  5. `spiral-lens` (distortion): Möbius kaleidoscope & domain-warped spiral refraction, resolved metadata write to dataTextureA (stores display RGBA), ACES tonemap, exact C loads, and spring cursor.
  6. `voronoi-faceted-glass` (distortion): Cellular glass distortion with Voronoi facet refraction, resolved metadata write to dataTextureA (stores display RGBA), ACES tonemap, exact C loads, and spring cursor. Added aligned updatedParams.
  7. `gravitational-lensing` (advanced-hybrid): Schwarzschild geodesic raytracing with Shakura-Sunyaev disk, Planck blackbody fit, standard clamp tonemap, exact C loads, and spring cursor.
  8. `gravitational-lensing-nlm` (advanced-hybrid): Relativistic geodesics with Non-Local Means patch filtering, ACES tonemap, exact C loads, writeback to dataTextureA, and spring cursor. Added aligned updatedParams.
  9. `digital-lens-prismatic` (advanced-hybrid): Digital prismatic lens with hex grid, Cauchy dispersion, resolved metadata write to dataTextureA (stores display RGBA), ACES tonemap, exact C loads, and spring cursor.
  10. `crystal-illuminator-iridescence` (advanced-hybrid): Faceted glass and gemstone crystal with thin-film rainbow iridescence, ACES tonemap, exact C loads, writeback to dataTextureA, and spring cursor. Added aligned updatedParams.
- Agent contract applied 10/10: Full 13-binding layout, ACES tonemapping, semantic alpha, writeback only to dataTextureA (and writeTexture/writeDepthTexture), exact textureLoad from dataTextureC, plasmaBuffer three-band audio reactivity, bounded extraBuffer[133..138] state only (single-writer), preserved mouse / held / click-ripple interactivity, and naga-clean WGSL.
- Preserved saved parameter contracts byte-for-byte in JSONs with aligned updatedParams.
- Proof: Naga 10/10, wgsl_precommit_gate 10/10, extraBuffer audit PASS, dead-sliders audit PASS (all 4 sliders live across all 10), URL policy PASS, Jest 84/84 suites (559 pass, 1 skip), and SKIP_WASM_BUILD=1 production build PASS. Real-GPU visual QA remains external handoff.

## 2026-08-23 — Optical / Glass / Prism / Crystal / Lens Upgrade Batch (10 shaders)

- Upgraded 10 optical / glass / prism / crystal / lens distortion shaders:
  1. `bubble-lens` (distortion): Marangoni surfactant convection + per-band membrane resonance modes, thin-film interference, removed dataTextureB write (A-only writeback), ACES tonemap, exact C loads, and spring cursor in `extraBuffer[133..138]`.
  2. `crystal-facets` (distortion): Prismatic facet refraction & birefringence, canonical three-band audio, ACES tonemap, exact C loads, and spring cursor.
  3. `cyber-lens` (distortion): Tactical holographic HUD with rolling-shutter scan skew, telemetry rings, removed dataTextureB write (A-only writeback), ACES tonemap, exact C loads, and spring cursor.
  4. `fractal-glass-distort` (distortion): IFS attractor glass with wired live aberration slider, chromatic dispersion, ACES tonemap, exact C loads, and spring cursor.
  5. `glass-brick-distortion` (distortion): Fluted architectural glass brick wall with Snell's law dispersion, Schlick Fresnel, Beer-Lambert absorption, ACES tonemap, exact C loads, and spring cursor. Added aligned updatedParams.
  6. `glass-brick-wall` (distortion): Textured architectural glass with FBM normals, fixed dt calculation and click logic, ACES tonemap, exact C loads, and spring cursor. Normalized updatedParams.
  7. `infinite-zoom-lens` (distortion): Droste spiral recursion with chromatic dispersion, resolved mask-as-colour trap (stores display RGBA to dataTextureA), ACES tonemap, exact C loads, and spring cursor.
  8. `liquid-prism` (distortion): Cauchy wavelength dispersion ripple glass, replaced non-standard saturate with clamp, bounded caustic fronts, ACES tonemap, exact C loads, and spring cursor.
  9. `luma-glass` (distortion): Luminance-driven Sellmeier dispersion, caustic trace, subsurface scatter, click ripples, ACES tonemap, exact C loads, and spring cursor. Added aligned updatedParams.
  10. `luminescent-glass-tiles` (distortion): Luminance-warped glass tiles, resolved mask write to dataTextureA (stores display RGBA), Beer-Lambert absorption, click ripples, ACES tonemap, exact C loads, and spring cursor. Added aligned updatedParams.
- Agent contract applied 10/10: Full 13-binding layout, ACES tonemapping, semantic alpha, writeback only to dataTextureA (and writeTexture/writeDepthTexture), exact textureLoad from dataTextureC, plasmaBuffer three-band audio reactivity, bounded extraBuffer[133..138] state only (single-writer), preserved mouse / held / click-ripple interactivity, and naga-clean WGSL.
- Preserved saved parameter contracts byte-for-byte in JSONs with aligned updatedParams.
- Proof: Naga 10/10, wgsl_precommit_gate 10/10, extraBuffer audit PASS, dead-sliders audit PASS (all 4 sliders live across all 10), URL policy PASS, Jest 84/84 suites (559 pass, 1 skip), and SKIP_WASM_BUILD=1 production build PASS. Real-GPU visual QA remains external handoff.

## 2026-08-23 — Reconciled local main with origin/main (Batch 67/70 + #1167/#1169)

- Merged the 8 remote commits (Batch 70 fluid/slime, generative named-params
  #1167/#1169, Batch 67 fast-motion/psychedelic #1170) into local `main`, which
  already carried the optical/glass/holographic/crystal batch plus earlier
  branch-union upgrades.
- Overlap policy: kept local optical `holographic-flicker` (ACES + clamp; Batch
  67 still used undefined `saturate` and non-canonical spring slots). Took Batch
  67 versions of `glass-wipes`, `liquid-jelly`, and `ferrofluid-spikes` (contract
  base + fast-motion/psychedelic). Unique remote shaders and named-params kept.
- Catalogs regenerated after conflict resolution. Real-GPU QA remains external.

## 2026-08-23 — Optical / Glass / Holographic / Crystal Upgrade Batch (10 shaders)

- Upgraded 10 optical / glass / holographic / crystal shaders:
  1. `holographic-projection` (visual-effects): Core holographic projection with Bessel interference, ACES tonemap, exact C loads, and spring cursor.
  2. `holographic-projection-gpt52` (visual-effects): Volume Bragg diffraction hologram with thin-film interference, ACES tonemap, exact C loads, and spring cursor.
  3. `holographic-flicker` (visual-effects): Laser diode instability & phosphor raster decay with temporal chromatic ghosting from exact C loads, clamp instead of non-standard saturate, and spring cursor.
  4. `holographic-sticker` (visual-effects): Rainbow diffraction foil with aspect-corrected geometry, micro-groove grating, ACES tonemap, exact C loads, and spring cursor.
  5. `alpha-multi-layer-glass` (visual-effects): 3-layer refractive glass stack with live roughness GGX microfacet scatter, Snell's law refraction, Schlick Fresnel, ACES tonemap, exact C loads, and spring cursor.
  6. `anamorphic-caustic-flare` (visual-effects): Cylindrical anamorphic lens flare with living water caustics, integrated bokeh optics, ACES tonemap, exact C loads, and spring cursor.
  7. `glass-shatter-morph` (advanced-hybrid): Voronoi glass shard shattering with morphological edge erosion/dilation, 16x16 workgroup, ACES tonemap, exact C loads, and spring cursor.
  8. `glass-bead-curtain-iridescence` (advanced-hybrid): Spherical thin-film glass bead curtain with fixed dt/mouse/alpha calculations, Beer-Lambert transmission, ACES tonemap, exact C loads, and spring cursor.
  9. `gemstone-fractures-crystal` (advanced-hybrid): Faceted gemstone shards with interior dendritic crystal growth, quartz-to-diamond IOR dispersion, ACES tonemap, exact C loads, and spring cursor.
  10. `bismuth-crystal-growth` (advanced-hybrid): 4-fold cubic hopper step crystal growth with phase-field solidification, oxide-layer rainbow iridescence, ACES tonemap, exact C loads, and spring cursor.
- Agent contract applied 10/10: Full 13-binding layout, ACES tonemapping, semantic alpha, writeback only to dataTextureA (and writeTexture/writeDepthTexture), exact textureLoad from dataTextureC, plasmaBuffer three-band audio reactivity, bounded extraBuffer[133..138] state only (single-writer), preserved mouse / held / click-ripple interactivity, and naga-clean WGSL.
- Preserved saved parameter contracts byte-for-byte in JSONs with aligned updatedParams.
- Proof: Naga 10/10, wgsl_precommit_gate 10/10, extraBuffer audit PASS, dead-sliders audit PASS (all 4 sliders live across all 10), URL policy PASS, Jest 84/84 suites (559 pass, 1 skip), and SKIP_WASM_BUILD=1 production build PASS. Real-GPU visual QA remains external handoff.

## 2026-08-23 — Remaining fluid / paint / reaction / slime batch requested

- Scope: alpha-fluid-simulation-paint, chromatographic-fluid,
  sim-heat-haze-field, sim-slime-mold-growth, sim-slime-mold-growth-em,
  slime-mold-on-video, gray-scott-tank, spec-runge-kutta-advection,
  painterly-oil-bilateral, and cyber-ripples-coupled.
- Preserve saved params and apply canonical exact-C, A-only, ACES, semantic
  alpha, three-band plasma audio, bounded `[133..138]` state, full pointer/click
  interaction, and Naga-clean requirements across all 17 WGSL members.
- Completed as Batch 70. Chromatographic and Gray-Scott retain seven/six graph
  dispatches with A-only handoffs. All 17 WGSL files pass Naga 30.0.1; params,
  focused contracts, graph tests, Jest, catalogs, and build are green. EM Slime
  no longer corrupts pixel `(0,0)` with pointer state; Cyber's abstract-literal
  Naga failure is repaired. Real-GPU stability/visual QA remains external.

## 2026-08-23 — Codex generative-only ten requested

- Upgrade Cybernetic Mycelium, Cyclic Automaton, Cycloid Bloom, Cymatic Plasma,
  Quantum Silk Loom, De Jong Attractor, Depth-Refracted Stained Glass, DLA
  Copper, DMT Fractal Zoom, and Dragon Curve with the usual exact-C/A-only/
  ACES/semantic-alpha/three-band-audio/bounded-state/interaction/Naga contract.
- Ensure four named `params` in every JSON. Nine targets currently expose only
  `updatedParams`; Cyclic Automaton already has four `params` and uses the
  historical underscore filenames `gen_cyclic_automaton.{json,wgsl}`.
- Completed as Batch 71. All ten shaders pass Naga/bind-group validation and
  scoped contract audits. DLA now owns raw persistent deposit/depletion/
  oxidation/tip state; Silk Loom's weave-speed control is live; DMT mouse UV is
  corrected; Plasma spring reads are bounds-safe. Nine definitions gained four
  aligned named params and all ten document feedback packing. Jest 84/84,
  TypeScript/uniforms/URLs, catalogs, manifest, and production build are green;
  real-GPU visual and long-run simulation QA remains external.


## 2026-08-23 — Reconciled main: Batch 70 + #1167 + Batch 67 (#1170)

- Merged local Batch 70 fluid/slime with origin named-params #1167, then Batch 67
  fast-motion/psychedelic ten-pack (#1170). No WGSL conflicts between B70 and B67.
- Regenerated audits after report conflicts; focused gate 25/25; cohort dead
  sliders 0. Full-tree dead-slider noise (65 unrelated) left as regenerated truth.
- User chose main↔origin reconcile only; leftover upgrade remotes left alone.

## 2026-08-23 — Merged shader upgrade branches into main

- Landed `cursor/effect-shaders-complexity-8594`, `new-shader-upgrades`, and
  `claude/shader-upgrades-motion-colors-m55m70` onto `main`.
- Overlaps kept the stronger cursor/main liquid + Batch 69 upgrades; unique
  shaders from the other branches retained. Catalogs regenerated to 1,334.
- Jest 84/84, focused Naga green, WASM-skipped build green. Real-GPU QA external.

## 2026-08-23 — Remaining liquid core + ferro/fluid simulation cohort

- Requested set: liquid-v1, liquid, liquid-rainbow,
  liquid-viscous-grokcf1, luma-velocity-melt, rain-ripples,
  ferrofluid-spikes, ferrofluid-em, liquid-magnetic-ferro-em, and
  ambient-liquid-coupled.
- Preserve the canonical 13 core bindings, exact C loads, A-only feedback,
  ACES, semantic alpha, bass/mids/treble, guarded state only at `[133..138]`,
  mouse/held/click-ripple response, saved params, and Naga cleanliness.
- Completed with four raw A simulations: Liquid V1 and Liquid own
  height/velocity/foam/coverage, Magnetic Ferro EM owns
  height/velocity/potential/charge, and Ambient Coupled owns two coupled
  height/velocity layers. The other six own semantic HDR display history; B is
  unwritten for all ten.
- Eight pointer-heavy effects use guarded single-writer `[133..138]` springs;
  Liquid V1 and Luma Melt use no extra state. Saved params are byte-exact.
- Focused Naga and contract gates 10/10, extraBuffer clean, URL policy green,
  1,333 unique manifest IDs including all ten, Jest 81/81 (545 pass, 1 skip),
  and the WASM-skipped production build pass. Real-GPU QA remains external.

## 2026-08-23 — Shader upgrade Batch 60 — CYBER/DIGITAL INTERACTIVE TEN

- Upgraded user-requested ten-pack: data-stream-structure, datamosh-brush,
  datamosh-brush-diffusion, digital-decay-rgba, digital-glitch-pass1/2,
  digital-lens-prismatic, digital-moss-rgba, digital-reveal-guided,
  glitch-ripple-drag.
- Cohort standard: spring cursor [133..138], held-drag, capped ripples,
  plasmaBuffer + bins, textureLoad on C, ACES, semantic alpha, dataTextureA
  writes, 16x16. datamosh-brush 8x8→16x16. Params exact; updatedParams added.
- Gate 10/10; Jest 84/84 (559 pass); build green. Real-GPU QA external.
  Branch: `cursor/cyber-digital-shader-upgrades-e675`.
**Last updated:** 2026-08-23 (Batch 58D spectral/datamosh upgrade)

## 2026-08-23 — Batch 58D spectral and datamosh upgrade

- Ten effects now use exact C history/state, authoritative A, no B writes,
  guarded `[133..138]` springs, real plasma bands/FFT, bounded click windows,
  canonical ACES, semantic alpha, source depth, and 16x16x1 workgroups.
- Raw A ownership is explicit for Spectral Vortex (phase/curl/energy), Data
  Moshing (offset/confidence/age), and Datamosh (motion/age/strength). The other
  seven own display RGBA; Spectral Waves remains premultiplied.
- Official Naga 30.0.0 gate 10/10; params exact; indexed controls aligned;
  catalogs unique and relative; Jest 81/81 and production build green.
- Cloud VM visual QA remains external, especially raw-state initialization,
  feedback stability, pointer/click feel, alpha/depth, performance, and presets.

## 2026-08-23 — Batch 56 triple-lineage merge (cursor branch)

- Three concurrent Batch 56 pushes claimed tracker #475–482. Merged on
  `cursor/effect-shaders-complexity-8594`: kept every unique upgrade;
  hand-merged cursor↔main overlaps (chromatic-focus-interactive,
  cmyk-halftone-interactive, quantum-prism) on top of the earlier main
  dual-lineage merge.
- **Cursor unique:** ascii-shockwave, heat-haze-gpt52, sphere-projection,
  fractal-kaleidoscope, rgb-iso-lines.
- **Overlap policy:** cursor geometry (iris blades, rosette rings, hex grout)
  + prior optical/feedback polish; CMYK A coverage preserved.
- Proof: focused gate **17/17**, cohort dead-slider + extraBuffer PASS,
  catalogs regenerated. Real-GPU visual QA remains external.
**Last updated:** 2026-08-23 (Batch 59)

## 2026-08-23 — Shader upgrade Batch 59 — CYBER & DIGITAL

- Upgraded tracker #511–520: cyber-ripples, cyber-scan, cyber-trace,
  cyber-organic, cyber-rain, digital-glitch, digital-haze, digital-reveal,
  edge-glow-mouse, ferrofluid.
- Critical fixes: cyber-rain extraBuffer[0..7] removed (spring [133..138]);
  digital-glitch 16×16; textureLoad on C for scan/trace/reveal/glitch/haze;
  digital-reveal spring gated to (0,0).
- Cohort standard: held-pointer, capped ripples, plasmaBuffer + bins, ACES,
  semantic alpha, dataTextureA writes. Gate 10/10; Jest 84/84; build green.
  Branch: `upgrade/batch-59-cyber-digital`. Real-GPU QA external.

## 2026-08-23 — Shader upgrade Batch 58C — HOLOGRAPHIC & QUANTUM

- Upgraded ten shaders: holographic-interferometry, holographic-projection,
  quantum-smear, quantum-wormhole, quantum-foam, holographic-entropy-vortex,
  holographic_interference, holographic-shatter, holographic-sticker, quantum-cursor.
- Fixed interferometry fake-audio (`config.y` ripple-count collision); rebuilt
  projection as holo projector; repaired quantum-smear/wormhole zoom_config
  hijacks; quantum-foam 8×8→16×16.
- Cohort standard: held-pointer, capped ripples, plasmaBuffer audio + bins,
  textureLoad on C, semantic alpha, dataTextureA writes. Gate 10/10; Jest
  84/84 (550 pass); build green. Real-GPU QA external.

## 2026-08-23 — Shader upgrade Batch 58E — INTERACTIVE COHORT

- Upgraded tracker #491–500: interactive-emboss, film-burn, fisheye, fresnel,
  glitch-brush, glitch-cubes, halftone-spin, kuwahara, magnetic-ripple, origami.
- Source `params` exact. Held-drag, capped clicks, oil-slick color, exact C
  loads. Existing extraBuffer springs kept (0,0 writer). A packing documented
  per shader. Gate 10/10 naga+bindgroup. Real-GPU QA remains external.

## 2026-08-23 — Unique alternate-branch upgrades unioned onto main

- Fast-forwarded local `main` to `origin/main` (already had #1105, #1132, #1137).
- Copied unique positive Batch 56 WGSL/JSON from `cursor/effect-shaders-complexity-8594` (#1136, dirty/unmergeable) without reverting #1137 or Batch 57 `fractal-kaleidoscope`.
- Kept: chromatic-focus, cmyk-halftone, cyber-slit-scan, heat-haze-gpt52, hyb-spectral-fbm-displace, infinite-zoom-lens, liquid-warp-interactive, phosphor-magnifier, quantum-prism, rgb-iso-lines, sphere-projection, warp_drive.
- Dropped: chrono branch (conflict-marker deletions vs main), claude weekly-plan-only branches (already landed as #1133), cursor `ascii-shockwave` (main #1137 version is the fuller upgrade).
- Resolved leftover `<<<<<<<` from earlier landings in `gen-abyssal-plasma-void-medusa` and `gen-chrono-kinetic-fractal-engine` (JSON now canonical `params`/`updatedParams`).
- #1126 device-adoption WIP remains stashed as `wip-1126-and-local-before-branch-union`.

## 2026-08-23 — Shader upgrade Batch 58 — SMALLEST MISSING-PARAM CONTRACTS

- User changed cohort selection policy: use an objective backlog rule such as
  smallest codewise or missing params, not adjacency to prior batches.
- Applied rule: eight smallest cataloged single-pass compute WGSL files with
  exactly four saved params but no `updatedParams`, excluding declared
  multipass and pass-ID files. Selected Triangle Mosaic, Polka Wave, Sphere
  Projection, Foil Impression, Bio Touch, Hypnotic Spiral, Spirograph Reveal,
  and Voronoi Chaos (tracker #491–498).
- Preserved params 8/8; added continuous geometry, held/click response, spectral
  color, three-band audio, truthful metadata, and aligned `updatedParams`.
  Triangle Mosaic now writes display RGBA to A to match its existing exact C
  feedback. Repaired Hypnotic normalized pointer/click coordinates and event cap,
  Voronoi/Hypnotic bounds guards, Voronoi sampling bounds, and Foil binding names.
- Proof: focused gate 8/8 (Naga unavailable), strict focused buffer/dead-slider
  audits clean, TypeScript clean, Jest 81/81 (545 pass, 1 skip), production build
  green. Real-GPU visual QA remains external.

## 2026-08-23 — Shader upgrade Batch 58 — SMALLEST MISSING-PARAM CONTRACTS

- User changed cohort selection policy: use an objective backlog rule such as
  smallest codewise or missing params, not adjacency to prior batches.
- Applied rule: eight smallest cataloged single-pass compute WGSL files with
  exactly four saved params but no `updatedParams`, excluding declared
  multipass and pass-ID files. Selected Triangle Mosaic, Polka Wave, Sphere
  Projection, Foil Impression, Bio Touch, Hypnotic Spiral, Spirograph Reveal,
  and Voronoi Chaos (tracker #491–498).
- Preserved params 8/8; added continuous geometry, held/click response, spectral
  color, three-band audio, truthful metadata, and aligned `updatedParams`.
  Triangle Mosaic now writes display RGBA to A to match its existing exact C
  feedback. Repaired Hypnotic normalized pointer/click coordinates and event cap,
  Voronoi/Hypnotic bounds guards, Voronoi sampling bounds, and Foil binding names.
- Proof: focused gate 8/8 (Naga unavailable), strict focused buffer/dead-slider
  audits clean, TypeScript clean, Jest 81/81 (545 pass, 1 skip), production build
  green. Real-GPU visual QA remains external.

## 2026-08-23 — Shader upgrade Batch 58 — SMALLEST MISSING-PARAM CONTRACTS

- User changed cohort selection policy: use an objective backlog rule such as
  smallest codewise or missing params, not adjacency to prior batches.
- Applied rule: eight smallest cataloged single-pass compute WGSL files with
  exactly four saved params but no `updatedParams`, excluding declared
  multipass and pass-ID files. Selected Triangle Mosaic, Polka Wave, Sphere
  Projection, Foil Impression, Bio Touch, Hypnotic Spiral, Spirograph Reveal,
  and Voronoi Chaos (tracker #491–498).
- Preserved params 8/8; added continuous geometry, held/click response, spectral
  color, three-band audio, truthful metadata, and aligned `updatedParams`.
  Triangle Mosaic now writes display RGBA to A to match its existing exact C
  feedback. Repaired Hypnotic normalized pointer/click coordinates and event cap,
  Voronoi/Hypnotic bounds guards, Voronoi sampling bounds, and Foil binding names.
- Proof: focused gate 8/8 (Naga unavailable), strict focused buffer/dead-slider
  audits clean, TypeScript clean, Jest 81/81 (545 pass, 1 skip), production build
  green. Real-GPU visual QA remains external.

**Last updated:** 2026-08-23 (Codex liquid complexity batch)

## 2026-08-23 — Codex Liquid Shader Complexity Batch requested

- Current implementation scope is ten single-pass effects: Liquid Smear, Liquid
  Tensor Vortex, Liquid Rainbow Prismatic, Liquid Perspective, Liquid RGB,
  Liquid Viscous, Liquid Viscous Simple, Liquid Zoom, Luma Melt Interactive,
  and Viscous Drag. Preserve saved params byte-for-byte, canonical bindings and
  feedback order, use bounded exact C loads with A-only writes, all three audio
  bands, strong held input, age-guarded capped clicks, semantic alpha, ACES, and
  distinct shader-specific complexity. Replace Tensor Vortex's generic overlay
  that introduced duplicate WGSL declarations. Add missing aligned metadata,
  regenerate relative catalogs/manifest, document ownership and real-GPU QA,
  and require actual Naga plus strict/type/Jest/build proof.

## 2026-08-23 — Codex (c) Liquid Shader Complexity Batch complete

- Completed all ten distinct single-pass upgrades and removed Tensor Vortex's
  invalid generic Batch 63 clock-ring appendix/duplicate declaration. Exact
  saved params and A/C ownership hold 10/10; B and extraBuffer are unused; all C
  state/history reads are bounded exact loads; metadata and generated catalog
  records document raw versus display feedback truthfully.
- Proof: temporary Naga CLI 30.0.1 and integrated focused gate pass 10/10;
  strict interaction/ownership and aligned metadata audits pass; liquid catalog
  is 29 entries and unified manifest 1,333 unique IDs with ten-target parity;
  uniforms, TypeScript, 81 Jest suites (545 pass, 1 skip), and the
  SKIP_WASM_BUILD production build are green. Real-GPU visual/stability/1080p
  performance QA remains external.

## 2026-08-23 — Liquid Shader Upgrade Batch 59 complete

- Implement the ten named liquid shaders from the supplied plan. Preserve
  byte-exact saved params and renderer contracts; use exact bounded C loads and
  documented feedback packing; wire all four sliders, real three-band audio,
  aspect-correct mouse/held/capped clicks; regenerate catalogs/manifest and add
  batch briefs, shader notes, and coordinator review with structural, type,
  Jest, and build proof. Jelly Fluid, Magnetic Ferro EM, and Oil Iridescence
  receive the heavier bounded sampling/state budgets; all remain single-pass.
- Closed with exact saved params 10/10, strict focused audits and structural
  gate 10/10 (Naga unavailable), 1,333 unique catalog/manifest entries with
  parity, clean uniforms/TypeScript, Jest 81/81 (545 pass, 1 skip), and a green
  SKIP_WASM_BUILD production build. Real-GPU visual/performance QA is external.
## 2026-08-23 — Gemini shader-upgrade branch is unclosed WIP

- `new-shader-upgrades` is 10 commits ahead of `main`, pushed through
  `20d71453`; it changes 58 unique committed shaders and leaves Glass Wall plus
  Holographic Flicker dirty.
- Treat it as salvageable input, not an accepted batch: no briefs/coordinator
  review or complete validation were recorded, 39 edits share a generic overlay,
  seven temporary rewrite scripts were committed, and at least two committed
  shaders plus one dirty shader use undefined `saturate`.
- Structural binding/workgroup and strict extraBuffer checks are clean, but Naga
  and real-GPU proof are absent. Before continuation, audit interaction/ripple
  semantics, saved-slider liveness, exact C feedback reads, and distinct effect
  identity across the whole branch.

## 2026-08-23 — Shader upgrade Batch 58 — SMALLEST MISSING-PARAM CONTRACTS

- User changed cohort selection policy: use an objective backlog rule such as
  smallest codewise or missing params, not adjacency to prior batches.
- Applied rule: eight smallest cataloged single-pass compute WGSL files with
  exactly four saved params but no `updatedParams`, excluding declared
  multipass and pass-ID files. Selected Triangle Mosaic, Polka Wave, Sphere
  Projection, Foil Impression, Bio Touch, Hypnotic Spiral, Spirograph Reveal,
  and Voronoi Chaos (tracker #491–498).
- Preserved params 8/8; added continuous geometry, held/click response, spectral
  color, three-band audio, truthful metadata, and aligned `updatedParams`.
  Triangle Mosaic now writes display RGBA to A to match its existing exact C
  feedback. Repaired Hypnotic normalized pointer/click coordinates and event cap,
  Voronoi/Hypnotic bounds guards, Voronoi sampling bounds, and Foil binding names.
- Proof: focused gate 8/8 (Naga unavailable), strict focused buffer/dead-slider
  audits clean, TypeScript clean, Jest 81/81 (545 pass, 1 skip), production build
  green. Real-GPU visual QA remains external.

## 2026-08-23 — Shader upgrade Batch 57 — KINETIC IMAGE TRANSFORMATIONS

- Upgraded tracker #483–490: Pixel Sort Radial, Mirror Drag, Psychedelic Noise
  Flow, Neon Flashlight, ASCII Flow, Temporal Distortion Field, Pixel Drag
  Smear, and Fractal Kaleidoscope.
- Added continuous shader-specific geometry, held-pointer deformation, capped
  click fronts, psychedelic color, and truthful three-band audio. Wired all
  previously dead ASCII/Fractal controls plus Pixel Drag mode and Temporal
  Distortion depth weight.
- Replaced filtered rgba32float history reads with bounded exact loads in Mirror
  Drag, Temporal Distortion, and Pixel Drag; preserved display-RGBA A ownership,
  unused B, canonical bindings, and zero `extraBuffer` access.
- Proof: focused gate 8/8 (Naga unavailable), params exact 8/8, strict focused
  buffer/dead-slider audits clean, TypeScript clean, Jest 81/81 (545 pass,
  1 skip), production build green. Real-GPU visual QA remains external.

## 2026-08-23 — Shader upgrade Batch 56 — INTERACTIVE COMPLEXITY

- Upgraded tracker #475–482: CMYK Halftone Interactive, Cyber Slit Scan,
  Interactive Ripple, Phosphor Magnifier, Vertical Slice Wave, Chromatic Focus,
  Quantum Prism, and Matrix Curtain.
- Added shader-specific geometry, continuous motion, psychedelic color,
  three-band audio, held-pointer response, and click loops capped at 50 while
  preserving all saved `params`, canonical bindings, unused B, and no
  `extraBuffer` access.
- Deliberate feedback corrections: Phosphor Magnifier A now stores display RGBA
  for truthful afterimages; Vertical Slice Wave A stays envelope/spring/velocity
  state and is no longer read as RGB/alpha history. Ripple is documented as an
  analytic Huygens field and Matrix occupancy as Conway-inspired.
- Proof: focused structural gate 8/8 (Naga binary absent), strict cohort buffer
  and dead-slider audits pass, params exact 8/8, catalogs/URLs/uniforms clean,
  TypeScript clean, Jest 81/81 (545 pass, 1 skip), production build green.
  Real-GPU visual QA remains external.

## 2026-08-21 — WASM `getGPUTimings` bridge ABI

- JS SoT is **`src/wasm/bridge/*.js`**. `concat_bridge.sh` copies src → `wasm_renderer/bridge` + `public/wasm/bridge`. Editing `wasm_renderer/bridge` gets overwritten. JS-only: no emcc; Playwright still needs a CRA rebuild.
- Do **not** change C++ `getGPUTimings` to a JSON string. Match out-params via `_malloc` / `ccall` / `getValue` / `_free`. Never return `{}` — always the `GPUTimings` shape (`timingSource` synthesized in JS).

## 2026-08-21 — Progress audit: foundation residual before next content

- Catalog ~1,343 defs / ~1,366 WGSL / manifest ~1,328; thumbs ~353 PNGs (~27%
  nominal, ~21% healthy). Renderer modularization, GraphRunner Physics Lab set 1,
  gpu-chores kit, TS 5.4, format-tier *types*, and WASM init ladder are in tree.
- Open board was only #1080 (WASM real-GPU promotion/demotion) and #1111
  (thumbnail regression gate). #1111 body is stale: `thumbs:check-regression`
  exists and runs on PRs, but still lacks deferrals, skip/integrity eligibility,
  and set-difference `newlyEligible` (comment posted).
- **Strategic call: build foundation, not another generative swarm.**
  - Adapter ladder / opaque canvas / limits JSON / B→C then A→C: **leave alone**.
  - WASM stays Tier B; no GraphRunner C++ port until #1080.
  - CRA+CRACO stays; Vite deferred.
- Filed **#1123–#1129**:
  1. #1123 WASM compile SoT (CMake export drift; C++ cannot request subgroups —
     `requiredFeatures[2]`; scanner feature set is a third variant)
  2. #1124 rgba16float tiers real (`probeFormatCapabilities` hardcodes true;
     C++ `writeTexture` always fp32 bytesPerRow)
  3. #1125 bridge SoT is `src/wasm` (concat copies src→wasm_renderer); drop
     unused `react-app-rewired` / `customize-cra` / `webpack-cli`; TS the JS glue
  4. #1126 second devices: ShaderValidator/Scanner + depth `requestAdapter`
  5. #1127 gpu-chores opt-in auto-exposure on catalog source (not just 64×64 preview)
  6. #1128 catalog hygiene (hyphen/underscore ids, graph parents, 44 leftover 8×8,
     parseWorkgroupSize fallback 8×8 vs canonical 16×16)
  7. #1129 later: Physics Lab set 2 (DLA, Kuwahara, Droste, ecology, Poincaré,
     byte-mosh) + audio mapping for **all slots** / simulation graphs
     (`useAudioReactiveParams` is slot-0 generative only)
- Audio-reactive slider mapping **exists** but is opt-in and slot-0/generative-only.
- Attract mode + Physics Lab chip already exist.

## 2026-08-17 — Repeating black present flicker (timestamp queries)

- **Symptom:** repeating black flashes during otherwise healthy WebGPU rendering.
- **Cause:** `encodeResolveAndCopy` skipped `resolveQuerySet` while `mapAsync` was pending; subsequent frames rewrote the same query indices without resolve → WebGPU validation killed the command buffer (present never ran, clear stayed black). Multipass also rewrote the same end-query index every intermediate pass.
- **Fix:** always resolve when stamps were written; per-slot `stagingBusy` for the 2-deep readback ring; intermediate multipass passes omit timestamps (only phase starts + final compute end). WASM `ResolveTimestampQueries` mirrors resolve-always. Tests in `WebGPUTiming.test.ts` updated.
- Real-GPU visual QA still external (no GPU adapter on Cloud VM).


## 2026-08-16 — Shader upgrade Batch 52 — INTERACTIVE VECTOR FIELDS & OPTICAL DYNAMICS

- Upgraded tracker #447–454 across the Interactive Vector Fields & Optical Dynamics cohort:
  Interactive Fresnel, Velocity Field (Vorticity Confinement), Fluid Lens Dynamics (Interactive Fisheye),
  Magnetic Field, Digital Mold, Swirling Void, Elastic Chromatic Explosion, and Motion Revealer.
- Added rich physical kinematics: multi-pole Lorentz vector fields, 2D Navier-Stokes momentum advection
  with vorticity confinement, Kelvin-Voigt viscoelastic droplet surface tension, continuous Gray-Scott
  reaction-diffusion kinetics, general relativistic Kerr metric frame dragging, and Lucas-Kanade
  optical flow structure tensor coherence analysis.
- Upgraded `swirling-void` from non-canonical 8x8 to canonical 16x16x1 compute workgroups.
- Replaced all non-standard / hardware-dependent float32 filtering operations with exact `textureLoad` from `dataTextureC`.
- Structural proof: 8/8 Naga and bindgroup gate, 0 new extraBuffer violations, 0 new dead sliders,
  catalogs in sync (1,341 unique IDs, 0 duplicates), uniforms layout contract in sync. Real-GPU visual QA remains external.

## 2026-08-15 — Shader upgrade Batch 51 — LIQUID DYNAMICS, GEOMETRY & VISCOUS FLOW

- Upgraded tracker #439–446 across the Liquid Effects cohort: Liquid Fast,
  Liquid RGB, Liquid Jelly, Liquid Rainbow, Liquid Perspective, Liquid Glitch,
  Liquid Viscous Nebula grokcf1, and Liquid Viscous (Simple).
- Added dual continuous motion structures (Hamiltonian divergence-free streamfunctions,
  complex potential vortex superposition, Kelvin-Voigt viscoelastic elasticity,
  trochoidal Gerstner waves, Laplace cohesion, and vorticity confinement), 2.5D
  heightfield normal derivatives, Snell's law refraction, thin-film optical
  interference, Voronoi cellular quantization, and interactive pointer drag wakes.
- Replaced all rgba32float feedback reads with exact `textureLoad` from `dataTextureC`.
- Structural proof: 8/8 Naga and bindgroup gate, 0 new extraBuffer violations,
  0 new dead sliders, catalogs in sync (1,340 unique IDs, 0 duplicates), uniforms layout
  contract in sync. Real-GPU visual QA remains external.

## 2026-08-15 — gpu-chores analysis layer (Tier 4b)

- Shared pre-FX kit in `src/gpuChores/`: BT.709 histogram, reduce_f32, lut_u8_map,
  downsample_2d. Adopts the renderer `GPUDevice` — never `requestDevice()`.
- Live path: auto-exposure from the histogram **normalizes the 64×64 preview**,
  not catalog FX. Kill switch `?no_gpu_compute`. Breadcrumbs in Dev Tools.
- CPU goldens are the Chromashift-shaped parity SoT on the headless VM.
- Docs: `docs/GPU_CHORES.md` (Tier 4a = domain FX, Tier 4b = chores).
- Device-init policy and feedback B→C / A→C copy order untouched.

## 2026-08-15 — Multipass Physics Lab flagships (#1081 / epic #1076)

- Three new Tier C graphs: `chromatographic-fluid` (7), `gray-scott-tank` (6),
  `optical-flow-dream` (4, history ring). TS GraphRunner only; no C++.
- GraphRunner now returns `GraphRunReport` and shrinks Jacobi repeats before
  dropping the color write. Dev Tools shows truncated steps + validation errors.
- Shader Browser has a Physics Lab chip (`hasGraph`). Attract pool includes the
  three new stacks plus `fabric-of-reality` at 22s dwell.
- Structural proof: 12/12 naga+bindgroup; focused Jest 45+ green. Real-GPU
  visual QA and thumbnail regen remain workstation-side.

## 2026-08-15 — Deploy SFTP credentials

- `npm run deploy` / `deploy:app` / shader SFTP sync no longer prompt when
  gitignored `.env.deploy` or an authorized SSH key is present.
- Shared loader: `scripts/deploy_credentials.py`. Example: `.env.deploy.example`.
- This VM's ed25519 key is authorized on `ford442@1ink.us`.
- The live DreamHost password is still the one that was once committed; rotate
  it when convenient. Never put it back in tracked files.

## 2026-08-10 — Batch 45 — Psychedelic generative six

## 2026-08-10 — Batch 45 — Psychedelic generative six

- User requested six new colorful psychedelic-inspired generative shaders with
  four live sliders plus mouse position, click, and drag response. Created
  Kaleidoscopic Synapse Bloom, Liquid Cathedral Dream, Mushroom Mandala Garden,
  Prismatic Serpent River, Cosmic Velvet Hypnosis, and Chromatic Oracle Jelly
  as tracker #389–394.
- Every shader uses pointer position plus mouseDown for held local deformation,
  bounded ripple timestamps for clicks, exact-load A/C display history, real
  audio, semantic alpha, and generated structural depth. B and `extraBuffer`
  remain unused.
- Proof is green: WGSL/Naga and interaction contracts 6/6, four-control
  liveness, buffer, and uniform audits pass; only the 431-entry generative
  catalog changes, unified manifest is 1,320, URLs are relative, definitions
  are 1,333/1,333 unique, Jest is 77/77 suites (508 pass / 1 skip), and the
  production build passes. Real-GPU visual QA remains external.

## 2026-08-10 — Shader upgrade Batch 44 — FAST MOTION ENCORE

- Upgraded tracker #381–388 across Lenia, Reaction-Diffusion, Video Echo
  Chamber, Ion Stream, Chroma Depth Tunnel, Mercury Temporal Mirror, Viscous
  Drag, and Rain Lens Wipe. Rainbow Vector Field was explicitly rejected after
  coordinator review exposed its hidden Pass-1 multipass ownership.
- Added state/display conveyors, traveling packets/streaks, and bounded click
  fronts without frame-hash motion. Repaired filtering rgba32float reads,
  Chroma's 8x8 workgroup, missing bounds guards, Ion's zero-density division,
  Viscous output/alpha bounds, and overclaimed depth/physics metadata.
- Proof is green: gate and contract audit 8/8, exact source params, indexed
  controls, A packing, unused B, live sliders/audio/mouse/clicks, zero new
  extraBuffer writes, relative URLs, 1,327 unique IDs, Jest 77/77 suites (508
  pass / 1 skip), and production build. Real-GPU visual QA remains external.

## 2026-08-10 — Shader upgrade Batch 43 — FAST MOTION ENCORE

- Upgraded tracker #373–380 across the first clean all-category cohort after
  Batch 42's generative queue closeout: Neon Quantum Lattice, Neon Strings, Kimi
  Chromatic Warp, Sine Wave, Slime Mold on Video, Thermal Touch Blackbody, VHS
  Jog, and Alpha Luminance History.
- Added shader-specific closed-form conveyors/packets/runners, bounded exact-load
  history advection, and click fronts. Repaired 8x8 workgroup/bounds/filtering,
  halo, safe-log/continuous-blend, output-bounds, and dead-diffusion issues while
  removing time-hash strobing and correcting overclaimed thermal metadata.
- Proof: gate 8/8; strict buffer and schema-aware contract audits PASS; source
  params exact; A packing preserved; B unused; no extraBuffer access; 1,327
  unique IDs; Jest 77/77 suites (508 pass / 1 skip); production build green.
  Real-GPU visual QA remains external.

## 2026-08-09 — Shader upgrade Batch 41 — FAST MOTION ENCORE

- Upgraded tracker #364–371: Morphogenic Resonance, Chrysanthemum Burst,
  Volumetric Cloud Nebula, Quantum Neural Lace, Aurora Borealis Loom, Willow
  Cascade, Hyperbolic Crystal Symbiosis, and Wind & Ripple Fireworks.
- Repaired fireworks-family normalized mouseUV bugs, missing A/depth/audio on
  Nebula and Neural Lace, spurious dataTextureB writes, and aspect mouse on
  Morphogenic Resonance. Added closed-form conveyors, speed-line streaks,
  ripple shock fronts, and bounded textureLoad HDR trails; B remains unused and
  no `extraBuffer` writes were introduced.
- Proof: focused WGSL/Naga gate 8/8; strict extraBuffer audit PASS; 8/8
  `updatedParams` byte-exact; 1,326 unique IDs; Jest 76/76 suites (506 pass /
  1 skip); supplemental `DISABLE_ESLINT_PLUGIN=true SKIP_WASM_BUILD=1` build
  green. Real-GPU visual QA remains external. ~49 generative pending remain.

## 2026-08-09 — Shader upgrade Batch 40 — FAST MOTION ENCORE

- Upgraded tracker #356–363: Gravitational Ferrofluid Singularity Engine,
  Abyssal Leviathan Scales, Abyssal Silicate Geode Weaver, Neuro-Kinetic
  Liquid-Gold Lotus, 4D Projection Dream Weavers, Prismatic Fractal Dunes,
  Sentient Liquid-Neon Fractal Heart, and Micro-Cosmos.
- Repaired fake ripple-count/timestamp audio, normalized-pointer scaling/Y,
  Lotus's generic control shim, Heart's invalid per-map ripple loop, missing
  display history, and flat/missing generated depth. Added closed-form fast
  motion and bounded visible A/C trails; B remains unused and no `extraBuffer`
  writes were introduced.
- Proof: focused WGSL/Naga gate 8/8; strict extraBuffer audit PASS; 8/8
  saved arrays exact; duplicate scan 1,326/1,326; Jest 76/76 suites (506 pass /
  1 skip); supplemental production compile PASS. Canonical Jest/build are blocked
  only by pre-existing WASM bridge WIP. Real-GPU visual QA remains external.

## 2026-08-08 — RendererManager + StoragePanel strangler (#1079 / PR #1092)

- Extracted renderer seams mirroring webgpu/* split: `backendLifecycle`, `slotOrchestration`, `inputSourceBridge`, `performanceStatus` (+ diagnostics/types helpers) with colocated Jest.
- `RendererManager.ts` facade **344 LOC** (was 987); all public API + contracts preserved (no WASM auto-fallback, feedback order untouched, #887 duck-types).
- `StoragePanel` split into `panels/*` (list/browser, detail, ratings, upload, operations); facade **200 LOC**; library tab uses `StorageClient.listLibrary()`.
- Proof: Jest **76 suites / 506 pass / 1 skip** (baseline 71/486); tsc clean; `SKIP_WASM_BUILD=1` build green; dependency-boundaries green.


- Progress audit: foundation wave 2 closed; catalog ~1310; generative batch through #355;
  thumbs ~27%; WASM stay Tier B until real-GPU evidence.
- Filed epic #1076 and issues #1077–#1084 (base-url, thumbs, RendererManager, WASM
  promotion, multipass expansion, VJ 2.0, TS5 hygiene, generative queue).
- **#1077 shipped:** `prestart`/`prebuild` keep relative shader-list URLs; deploy uses
  `SHADER_LIST_BASE_URL`; CI `verify:shader-list-urls` enforces no accidental CDN drift.
- User preference reaffirmed: build foundation residual before huge content-only waves;
  multipass on TS GraphRunner; no C++ feature expansion until promotion decision.

## 2026-08-06 — Shader upgrade Batch 39 — FAST MOTION ENCORE

- Continued the smallest clean single-pass generative queue with Chrono Voronoi
  Mycelium, Singularity Forge, Obsidian Echo Chamber, Prismatic Aether Loom,
  Rainbow Firefly Dance, Cybernetic Liquid Chrome Engine, Magnetic Field Lines,
  and Bifurcation Diagram; tracker is now #355.
- Added shader-specific fast motion through smooth traveling particles,
  warp/conveyor cameras, velocity-stretched streaks, click events, and bounded
  field/derivative/history advection. Removed redundant raymarch and field-line
  loops while repairing control/audio/mouse truth and generated depth/A writes.
- 8/8 existing `updatedParams` exact; canonical bindings and 16x16x1 retained;
  no `extraBuffer` writes and `dataTextureB` stays unused.
- Proof: gate 8/8, focused extraBuffer and custom liveness checks clean, 421
  generative / 1,310 manifest entries, 1,323 unique IDs, Jest 478/1, and
  `SKIP_WASM_BUILD=1` build green. Report drift restored. The legacy dead-slider
  audit scans zero `updatedParams`-only controls, so custom x/y/z/w liveness is
  the cohort proof. Visual QA remains external.

## 2026-08-06 — Shader upgrade Batch 38 (4-agent swarm) — FAST MOTION batch

- User directive: add fast motion. Next 8 smallest: Sonoluminescent Chrono
  Geode Matrix, Abyssal Quantum Leviathan Skeleton, Eldritch Tesseract
  Hive-Mind, Stellar Web-Loom, Neon Plasma Biomechanical Hive, Sentient
  Aether-Flora Biosphere, Magnetic Dipole Field, Mycelium Network; tracker is
  now #347.
- Every shader gained ≥2 fast-motion techniques (closed-form orbitals/whip
  kinematics, warp-flight cameras, velocity-advected HDR-clamped trails,
  bass-transient kicks, speed streaks, time-warp easing, analytic dipole-line
  advection) under stability rules (clamped velocities, bounded feedback, no
  strobing, dt-based integration).
- Massive uniform-truth finds: geode's config scrambled as [resX,resY,time,
  aspect]; neon-plasma hive read all 4 sliders from zoom_config; flora's p1/p2
  never read; config.y-as-audio in 4 shaders. Coordinator caught vertically
  mirrored mouse gravity wells in geode + leviathan (camera-convention y
  mismatch; same class as b37 moth flip — now a standing review item).
- 8/8 updatedParams byte-exact; state only extraBuffer[133..138] single-writer.
- Proof: gate 8/8, audits PASS, generative list synced, manifest 1,310/1,310,
  Jest 478/1, SKIP_WASM_BUILD=1 build green, drift restored. Visual QA
  external. ~103 pending generative remain.

## 2026-08-06 — Shader upgrade Batch 37 (4-agent swarm)

- Same 4-agent pattern on the next 8 smallest pending generative shaders:
  Fireworks Fan Shell / Horse Tail / Ring Shell / Kamuro Gold, Symbiotic
  Cyber-Fungal Core-Reactor, Evolutionary Cellular Gardens, Chrono Kitsune
  Prism Weaver, Quantum Fluorescent Aether Moth Swarm; tracker is now #339.
- Fireworks-family normalized-pointer bug confirmed cohort-wide (yz-as-pixels);
  fixed config.y-as-audio in fungal/kitsune/moth, fungal's engine-owned
  zoom_config.w mutation slider, gardens' fake hash CA, moth's dead scatter +
  18-tap curl (→4-tap potential curl). Fungal gained 4 NEW indexed
  updatedParams (controls-dict schema; engine-owned control excluded).
- Coordinator caught a moth mouse y-flip (vertical mirror) post-swarm; fixed
  and re-gated. 7/7 pre-existing updatedParams byte-exact; state only
  extraBuffer[133..138] single-writer.
- Proof: gate 8/8, audits PASS, generative list synced, manifest 1,310/1,310
  (+1 = fungal qualifies), Jest 478/1, SKIP_WASM_BUILD=1 build green, drift
  restored. Visual QA external. ~111 pending generative remain.

## 2026-08-05 — Shader upgrade Batch 36 (4-agent swarm)

- Same 4-agent pattern on the next 8 smallest pending generative shaders:
  Cybernetic Ferro Coral, Thermal Rainbow Topography, Hyper Labyrinth,
  Topology Flow, Lichtenberg Storm, Phase-Transition Memory Weave, Luminescent
  Chrono-Fluid Astrolabe, Prismatic Void-Weaver Ouroboros; tracker is now #331.
- Repaired Astrolabe's completely scrambled uniform truth (time←config.z,
  audio←mouseDown), Ouroboros's fake rippleCount-audio + dead Twist Density,
  Topology Flow's unbounded ~15× feedback blowup, Thermal's top-left-pinned
  mouse, and cohort-wide missing A writes / far-is-one depth / hardcoded alpha.
- 8/8 updatedParams byte-exact; state only extraBuffer[133..138] single-writer.
- Proof: gate 8/8, audits PASS, generative list synced, manifest 1,309/1,309,
  Jest 478/1, SKIP_WASM_BUILD=1 build green, drift restored. Visual QA
  external. ~79 pending generative remain.

## 2026-08-05 — Shader upgrade Batch 35 (4-agent swarm)

- Full Algorithmist/Visualist/Interactivist/Optimizer swarm, 2 shaders each:
  Bioluminescent Cyber-Aether Void Seahorse, Velocity Bloom, Dragon Curve,
  Fractal Chrono-Dendrite Forge, Raptor Mini, Bismuth Singularity Loom Engine,
  3D Sierpinski Chaos, and Astro-Kinetic Chrono Orrery; tracker is now #323.
- Repaired Seahorse's non-canonical Uniforms struct, Bismuth's
  rippleCount-as-audio miswire, Orrery's 3 dead sliders + per-step Kepler
  hoisting, Sierpinski's filtering history read/flat depth, and gave
  Dendrite-forge 4 indexed updatedParams + 16x16x1 (stale unconsumed `controls`
  schema removed; effective defaults preserved). 7/7 pre-existing
  updatedParams byte-exact; state only extraBuffer[133..138] single-writer.
- Proof: focused gate 8/8, strict audits PASS, generative list synced
  (regenerate WITHOUT --base-url; build prebuild re-adds URL drift so re-sync
  after), manifest 1,309/1,309, Jest 478 pass / 1 skip, SKIP_WASM_BUILD=1
  build green, unrelated drift restored. Visual QA is a real-GPU handoff.
- Pending-pool recipe recorded in memory/2026-08-05.md (~87 generative remain).

## 2026-08-03 — Shader upgrade Batch 34

- The user immediately rolled into Batch 34, reinforcing the preference to
  continue directly through the clean pending generative queue. Completed
  Celestial Glass Tornado, String Theory, Voronoi Crystal, Chromodynamic Plasma
  Collider, Magnetic Ferrofluid, Psy Swirls, Audio Spirograph, and
  Bioluminescent Aether Pulsar; tracker is now #315.
- Fixed normalized-pointer-as-pixel mistakes, backward signed marching, missing
  A/depth writes, unguarded ripple ages/counts, filter-dependent C reads,
  inverted string energy glow, stub-only spirograph geometry, and Pulsar's
  generic control remapping.
- All eight now use bounded spring/click interaction, A as display history,
  generated relief/hit depth, exact saved control arrays, canonical bindings,
  and 16x16x1 workgroups. Persistent state stays in `extraBuffer[133..138]`.
- Focused gate 8/8, strict uniform/buffer/liveness/catalog audits, duplicate
  scan 1,320/1,320, Jest 478 pass / 1 skip, and production build all pass.
  Unrelated generated drift was restored; real-GPU visual QA remains external.

## 2026-08-03 — Shader upgrade Batch 33

- Completed a balanced hardening batch for Superfluid Quantum Foam, Cymatic
  Plasma Mandalas, Fractal Clockwork, Neuro-Kinetic Bloom, Nebular Chrono
  Astrolabe, Lenia 2, Graviton Plasma Lotus, and Silica Tsunami. Tracker is now
  #307.
- Added consistent spring/click interaction with persistent state restricted to
  `extraBuffer[133..138]`; corrected mouse/config semantics, unsafe math,
  workgroup drift, feedback reads, bounded raymarching, HDR output, and depth.
- Intentionally repaired Lenia's state ownership so C supplies prior species
  state, A receives the next state, and writeTexture stays presentation-only.
  Silica's refraction control now drives real IOR transmission.
- Exact saved updatedParams stayed intact. The focused gate is 8/8,
  strict uniform/buffer/liveness/catalog audits pass, duplicate scan is
  1,320/1,320, Jest is 478 pass / 1 skip, and the production build is green.
  Unrelated generated drift was restored; live visual QA remains external.

## 2026-08-03 — Shader upgrade Batches 31 and 32

- Resumed Kimi's interrupted generative-geometry swarm: coordinator-reviewed
  all 13 Batch 31 drafts and completed the five partial plus three missing Batch
  32 targets. Tracker is now #299.
- Cross-cutting fixes: canonical uniform meanings, plasmaBuffer[0]-only audio,
  guarded FFT access, non-filtering rgba32float feedback, defined falloffs,
  bounded ripple geometry, safe normalization, live controls, and consistent
  near-is-one depth. Existing saved-preset arrays stayed byte-equivalent; text
  metadata is additive and scientifically/descriptively honest.
- Batch 32 added budgeted attractor tubes, analytic IFS/monotile sculptures,
  raymarched cavern materials, interactive fluid geometry, and heightfield
  stained glass. Complete briefs and WGSL/JSON/MD output packages remain under
  the dated Kimi swarm directories.
- Final proof: explicit 21-file gate 21/21, strict extraBuffer and custom
  slider/JSON/list audits clean, 1,320 unique IDs, 1,307 manifest entries, Jest
  478 pass / 1 skip, and production build green. Unrelated generator/report
  drift was restored; visual QA remains external because the VM has no GPU.

## 2026-08-02 — Shader upgrade Batch 30

- Upgraded the next eight clean 120–122-line shaders: Gamma Ray Burst,
  Temporal Rift, Voxel Depth Sort, CRT Phosphor Decay, Infinite Spiral Zoom,
  Neon Poly Grid, X-Ray Reveal, and Color Channel Weave (tracker #271–278).
- Repaired runaway gamma math, missing bounds/border clamps, additive voxel
  shadows, two legacy 8x8 workgroups, Spiral's blue-channel angle alias, X-Ray
  softness/NaN issues, and Weave's reserved-zone audio bug.
- Standardized spring/click/FFT interaction with persistent state only in
  `[133..139]`; preserved source params and every raw/display feedback role.
- Focused gate/audits, generated catalogs, 1,319-ID duplicate scan, full Jest,
  and `SKIP_WASM_BUILD=1` production build all passed. VM GPU limitation leaves
  visual smoke to real hardware; unrelated generated/report state was preserved.

## 2026-08-02 — Shader upgrade Batch 29
- Continued the smallest-first clean single-pass queue with `sonic-boom`,
  `spectrum-bleed`, `anamorphic-caustic-flare`, `ascii-lens`, `digital-haze`,
  `heat-haze-mirage`, `interactive-film-burn`, and
  `porcelain-fracture-glow` (tracker #263–270; completed total 270).
- Fixed Spectrum Bleed's four controls reading time/mouse instead of
  `zoom_params`, its idempotent blur loop, Heat Haze's reserved-zone audio
  reads, ASCII Lens's missing A write/dead audio, and Digital Haze's dead
  density control. Added click launches, spring interaction, and FFT voices.
- Coordinator review repaired a missing bounds guard, an every-pixel persistent
  state race, ambiguous initialization, wrong click-shock direction, border
  samples, and unbounded event/HDR stacking. New state remains in
  `extraBuffer[133..138]`; raw temporal and mask/field feedback roles stay intact.
- Source params stayed exact; four indexed additive `updatedParams` and truthful
  feature/depth metadata match generated lists. Proof: focused gate 8/8 with
  zero warnings/buffer violations; dead-slider, strict-buffer, JSON/list audits
  clean; 1,319 unique IDs; 1,306 manifest entries; Jest 69 suites / 478 pass /
  1 skip; `SKIP_WASM_BUILD=1` production build green. Unrelated Physics Lab
  list drift and the existing WGSL report were restored byte-for-byte. Live
  WebGPU visual proof remains a real-hardware handoff.

## 2026-08-02 — Shader upgrade Batch 28
- Continued the smallest-first clean single-pass queue with
  `spec-importance-sampled-bokeh`, `chromatic-shockwave`, `film-cross-process`,
  `fluid-grid`, `infinite-video-feedback`, `pixel-storm`, `pixelation-drift`, and
  `silk-flow-advection` (tracker #255–262; completed total 262).
- Wired Chromatic Shockwave's dead Ring Count, corrected Fluid Grid's mislabeled
  controls, implemented Infinite Feedback's advertised mouse transform, made
  Pixelation Drift's mouse feature real, and activated Silk Flow's formerly
  write-only velocity history. Fixed missing bounds guards, displaced-sample
  safety, aspect-space transforms, exact-center math, and eager alpha division.
- All eight gained top-left-safe spring interaction, guarded click behavior, and
  regional FFT voices. Source params stayed exact; four indexed additive
  `updatedParams` and truthful feature/depth metadata propagated to generated
  lists. New persistent state remains in `extraBuffer[133..138]`; raw HDR,
  temporal display-history, and velocity feedback roles remain unchanged.
- Proof: focused Naga/bindgroup gate 8/8 with zero warnings/buffer violations;
  dead-slider, strict-buffer, JSON, and generated-list audits clean; 1,319 unique
  IDs; 1,306 manifest entries; Jest 69 suites / 478 pass / 1 skip;
  `SKIP_WASM_BUILD=1` production build green. Unrelated Physics Lab list drift
  and the pre-existing WGSL report were preserved byte-for-byte. Live WebGPU
  visual proof remains a real-hardware handoff.

## 2026-08-02 — Shader upgrade Batch 27
- Continued the smallest-first clean single-pass queue with `melting-oil`,
  `spec-iridescence-engine`, `spectral-waves`, `aero-chromatics`,
  `chroma-kinetic`, `cyber-trace`, `gen-chrono-erosion-feedback-melting`, and
  `quantum-flux` (tracker #247–254; completed total 254).
- Rewired three mislabeled Melting Oil sliders, three shaders that declared but
  never sampled audio, and Chrono Erosion's dead Feedback Mix. Added guarded
  click behavior, spring interaction, and regional FFT voices throughout.
- Coordinator review clamped Sobel border loads, fixed top-left initialization
  ambiguity, added the missing iridescence bounds guard, corrected aspect-space
  directions back into UV space, and bounded Cyber Trace's display emission with
  a hue-preserving soft knee while keeping raw clamp-2.0 history untouched.
- Source params stayed exact and each definition gained an indexed additive
  `updatedParams`; additive feature tags now match live audio/depth/temporal use.
  New persistent state remains in `extraBuffer[133..138]` and all feedback roles
  remain unchanged.
- Proof: focused Naga/bindgroup gate 8/8 with zero warnings/buffer violations;
  dead-slider, strict extraBuffer, JSON, and generated-list audits clean; 1,319
  unique IDs; 1,306 manifest entries; Jest 69 suites / 478 pass / 1 skip;
  `SKIP_WASM_BUILD=1` production build green. Unrelated Physics Lab list drift
  was removed and the pre-existing WGSL report preserved byte-for-byte. Live
  WebGPU visual proof remains a real-hardware handoff.

## 2026-08-02 — Shader upgrade Batch 26
- Continued the smallest-first clean single-pass queue with
  `temporal-frequency-decomposition`, `glass-wipes`, `interactive-zoom-blur`,
  `reality-tear`, `bubble-lens`, `cross-mouse-spec-dispersion-lens`,
  `laser-burn`, and `magnetic-luma-sort` (tracker #239–246; total 246).
- Core wins: wired Temporal Frequency Decomposition's previously dead mouse tag;
  corrected the prismatic crossover's elliptical lens; removed Magnetic Luma
  Sort's dead final-color experiment; wired formerly dead audio in Glass Wipes
  and Magnetic Luma Sort; added guarded click behavior and FFT voices throughout.
- Coordinator review replaced non-atomic every-pixel state stores in Temporal,
  Reality Tear, and Laser Burn with single-writer persistence, made top-left
  initialization explicit where position-zero sentinels were unsafe, and added
  a coarse cull before Bubble Lens satellite evaluations. New state remains in
  `extraBuffer[133..138]`; history binding 13 and all A/C state roles are intact.
- Source `params` stayed byte-equivalent; four indexed additive `updatedParams`
  were generated for each shader. Glass Wipes and Magnetic Luma Sort now carry
  truthful additive `audio-reactive` features.
- Proof: focused Naga/bindgroup gate 8/8 with zero warnings/buffer violations;
  dead-slider and JSON/list audits clean; 1,319 unique IDs; 1,306 manifest entries;
  Jest 69 suites / 478 pass / 1 skip; `SKIP_WASM_BUILD=1` production build green.
  Unrelated Physics Lab list drift and the pre-existing WGSL report were restored
  byte-for-byte. Live WebGPU visual proof remains a real-hardware handoff.

## 2026-08-02 — Shader upgrade Batch 25
- Continued the smallest-first all-category queue with `signal-tuner`,
  `fiber-optic-weave`, `hybrid-fractal-feedback`, `scan-slice`,
  `split-dimension`, `temporal-decay-multiresolution`, `paper-cutout`, and
  `rgb-delay-brush` (tracker #231–238; completed total 238).
- Major correctness repairs: Hybrid Fractal's four JSON controls now map to their
  named WGSL behaviors; unsafe 256-entry plasma palettes in Hybrid/Fiber were
  replaced by bounded procedural palettes plus valid FFT bins 1–8; Signal Tuner
  moved hidden origin state to safe persistent slots so A contains display RGBA
  everywhere; Paper Cutout accepts top-left mouse and now writes real relief.
- The history-ring effect now earns its mouse tag with a spring temporal lens and
  click echoes while preserving binding 13, its eight-layer indices, and read-only
  `extraBuffer[4]`. RGB Delay's scientific header is now explicitly a stylized,
  non-calibrated absorption model; its raw temporal A/C feedback stays intact.
- All eight gained guarded normalized click effects and meaningful regional FFT
  behavior. Source params stayed exact; indexed additive `updatedParams` were
  synchronized into generated lists. New state uses only [133..139].
- Proof: focused Naga/bindgroup gate 8/8 with zero warnings/buffer violations;
  dead-slider, extraBuffer, JSON, and generated-list audits clean; 1,319 unique
  IDs; 1,306 manifest entries; Jest 68 suites / 464 pass / 1 skip; production
  build green with `SKIP_WASM_BUILD=1`.
- Direct `tsx` again hit the known VM IPC `EPERM`; `node --import tsx` succeeded.
  The pre-existing WGSL report and unrelated simulation list were preserved
  byte-for-byte. Live WebGPU proof remains a real-hardware handoff.

## 2026-08-02 — Shader upgrade Batch 24
- Continued the smallest-first all-category queue with eight clean single-pass
  shaders: `quantum-tunnel-interactive`, `vhs-tracking-mouse`,
  `blueprint-reveal`, `cyber-grid-pulse`, `night-vision-scope`, `data-stream`,
  `glitch-slice-mirror`, and `knitted-fabric` (tracker #223–230).
- All eight gained spring-weighted interaction, guarded normalized click effects,
  and per-region FFT detail. Specific fixes include aspect-correct Data Stream
  wake, live treble characters, honest Night Vision depth, bounded HDR/emission,
  displaced depth sampling, and nonnegative click-slice intensity.
- Feedback truth held: Blueprint keeps raw temporal reveal state in A; Knitted
  Fabric moved display RGBA to host-primary A and diagnostic masks to B. All new
  persistent writes are confined to `extraBuffer[133..138]`.
- Source parameter IDs/defaults/ranges/steps stayed exact. Each definition gained
  indexed additive `updatedParams`; truthful click/depth metadata was added.
- Proof: focused Naga/bindgroup gate 8/8 with zero warnings/buffer violations;
  no dead sliders; 1,319 unique IDs; 1,306 manifest entries; Jest 68 suites / 464
  pass / 1 skip; production builds green with `SKIP_WASM_BUILD=1`. Direct `tsx`
  hit the known VM IPC `EPERM`; `node --import tsx` rebuilt the manifest.
- Live WebGPU visual/thumbnail QA remains external because this VM has no adapter.
  Pre-existing Batch 23 work and WGSL report bytes were preserved; unrelated
  Physics Lab simulation-list drift was removed byte-for-byte.

## 2026-08-01 — Shader upgrade Batch 23
- Eight upgrades shipped locally: `gen-fireworks-roman-candle`,
  `gen-zeta-function-landscape`, `gen-bioluminescent-reaction-diffusion`,
  `gen-cycloid-bloom`, `crt-scanline-damage`, `steampunk-gear-lens`,
  `fireworks-depth-parade`, and `fractal-noise-dissolve` (tracker #215–222).
- Key correctness wins: normalized pointer fixes in the fireworks family,
  eta-based zeta continuation, boundary-safe RD stencil + valid FFT bins 1–8,
  no Steampunk double mask, honest relief/shell/luminance depth, and bounded
  Fractal burn emission. Cycloid search dropped 1,205→360 tests/pixel.
- Contracts held: image source `params` and generative `updatedParams` unchanged;
  four image `updatedParams` added; only Depth Parade gained `supportsDepth`;
  RD keeps raw state in A; other A/B feedback roles unchanged; new state uses
  only `extraBuffer[133..138]`.
- Verification: 8/8 focused Naga/bindgroup gate, zero workgroup warnings and
  buffer/dead-slider violations, 1,319 unique IDs, Jest 464 pass / 1 skip, and
  `SKIP_WASM_BUILD=1` production build green. Real-GPU visual QA remains external.

## 2026-08-01 — WebGPU frame split (#1043)
- `src/renderer/webgpu/frame.ts` is now a **194 LOC** lifecycle facade (down from 873): RAF/media refresh, uniform writes, history-ring advancement, FPS, and top-level timing.
- New seams: `frameState.ts` for renderer-owned state adapters, `present.ts` for input scale/copy + canvas acquire/blit/submit, and `slotDispatch.ts` for parallel/chained/GraphRunner dispatch, quality caps, feedback copies, and compute timestamp phases.
- Contract stays fixed: when feedback uses both storage buffers, copy **B→C first, A→C last** so primary simulation state wins. The older pure `slotOrchestrator` model now agrees.
- Pure tests cover copy order, graph-vs-linear resolution, graph quality caps, blit cache invalidation, and generative present selection.
- Green proof: 68 Jest suites / 464 pass / 1 skip, TypeScript, focused ESLint, device + uniform policy sync, production CRA build, and 254.49 KiB gzip main bundle under 320 KiB.
- VM workaround: direct `tsx` may fail with `listen EPERM`; use `node --import tsx scripts/build-unified-manifest.ts`, then `npm run build --ignore-scripts` after lifecycle generation. Real GPU visual QA remains external.

## 2026-08-01 — Toolchain foundation (#1042)
- Phase 0 + low-risk Phase 1 guardrails landed locally: 320 KiB gzip main-chunk CI budget, explicit lazy `auto-dj` / `transformers` / `web-llm` checks, direct/alias dependency duplicate protection, and AI-loader source boundaries.
- Fresh baseline: main ~251.43 KiB gzip; Transformers ~175.76 KiB and WebLLM ~2,090.61 KiB remain excluded lazy chunks.
- Package/lock were already TypeScript 5.4.5; local install was stale at 4.9.5. After `npm ci`, `npx tsc --noEmit` passes with two narrow test-fixture typing updates.
- CRA 5's stale peer metadata still lists TypeScript only through 4.x (`npm ls` marks 5.4.5 invalid), but locked TS 5.4.5 passes both full typecheck and CRA/craco build. CI now runs the real typecheck; Vite remains the long-term peer-mismatch exit.
- `public/wasm/` is explicitly documented as the only deployable WASM artifact SoT; bridge source remains `wasm_renderer/bridge/*.js`. Device initialization was not changed.
- Removed tracked root junk `a.out.wasm`, `upg.zip`, `patch_wasm_final16.js`, and `fix_eslint2.py` (Git-recoverable). CRA→Vite remains a separate optional spike.
- Green proof: production build, 64 Jest suites / 428 pass / 1 skip, TypeScript 5.4 typecheck, device-policy sync, WASM validation, bundle/dependency gate, diff check.

## 2026-08-01 — Branch consolidation
- Audited all local/remote alternate branches vs `main`. Nearly everything useful was already merged (foundation waves, relay hops, MIDI, CORS/blank-after-scale, shader plans/impls).
- **Imported into main** (`0a74d08a`): celestial-lion + void-urchin plan files + queue pending entries (only unique orphans).
- **Closed junk PRs:** #995 (stale midi), #1020 (moth 397-file rewrite), #1053 (urchin draft after landing).
- **Deleted** all non-main local + remote branches and foundation worktrees. Repo is main-only.
- Left uncommitted Batch 21 WIP alone (moire / mouse-gravity / fireworks-edge-ignite).

## 2026-07-29 — Progress audit & next foundation wave
- **Board was empty** (July 26 closed #1007–#1031 tooling/content campaigns). Created **7 open issues** for next code foundation + product:
  - #1038 Uniforms SoT (`config.y` = **rippleCount**, not delta_time in agent docs)
  - #1043 finish `frame.ts` modularization (present/blit/slot dispatch)
  - #1039 real-GPU format-tier + multipass budget evidence
  - #1040 WASM Tier A go/no-go on discrete GPUs (stay B until then)
  - #1044 thumbs 27% → 80% (GPU waves; tooling already done)
  - #1041 multipass physics polish (ripple/fabric/caustics discoverability)
  - #1042 toolchain: TS upgrade, bundle budget, optional CRA→Vite
- **Strategic call:** foundation first (#1038, #1043) before another generative swarm; content flagship = multipass polish not more single-pass volume; WASM feature freeze until #1040.
- **Health at audit time:** device policy sync OK; format tiers in tree; dual Storage re-exports only; package dual-deps cleaned. Root junk noted here was removed by the 2026-08-01 toolchain pass above.


## WGSL cross-cutting improvements (2026-07-12 audit)
- **Engine wins (all shaders):** gate historyTex copy (only 11 use binding 13); reuse extraBuffer Float32Array; fix dataTexA/B→C double-copy in chained slots; merge queue submits; GPU image upload path.
- **Mouse Y convention (2026-07-19):** Removed erroneous `1.0 - y` flip in `WebGPURenderer.updateMouse` — `zoom_config.yz` is now canvas UV (0=top, 1=bottom), matching WASM + `WGSL_BUILTINS_GENERATIVE.md`. Patched ~70 WGSL files that had compensating `1.0 - zoom_config.z` / `1.0 - mouseUV.y` / `(0.5 - mouse.y)` flips. Script: `scripts/fix_mouse_y_compensation.py`.
- **Subgroup infra:** `-sg.wgsl` variant loader removed 2026-07-26; subgroup **feature** still requested when available for inline `enable subgroups` WGSL. TS timestamp-query **wired 2026-07-26** (feature request + ring-buffered readback + honesty gate `hasRealGpuTimings`).
- **Live rating API (2026-07-22):** `POST /api/shaders/{id}/rate` wants JSON `{ rating }` not FormData `{ stars }`. No `/api/shaders/{id}/play` on production. Use `postShaderRating()`.
- **Format tradeoff:** rgba32float pipeline is quality-correct for HDR/sim but 4× bandwidth — don't downgrade without tiering.

**Last updated (prior):** 2026-07-11 (Epic #912 foundation hardening in flight)

## Core Identity & Vibe (from SOUL + IDENTITY)
- Spark Engine / Cheerleader: bright, protective, kinetic, loud-hearted. "We are NOT done here!" Fast, punchy, energetic. Use "we/let's", 🔥⚡💥🫡, short lines, "one thing first", "messy start? fine", "this is NOT the final boss".
- Never fake slogans. Protect morale + motion. Turn "impossible" into sequence. Remember comeback history.

## User (from USER.md + consolidation + this work)
- Developer (ford442) on github.com/ford442/image_video_effects (WebGPU shader effects app, "Pixelocity").
- Iterative builder, focused sessions on shaders (generative, upgrades, swarm agents using WGSL_BUILTINS etc).
- Values: ship-ready, self-evident systems, canonical refs, clean output over "mostly works". Uses AI as peer ("you do X, I'll do Y").
- Recent focus (from 2026-06): shader swarms, generative, image suggestions, and now hardening the C++ WASM renderer path (long investment, currently not loading reliably).
- Communication: enthusiastic shorthand + technical, approval like "pure gold" when matches.

## Project Context - WASM Renderer (C++)
**Investment:** Multi-phase (2026-03 to now). Advanced compute: multi-slot (chained/parallel), ping-pong, depth, 3-band audio (extra+plasma), RAII WGPUHandle, async capture/readback, workgroup parse, device-lost/uncaptured callbacks, universal 13-bind layout matching all WGSL shaders.
- main.cpp: EM_KEEPALIVE exports, thin bridge to g_renderer.
- renderer.cpp/h: full WebGPURenderer (Initialize/CreateDevice with 4-attempt powerPref ladder + WaitAny+ASYNCIFY for emdawn, CreateResources for 2048² rgba32f + r32 depth + data A/B/C + buffers, bind layout, render pipeline for present blit, LoadShader+parse wg size, Render multi-submit per slot + feedback, PresentToSurface with acquire+BeginRenderPass+draw+present, Recreate on resize, BeginFrameCapture mapAsync etc).
- Has presentation now (Render calls PresentToSurface at 1725).
- JS side: wasm_bridge (newer in wasm_renderer/, stale copy in src/wasm/), WASMRenderer.ts wrapper, RendererManager forwards (now has WASM branches).

- **Current Reality (2026-06-16):**
- **Init/format/limits handshake hardened** (#817–#822 ✅ in tree). Presentation wired (`PresentToSurface` at 1725).
- **Still not drop-in:** live edge-GPU verification; `setInputSource` app wiring partially done (WebGPUCanvas + resync on switch).
- **Phase 1 glue (2026-06-20):** RendererManager duck-typed shader forwarding, `syncAllSlotParams`, `resyncShaderStack` on backend switch, normalized `ShaderSlotRenderer` API, unit tests.
- **Phase 3 parity (2026-06-20):** WASM path now exposes `updateAudioFrequencyBins`, aggregate `updateSlotParams`, `getSlotState`, `getGPUTimings`, `getSupportsDeepWorkgroup`, `setRecording`, `getFrameImage`/`refreshFrameImage` via C++ + bridge + RendererManager. GPU timings are CPU wall-clock only (`available: false`).
- **Build:** CI `wasm` job builds + validates + Jest smoke; `build.sh` fails without emcc unless `SKIP_WASM_BUILD=1`.

**User directive this session:** Solidify/complete the *C++ code*. Specifically call out that "we can check if we've chosen good webgpu settings for the context via c++" → move adapter/device/surface/limits/format decisions + validation into C++ side, expose/report.

## Decisions / Lessons (write down or they vanish)
- Always keep single source of truth for bridge wrappers; copy step in build for both glue + wrapper.
- For WASM + Dawn + browser WebGPU: context ownership, format negotiation, compatibleSurface, and explicit limits are first-class reliability concerns, not afterthoughts.
- "Works in C++ compute" != "loads and presents reliably cross browser/GPU". The last mile is the surface + init handshake.
- Update GAP/STATUS aggressively when code evolves (present path landed after May doc).
- Use GH issues + Copilot for the C++ work (user has swarm/agent patterns elsewhere).

## Epic #912 — Foundation hardening (2026-07-11)
- **Strategic call:** 1–2 cycles of structure before next shader swarm. Content (#897 fireworks) ships in parallel.
- **Three waves done locally:** W1 (#919/#918/#931 build+docs), W2 (#915/#917/#920 limits+catalog+ES2020), W3 (#913/#914 App/Controls split) — PR #938 open for W3 only; W1/W2 branches not pushed yet.
- **Current branch:** `feat/midi-control-and-wasm-parity` (PR #936) — orthogonal to foundation; merge foundation first or rebase MIDI after.
- **Still open in epic:** #917 full orphan reconcile, #921 thumbnail pipeline (GPU), #916 renderer.cpp modularize, product epics (#922/#929) deferred per epic scope.
- **Success criteria:** 4/6 have code on foundation branches; thumbnails + full god-component split remain partial.

## Foundation Wave 2 — Post-#912 (#965, 2026-07-19)
- **App strangler (#966):** `App.tsx` 2,207 → **562 LOC**; all hooks wired; overlays in `AppOverlays.tsx`; constants from `src/app/constants/`.
- **WebGPU modularization (#967):** `WebGPUDeviceInit`, `WebGPUResourceManager`, `WebGPUShaderManager`, `WebGPUTiming` wired; monolith ~1,390 LOC (render loop + blit scale path still inline).
- **Binding + device policy (#968/#969):** `docs/BINDING_CONTRACT.md`; binding 13 (`historyTexture`) in C++ pipeline/resources/frame; `maxBindingsPerBindGroup` 14; `npm run verify:device-policy`.
- **Multipass graph (#970):** `docs/MULTIPASS_GRAPH_SPEC.md`, `multipassGraph.ts`, `GraphRunner.ts`; wired in `dispatchSlot()` for `quantum-foam-pass1` same-frame demo.
- **Thumbnails (#921):** `npm run thumbs:generate -- --missing` (app engine, production build); `thumbs:status`; docs/THUMBNAIL_PIPELINE.md; CI workflow_dispatch; failure report with black_frame/compile; **346/1,302 (26.6%)** — GPU batch on real hardware.
- **WASM promotion (#890 / #965):** **STAY TIER B** reaffirmed 2026-07-19; bench harness polish (adapter summaries, CI artifact); `reports/wasm-promotion-evidence-2026-07-19.md`; issue comment posted. GPU gates still open — human discrete-GPU runs required.
- **Controls panel closeout (#914 residual):** `useShaderMenuOptions`, `useAiVjAutoTransition`; production `RendererToggle`/`WASMToggle` removed; StorageBrowser via `storage/` imports.
- **Tests/build:** 274 Jest tests pass; `SKIP_WASM_BUILD=1 npm run build` green (WASM also compiles when emcc present).

## Epic: Advanced Physics & Multipass Sims (2026-07-11)
- **Agent kit:** `swarm-tasks/advanced-physics/` — README, MULTIPASS_SIM_CONTRACT, 3 agent specs + stretch goals
- **Tier gate:** A/B ship now (linear multipass + frame feedback); Tier C (graph runner #929) blocks heavy iterative solvers
- **Priority:** ripple-tank multipass → fabric-of-reality → caustic accumulator
- **Prototypes exist:** `wave-equation`, `photonic-caustics` (single-pass); `fabric-of-reality` greenfield
- **Preamble for swarms:** `agents/WGSL_BUILTINS_GENERATIVE.md` + MULTIPASS_SIM_CONTRACT.md

## WASM Tier B → A evidence (2026-07-19)

- Bench report schema: `benchmarkShaderIds`, `wasmAdapterSummary`, `webgpuAdapterSummary`, `userAgent`
- `__pixelocity__.getAdapterSummary()` in testMode; CI uploads `wasm-benchmark-report` artifact
- VM run: `gpuBackendObserved: false` → `reports/wasm-benchmark-report-stub-2026-07-19.json`
- Parity: 7/7 skipped (no WebGPU adapter); Gate 3 manual smoke blocked in VM
- Gate 4: W29 partial — `wasm` green, `test-wasm-e2e` skipped (`test` failing on main)
- Decision comment: https://github.com/ford442/image_video_effects/issues/965#issuecomment-5014449092

## WASM Tier B → A evidence (2026-07-11)
- **Decision: STAY TIER B** — no GPU benchmark/parity evidence; 4-week CI ops gate not met
- Created `WASM_PROMOTION_TRACKING.md` + `reports/wasm-promotion-evidence-2026-07-11.md`
- Stub `test-results/wasm-benchmark-report.json` (gpuBackendObserved: false)
- Local: `test:wasm:unit` 29/29 pass; Playwright blocked (no GPU VM; branch build TS2352)
- CI note: `test-wasm-e2e` green on ubuntu-latest skips GPU-dependent specs

- **2026-07-11:** WASM GPU timestamp queries when `timestamp-query` feature supported (`timing.cpp`); wall-clock fallback otherwise.

## TODOs / Open Threads (from this + recent memory)
- [ ] **Shader scan cleanup (2026-07-11):** 95 scan errors fixed in code (fetch fallback, subgroups device, filter test junk). Optional: `sync_shaders_to_1ink.py --ids-file scripts/shader_scan_fix_list.txt` for 88 CDN 404s.
- [ ] **Shader upgrade mission (2026-06-28):** Upgrade batches of Pixelocity WGSL shaders to the immutable 13-binding contract, including standard `Uniforms`, `rgba32float` storage writes, depth/data/audio bindings, 16x16x1 workgroups, aspect-correct UVs, four `updatedParams`, feature metadata, generator validation, and batch commits.
- [x] Created GH issues 817-823 (2026-06-11) for C++ solidification. All C++-centric, reference #799 + specific source lines.
- [x] Updated issue bodies 2026-06-14: moved Claude's implementation sketches from comments into structured task sections (Prerequisites, Implementation Instructions, Task Checklist). PR order: #821 → #818+#820 → #817+#819 → #822 → #823.
- [x] Bridge skew fix (2026-06-16): `wasm_renderer/wasm_bridge.js` is SOT; build.sh copies to both paths; validate guard; `getDiagnostics()` synced.
- [x] Unified error paths (#822, 2026-06-16): bridge merges C++ stage/message into diagnostics.
- [x] Bridge sync (#821, 2026-06-16): canonical `wasm_renderer/wasm_bridge.js` synced to `src/wasm/` + validator guard.
- [x] WASM docs refresh (#823, 2026-06-16): GAP_ANALYSIS, STATUS, README, WASM_*.md — presentation corrected, #817–#822 tracking table, #799 roadmap link.
- [x] RendererManager WASM forwarding + resync on switch (Phase 1, 2026-06-20).
- [ ] App-level `setInputSource` everywhere + live edge-GPU verification.
- [x] Phase 2 CI/build hygiene (2026-06-27): build.sh fails without emcc; CI artifact pipeline; ARTIFACTS.md
- [x] Phase 3 WASM test suite (2026-06-27): parity matrix, benchmarks, hot-reload, WASM_TEST_SUITE.md
- [x] **Product decision Tier B (2026-06-27):** WASM = experimental opt-in; TS WebGPU = production default. Policy: `WASM_BACKEND_POLICY.md`
- Memory maintenance: review recent daily (06-07 had swarm, git sync); distill only high-signal (C++ reliability is now key infra bet).

## Build & tooling hardening (#965, 2026-07-19)
- `src/contracts/webgpu_limits.json` — shared limits SOT; Jest `webgpuLimitsContract.test.ts`; `verify:device-policy` reads JSON
- INITIAL_MEMORY 64 MiB experiment: **reject** (no wasm size win); ASYNCIFY **+40 KiB wasm** documented in `BUILD_FLAG_EXPERIMENTS.md`
- `measure_wasm_build_flags.sh` for reproducible flag comparisons
- PR template checklist includes `wasm:validate`; CMake marked CI-off-limits
- `docs/TOOLCHAIN_DECISION.md`: **stay CRA + CRACO** (Vite spike deferred); **TS 5.4.5 landed** (#1083, Aug 2026)

## Toolchain truth pass (#1076 / #1083, 2026-08-15)
- **Decision recorded:** TypeScript 5.4.5 on CRA 5 + CRACO 7 — not blocked; only CRA peer-metadata noise (`npm ls typescript` invalid peer).
- **Docs:** `TOOLCHAIN_DECISION.md` decision log + dependency boundaries; README toolchain command matrix; `npm run typecheck`.
- **Cleanup:** removed `BaseRenderer.ts`, root Storage UI shims, `getStorageService` aliases; `StorageService.ts` facade kept.
- **Vite:** deferred per revisit triggers (TS 5 prerequisite satisfied).
- **Green:** typecheck, verify:device-policy, verify:uniforms, 513 Jest pass, SKIP_WASM_BUILD build, verify:toolchain-foundation (~258 KiB main gzip).
- **No collateral:** device-init policy and feedback B→C / A→C copy order untouched.

- Multi-agent shader relay experiment: `gen-relay-psychedelia` in generative category
- CHUNK-based ownership (domain-warp, symmetry, palette, feedback, motion) — see `agents/RELAY_PROTOCOL.md`
- Hop 0 spine done; hop 1 (recursive domain warp) prompt at `agents/swarm-tasks/prompts/relay-hop-1-domain-warp.md`
- Validation between hops: `python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-relay-psychedelia.wgsl`

## Progress audit 2026-07-22 — next moves

**Foundation vs content:** Wave 2 structure is good enough to ship product/content in parallel. Prioritize:
1. Small engine fixes (#1007 timestamp-query TS parity) before honest benches
2. Content: generative updatedParams (#1011), multipass physics on existing GraphRunner (#1009), thumbs on real GPU (#1012)
3. Hygiene: bundle/AI lazy load (#1010), WASM evidence when discrete GPU available (#1013)
4. Larger architecture: format tiering (#1008) before mobile-quality multipass

**Created issues:** #1007–#1013. Existing open: #976 attract/importer, #983/#984 gate (likely mostly done — verify before more work).

**Stale notes corrected:** CommunityGallery is mounted in `AiVjStudioPanel`; weekly_plan "unmounted" is outdated.

## Quick Refs (for continuity)
- Key files: wasm_renderer/{renderer.cpp:242 CreateDevice, 658 format negotiation, 669 fatal surface, 1595 Render, 1725 PresentToSurface}, wasm_renderer/wasm_bridge.js (canonical, synced to src/wasm/), src/renderer/{WASMRenderer.ts,RendererManager.ts}, WASM_RENDERER_GAP_ANALYSIS.md, wasm_renderer/STATUS.md
- GH: #799 (open, context init), #771 (closed windows), #736 (closed testing).
- Build: `cd wasm_renderer && ./build.sh` (needs emsdk); `npm run wasm:build`
- Test: `?renderer=wasm`, `window.__rendererManager?.getDiagnostics()`, switchRenderer in console.
- Soul line: "i am here to help you get back in the fight!" — for the C++ path, we're turning the loading screen into a win.

**Capture principle:** All this written down immediately. Future sessions read this + today's daily before touching WASM C++.

(If consolidating older: 06-07 swarm details in its daily; only kept the "C++ WASM now the reliability focus" signal here.)

## Liquid shader upgrade batch (2026-07-21)
- Codex completed a Kimi-disjoint lane covering eight legacy `liquid-*` shaders.
- Batch contract: exact 13 bindings, 16x16x1 workgroups, all four `zoom_params`, bounded
  plasma audio, meaningful alpha/depth, `dataTextureA`, metadata synchronization, and
  stable parameter IDs/defaults/ranges for saved-preset compatibility.
- Target gate passed 8/8 and production build succeeded. The authoritative scan found four
  unrelated committed generative failures; do not attribute those to the liquid batch.

## Generative upgrade swarm — Batch 10 (2026-07-22)
- 8 smallest generative shaders with empty `updatedParams` (pool: 99 → 91 remain).
- Theme: wire `updatedParams` from EXISTING JSON params (preset contract — no renames),
  rewire boilerplate slider mappings to shader-specific constants, +2–3 techniques, +50–90 lines.
- 8/8 gate green first-pass, Jest 332, tracker #111–118. Briefs generator: temp/make_briefs_2026_07_22.py.
- Repo trivia: root `swarm-outputs`/`swarm-tasks` are symlinks into agents/.

## Generative upgrade swarm — Batch 12 (2026-07-22)
- 8 more (calligraphic-weave, bubble-chamber, turing-veins, molten-gold,
  phase-memory-weave, atmos_fog, mycelium, julia_set). Pool ~67 remain. Tracker #127–134.
- 🔴 **extraBuffer index map (PERMANENT LESSON):** [0..4] reserved, **[5..132] = engine FFT
  bins (stomped every audio frame)**, [133..255] = safe persistent state. 9 shaders from
  Batches 10–12 remapped post-hoc. Documented in agents/WGSL_BUILTINS_GENERATIVE.md.
  Future briefs: "use [133..255]", never "[5]+".
- turing-veins had 4 dead sliders (JSON params, no WGSL reads) — check for this pattern.

## Generative upgrade swarm — Batch 11 (2026-07-22)
- Next 8 (gen_cyclic_automaton, holographic_interference, holographic-crystal,
  gen_wave_equation, plasma-orb, plasma-jet-stream, sacred-geometry-torus,
  acoustic-string-theory). Pool ~76 remain. Tracker #119–126, Jest 332.
- 🐞 gen_wave_equation feedback bug FIXED (state→dataTextureA). Revived dead sliders
  (arcChaos, depthWeight). gen_capabilities intentionally skipped (system-monitor demo).

## WGSL audit fix swarm (2026-07-21) — complete
- Batch 9 upgrade swarm (8 shaders) closed earlier same day; liquid batch disjoint.
- Audit → fix agents 1–5: naga 4-pack, boids/flock feedback rewrite + entry-aware workgroup
  parser, reserved extraBuffer[0..4] gate, **dataA primary feedback (B then A copy)**, logic
  one-liners + guided-filter `/count`. Reports under `reports/audit-2026-07-21/fix-*.md`.
- Host contract: when both dataA and dataB are written, **A→C last** so sim state wins.
- Optional backlog: mechanical gid-guard for ~220 files; deeper agent-sim races (pixel-sand).

## Generative upgrade swarm — Batch 14 recovery (2026-07-22)
- Kimi completed shader/JSON edits for all 8 targets but stopped before the
  `spore-galaxy` note and integration closeout. Codex recovered and closed the batch.
- Targets: gen-bioelectric-pulse, gen_grok4_life, gen_reaction_diffusion,
  gravito-phononic-accretion, neural-mandala, phosphorescent-jellyfish, spore-galaxy,
  topological-acoustic-knots. Tracker entries #143–150; completed count now 150.
- Gate 8/8 green; JSON contracts preserved; shader lists and 1310-ID duplicate check clean;
  Jest 49 suites / 339 pass / 1 skip.
- Full Naga scan is 1314/1315. The only failure is unrelated/unmodified
  `gen-luminescent-aether-plasma-astro-axolotl.wgsl` (`invalid left-hand side of assignment`).
- `spore-galaxy` feedback fix is important: color now writes dataTextureA (host copies A→C
  last), masks write dataTextureB, enabling real color trails instead of mask-as-color feedback.
- No live visual QA in the headless VM; use real WebGPU hardware for look/slider tuning.

## Psychedelic generator encore — Batch 46 (2026-08-10)

- Tracker #395–406 covers a second visual-layer pass on the six Batch 45 generators plus six registry-pending complex generative shaders: Gravitational Strain, Holographic Data Core, Art Deco Sky, Ethereal Anemone Bloom, Liquid-Crystal Hive-Mind, and Celestial Prism-Orchid.
- Preserve exact `params` and `updatedParams` arrays even when complex definitions expose only `updatedParams`. Gravitational Strain and Hive-Mind own A as state; the other ten use A/C display history; B and `extraBuffer` remain unused.
- Useful fixes: smooth analytic scan packets replaced Holographic frame hashes; Orchid normalized mouse X no longer divides by resolution and its center direction is safe; Art Deco/Hive C reads are exact loads; all click loops cap at 50.
- Structural proof: Naga/bind-group and schema-aware contract audits 12/12, Jest 77/77 suites, production build green. The manifest retains seven unrelated baseline leading-slash URLs; real-GPU visual/performance QA remains external.

## Thumbnail coverage — corrected August 2026 baseline

- Nominal: **349/1,306 (26.7%)**; eligible: 1,305 after the justified `deep-workgroup-multi-effect-blend` hardware skip.
- The old Python PNG audit did not reverse row filters and over-reported failures. Correct decoding identifies **77 genuinely black thumbnails**, making healthy eligible coverage **272/1,305 (20.8%)** and the honest 80% backlog **772**.
- Always audit and force-regenerate invalid existing PNGs before `--missing` waves. Priority order: generative, simulation multipass, interactive-mouse, then remaining categories.
- Do not allowlist renderable failures to improve the denominator. CI remains reporting-only until healthy coverage reaches at least 50%.
- The current Cloud VM's production WebGPU probe produced a zero-energy frame, so batch generation requires a verified discrete-GPU host. See `reports/thumbnail-coverage-2026-08.md`.

## Thumbnail foundation wave — #1076 (2026-08-15)

- Confirmed the app engine is the full-catalog/multipass path and constrained the
  minimal engine/package command to generative-only captures.
- Added `thumbs:check-regression`, a PR check that compares healthy coverage with
  the base git ref and fails new shader definitions without healthy PNGs.
- `thumbs:status` now reports curated attract + Physics Lab priority coverage and
  accepts `--require-priority` for GPU-workstation enforcement.
- Current VM proof: nominal 349/1,324 (26.4%), healthy 272/1,323 (20.6%),
  priority 20/21 (95.2%); capture remains blocked until discrete-GPU access.

## Shader upgrade Batches 53–54 (2026-08-21)

- Tracker #455–470 is complete in two sequential, independently gated cohorts:
  Batch 53 Fast Motion Encore and Batch 54 Psychedelic Upgrade. Preserve their
  closeouts separately when auditing or reporting.
- Batch 54's intentional contract repairs are Tile Twist A
  `[bassEnvelope, trailRGB]` plus corrected Tile Size/Twist mapping, and Polar
  Warp A `[bassEnvelope, mouseX, mouseY, alpha]` with no RGB-history read. B is
  unused throughout Batch 54; no extraBuffer access was introduced.
- Current committed baseline has malformed
  `shader_definitions/generative/gen-chrono-kinetic-fractal-engine.json`.
  Generators skip it and Jest catalog hygiene fails on it; do not attribute that
  pre-existing defect to Batches 53, 54, or 55. Structural/build gates pass, but
  psychedelic identity and motion/trail acceptance still require a real GPU.

## Shader upgrade Batch 55 (2026-08-21)

- Tracker #471–474: Kaleido-Scope Prism grokcf1, RGB Topology, Elastic Strip,
  Refraction Tunnel. Geometry detail + fast motion + psychedelic color.
- Kaleido 8x8→16x16; origin A `[env, springXY, vel]`; topology mask A
  preserved; B unused; no extraBuffer writes. Tunnel no longer uses
  `floor(time)` hash caustics.
- Structural proof 4/4; visual QA remains real-GPU workstation work.
## Generative-only ten-shader cohort (2026-08-23)

- Preserve the exact ten IDs and their distinct models: chronal maze/monolith,
  Conway CA, coral colony, Dyson clockwork, slime mold, velvet hypnosis, cosmic
  web, cryogenic matrix, and crystal caverns.
- All ten now use bindings 0–12, ACES, semantic alpha, exact C, A-only state,
  and plasma XYZ. Persistent scalar/spring state is absent or confined to
  `extraBuffer[133..138]`.
- Every definition exposes four truthful named `params`; Dyson's labels match
  Mechanical Complexity, Clock Speed, Plasma Intensity, and Gear Ratio.
- Important repairs: Conway declaration order; Cryogenic state slot and A
  writeback; Monolith/Coral/Slime filtered C; Dyson missing C/ACES; Crystal
  Purity wiring. Structural, catalog, Jest, and build gates pass; GPU QA remains
  external.

## Eldritch / emergent / ethereal generative cohort (2026-08-23)

- Ten verified live generative IDs now meet the canonical bindings 0–12,
  ACES, semantic-alpha, exact-C, A-only, plasma-XYZ contract with 40 truthful
  named controls.
- Preserve Script Gardens A.a as ink occupancy. Owl, Manta, Hummingbird,
  Kaleidoscope, Erosion, Orchid, Anemone and calligraphic effects own HDR or
  display history in A; Eldritch A.a remains generated depth.
- Important repairs: no filtered C; Owl no longer reads engine FFT bins through
  extraBuffer; Manta/Hummingbird no longer treat rippleCount as audio;
  Hummingbird gained its missing ACES/C/A/semantic-alpha path.
- Focused Naga/contract/dead-slider gates, catalogs, duplicates, URLs, Jest and
  canonical build pass. Real-GPU visual/performance acceptance remains external.

## Fireworks / atmospheric / fractal generative cohort (2026-08-23)

- Ring Shell, Roman Candle, Smoke Bloom, Strobe Shell, Willow Cascade, Wind
  Ripple, Fluffy Raincloud, Fourier Epicycles, Spore Network, and Chrono
  Dendrite Forge now satisfy the bindings 0–12, ACES, semantic-alpha, exact-C,
  A-only, plasma-XYZ contract with 40 named controls.
- Preserve Raincloud raw A packing `[density,vx,vy,moisture]` and Fourier packed
  `[bass envelope,trail R,trail G,alpha]`; all B writebacks are intentionally
  absent. Raincloud alone uses extraBuffer state, bounded to `[133..136]`.
- Important repairs: `gen-fluffy-raincloud` uses the underscore WGSL/JSON path;
  its WGSL time wrap must not use unsupported `mod()`. Smoke bloom uses exact
  five-tap C bloom; Chrono must not read engine FFT slots; Spore and Chrono now
  have exact-load history and bounded click rings. Naga/Jest/build pass; GPU QA
  remains external.

## Reaction / flow / sand / optical-fluid cohort (2026-08-23)

- Ten selected simulation shaders now obey bindings 0–12, exact C, A-only
  feedback, ACES display, semantic alpha, live plasma XYZ, full interaction,
  and byte-exact saved params. All active WGSL passes are Naga-clean.
- Optical Flow Dream deliberately changed from a binding-13 four-pass graph to
  a canonical single-pass exact-history effect; update graph/badge/docs/tests
  together if this ownership changes again. Pixel Sand deliberately migrated
  its raw density/velocity/energy state from B to authoritative A.
- Structural proof is green through Jest/build; visual and performance QA still
  requires real WebGPU hardware.

## Ethereal generative cohort (Batch 72, 2026-08-23)

- The phoenix, void whale/dragon, glass flora, hologram bonsai, fractal coral,
  medusa, silk veil, cellular gardens, and echo chamber now satisfy bindings
  0–12, exact C, A-only feedback, ACES display, semantic alpha, plasma XYZ,
  bounded `[133..138]` state, and four live named JSON params.
- Focused shader/state/slider gates pass 10/10; catalogs, TypeScript, Jest, and
  production build pass. Real-GPU visual and performance QA remains external.

## Generative Grid / Grok / Holographic cohort (2026-08-23)

- The ten Lotus/Grid/Grok/Bismuth/Data Core shaders preserve catalog IDs, seven
  underscore-backed filename aliases, bindings 0–12, 16x16 workgroups, saved
  defaults, interaction contracts, and A-only ownership.
- Lotus, Grid, Mandelbrot, Bismuth, and Data Core own display history. Life,
  Perlin, Plasma, Interference, and Voronoi retain raw A simulation/telemetry.
  Only Lotus `[133..138]`, Grid/Mandelbrot `[133..136]`, and Life `[133..134]`
  may persist scalar state.
- Four aligned named controls were added only to Lotus, Bismuth, and Data Core;
  all existing params and updatedParams are preserved. Structural, catalog,
  Jest, typecheck, and production-build gates pass; real-GPU QA remains.

## Crystalline / cybernetic generative cohort (2026-08-23)

- Ten requested IDs run from `gen-crystal-lattice-growth` through
  `gen-cybernetic-liquid-chrome-engine`; ferro-coral and liquid-chrome-engine
  have prior upgrades whose visual/state behavior must be preserved during the
  contract audit.
- Acceptance adds an explicit four-named-parameter JSON requirement to the
  standard full-13-binding, ACES, semantic-alpha, A-only writeback, exact-C-load,
  regional three-band audio, bounded `[133..138]` state, interaction, and Naga
  gates.
- Completed 10/10: exact integer C history, raw HDR A-only packing, ACES display,
  semantic alpha/depth, and three-band audio throughout; no target needs
  extraBuffer state. Nine prior `updatedParams` arrays stayed exact, while the
  void-spider's incorrect control order was deliberately aligned to WGSL.
- Proof: Naga 10/10, no focused dead sliders or contract violations, 1,333-shader
  catalog, TypeScript and URL/uniform checks, 81 Jest suites / 545 passes / one
  skip, and production build green. Real-GPU visual proof remains external.

## Ornate / fractal-growth generative cohort (2026-08-23)

- Ten IDs span dynamic tessellation, dunes, eldritch eye, calligraphic weave,
  ferrofluid monolith, Fibonacci garden, two flame systems, silk ribbons, and
  fractal tree growth.
- Apply the same full-13 / ACES / semantic-alpha / A-only raw HDR history /
  exact-C-load / three-band audio / bounded-state / interaction / four-named-
  parameter contract, while preserving the preceding completed batch in the
  shared worktree.
- Audit found seven requested IDs absent from both the tree and Git history;
  implement those exact IDs greenfield rather than renaming preset-bearing
  neighboring effects. The first three remain in-place upgrades.
- Completed all ten. The seven missing IDs are now independent effects; Dynamic
  Tiles, Echo Dunes, and Eldritch Eye were repaired in place. A/C is raw HDR
  display history, C loads are exact, B is never written, and every definition
  exposes four live named controls.
- Echo Dunes alone uses persistent state at `[133]`; the other nine use none.
  Proof: Naga/dead-slider/custom contract 10/10, 448 generative / 1,340 total
  catalog entries, TypeScript and URL/uniform checks, 81 Jest suites / 545 pass /
  one skip, and production build green. Real-GPU visual/performance proof remains
  external.

## Completed fireworks generative cohort (2026-08-23)

- Ten confirmed IDs cover audio symphony, chrysanthemum, comet trail, crackle
  palm, crossette, dahlia, fan, horse-tail, kamuro gold, and nocturne.
- Apply full bindings, ACES/semantic alpha, A-only exact C feedback, plasma
  audio, `[133..138]`-only state, Naga, and four-named-parameter rules while
  keeping every shell pattern visually distinct.
- Completed 10/10 in place with characteristic shell geometry intact. All use
  A-only semantic RGBA history, exact C loads, ACES display, generated depth,
  and live bass/mids/treble mappings. Audio Symphony alone uses auxiliary state,
  single-writer at slot 133.
- Six normalized-pointer conversions were repaired, and Nocturne's command
  shell is now properly held-pointer gated. All existing `updatedParams` labels
  and defaults stayed exact while new four-entry `params` arrays were added.
- Proof: Naga/dead-slider/custom contract 10/10, 448 generative / 1,340 total
  catalog entries, URL/uniform/typecheck clean, 81 Jest suites / 545 pass / one
  skip, and production build green. Real-GPU visual/performance QA remains
  external.

## Completed fractal / gravity generative cohort (2026-08-23)

- Ten confirmed IDs span fractal mechanisms, ember lattice, fractured monolith,
  aether geode/cavern, ghost flame, refractive mosaic, ferrofluid singularity,
  gravitational strain, and gravito-phononic accretion.
- Apply the full bindings, ACES/semantic alpha, A-only exact C feedback,
  three-band plasma audio, bounded `[133..138]` state, Naga, and four named live
  JSON control contract while keeping each visual system recognizably distinct.
- Completed 10/10 in place. The older monolith and geode now consume real plasma
  bands rather than overloaded config/resolution fields; mosaic and ferrofluid
  have exact temporal loads plus ACES/semantic output; strain and accretion now
  persist truthful field/display state and generated depth.
- Clockwork retains bounded sprung-orbit slots 133–138, Ghost Flame moves its
  two envelopes to 133–134, and no other target accesses auxiliary state.
  All definitions expose four aligned named controls with saved
  `updatedParams` labels/defaults preserved.
- Proof: Naga/dead-slider/static contract 10/10, 448 generative / 1,340 total
  catalog entries, URL/uniform/typecheck clean, 81 Jest suites / 545 pass / one
  skip, and production build green. Real-GPU visual/performance QA remains
  external.
