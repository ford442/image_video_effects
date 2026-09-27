# NOTES — Sentient / Radiant Cosmic Entities Eight (2026-09-15)

Batch: 8 shaders, one native family (sentient/radiant cosmic fauna and
crystalline entities). Two native ideas each. Identities kept. No new
springs. No extraBuffer[0..132]. No IQ palettes. No click shockwaves.

Cards were written in BRIEFS.md before WGSL. Plumbing (13 bindings, 16×16,
ACES, semantic alpha, plasmaBuffer audio, canonical `params`) is floor work.

## Per shader

### gen-sentient-aether-plasma-nebula-moth
- Kept verbatim: ellipsoid thorax; capped-cone antennae; mirrored thin-ellipsoid
  wings; four-octave FBM; time-rift SDF; under-relaxed raymarch; mouse orbit;
  Wing Flutter / Storm / Glow / Rift meanings.
- Added: (1) thorax-rooted plasma venation (`g_vein_dist` from wing-local
  surface); (2) flap-reversal ion-scale wake filaments inside the existing
  15-step storm loop.
- Floor: plasmaBuffer three-band; ACES display A; semantic alpha; hit-gated
  depth; canonical `params`.
- A packing: ACES display RGBA; B unused.

### gen-sentient-bismuth-hypercrystal
- Kept verbatim: four abs-folds; anisotropic offsets; time rotations; cuboid;
  pointer-local twist; source-image mix; Growth / Audio React / Twist /
  Iridescence meanings. Leading `/shaders/...` URL left unchanged.
- Added: (1) recursive hopper terraces on the folded cuboid; (2) oxide zoning
  from dominant facet + hopper-band film thickness.
- Floor: plasmaBuffer audio (was C); ACES after source mix; aligned
  `updatedParams`.
- A packing: ACES display RGBA after preserved source mix; B unused.

### gen-sentient-cyber-aurora-void-owl
- Kept verbatim: tapered capsule body; sphere head; periodic cuboid feathers;
  wing box; nested glass eyes; obsidian/glass/core; aurora; source mix;
  Wingbeat / Eye / Aurora / Refraction meanings.
- Added: (1) auroral feather-current lanes (mat 3, cyan/magenta by row);
  (2) faceted cyber-iris aperture under each glass lens (treble-rotated).
- Floor: mouse UV not divided by resolution; head rotation order; signed
  feather boxes; glass shell so iris/core can win; plasmaBuffer; canonical
  `params`.
- A packing: ACES display RGBA including preserved source blend; B unused.

### gen-sentient-quantum-chrono-leviathan-moth
- Kept verbatim: capsule body; Voronoi-FBM wings; mirrored thin-box wings;
  radial chrono distortion; gyroid nebula; blackbody dust; mouse rotation;
  Wing Span / Plasma / Chrono / Nebular meanings.
- Added: (1) peristaltic armor grooves along the body capsule; (2) frozen-time
  wing lamellae in the existing wing refraction.
- Floor: plasmaBuffer in map and main; held dust via `zoom_config.w`; bounded
  gyroid bias `sin(time)`; bounds guard; canonical `params`.
- A packing: ACES display RGBA; B unused.

### gen-radiant-chrono-glass-nautilus
- Kept verbatim: logarithmic spiral; alternating shell/interior IDs; smooth
  chamber union; pointer axial distortion; Spiral / Bloom / Refraction / Audio
  meanings.
- Added: (1) logarithmic chamber septa at phase boundaries, thickening with
  radius; (2) birefringent growth lamellae from spiral phase + n·v.
- Floor: `max(length(p.xy), 0.001)` before `log`; canonical `params`.
- A packing: ACES display RGBA; B unused; C unused.

### gen-radiant-cyber-chrono-void-stag
- Kept verbatim: torso/neck/head/leg silhouette; leap; material IDs; antler
  chain; heart core; hoof trails; nebula; Scale / Antler / Nebula / Core
  meanings.
- Added: (1) crystal tine bifurcation (one bounded lateral child per enabled
  antler segment, complexity 1–5); (2) segmented chrono hoof-wake packets on
  existing trail capsules.
- Floor: mouse UV (not pixels); plasmaBuffer; ACES A; canonical `params`.
- A packing: ACES display RGBA; B unused; C unused.

### gen-radiant-quantum-crystalline-forge
- Kept verbatim: six-iteration abs-fold IFS; fold offsets/rotations; raymarch
  + fog; spectral surface; Density / Chromatic / Fog / Mouse meanings.
- Added: (1) crystallographic twin facets (alternating fold-parity spectra);
  (2) accretion weld seams at fold-plane intersections (white-hot→violet).
- Floor: removed `applyGenerativePrimaryControls` so sliders keep declared
  roles; mouse gravity uses normalized UV and `zoom_params.w`; same ACES vec4
  on output and A.
- A packing: ACES display RGBA shared by output and A; B unused; C unused.

### gen-radiant-quantum-plasma-kraken-core
- Kept verbatim: noisy core sphere; eight radial arms; capsule taper;
  twist/wave; core vs tentacle materials; pointer rotation; Void Depth camera;
  Twist / Glow / Heat / Depth meanings (full ranges, not flattened to 0–1).
- Added: (1) paired sucker-current rows on the nearest-arm underside
  (shade-only, no extra SDF loop); (2) core-to-arm peristaltic discharge
  (`t_radius` pulse + emissive phase).
- Floor: plasmaBuffer audio; `normalize` guarded at origin; ACES A; semantic
  alpha; hit-gated depth; canonical `params`.
- A packing: ACES display RGBA; B unused; C unused.

## Gates

- Naga / bindgroup / workgroup: 8/8
- extraBuffer new violations: 0
- dead sliders: 0
- `node scripts/generate_shader_lists.js`: generative 472
- Jest: 689 pass / 6 fail = pre-existing WASM `bridge/api.js` (semanticIndex green after search-index rebuild)
- SKIP_WASM_BUILD=1 `npm run build`: compiled successfully; catalog 1,367 / generative 472
- Real-GPU visual QA: external (Cloud VM has no GPU adapter)
