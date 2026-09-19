<<<<<<< HEAD
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
=======
# Notes — Sentient / Radiant cosmic entities eight (2026-09-15)

Coordinator: Flash. Branch: `cursor/sentient-radiant-eight-720b`.

## Ideas landed (findable in WGSL)

1. **gen-sentient-aether-plasma-nebula-moth** — `g_vein` / `sin(wp.x)*sin(wp.z)` ridges on the FBM wing; trailing-edge `hash33` scale-dust on `-wp.z`.
2. **gen-sentient-bismuth-hypercrystal** — hopper `fract(q.y * 8)` treads after the Menger cuboid; stair-riser `palette` mix on `g_hopper`.
3. **gen-sentient-cyber-aurora-void-owl** — `abs(sin(q.x * 28))` barb grooves on lattice cubes; concentric `fract(ir * 14)` iris rings on `g_eye_off`. Head-look now rotates `xz` then `yz` without overwriting `headPos.x`.
4. **gen-sentient-quantum-chrono-leviathan-moth** — `pow(1 - voronoi, 3)` raised veins; two `sdCapsule` antennae from the head.
5. **gen-radiant-chrono-glass-nautilus** — septa at `fract(spiral_a * 1.5 + 0.5)` seams; nacre keyed to `floor(spiral_hit * 1.5)`.
6. **gen-radiant-cyber-chrono-void-stag** — pearl spheres on antler segments; `fract` gait pulses on hoof trails. Dead `ripples[i].w` glow loop removed (padding, always 0).
7. **gen-radiant-quantum-crystalline-forge** — recalescence on `abs(g_fold)` crests; hopper terraces on folded `p.y`. **Deleted** `applyGenerativePrimaryControls` (it stole Density/Chroma/Fog/Mouse Influence). Mouse Influence now scales the UV gravity well. ACES on display RGBA + A.
8. **gen-radiant-quantum-plasma-kraken-core** — sucker discs along each tentacle; chromatophore `sin(t + p)` flashes. Raw `zoom_params` (no 0–1 re-clamp).

## Floor

- `plasmaBuffer[0].xyz` bass/mids/treble. Removed fake C (`bismuth`) and `u.config.y` audio (owl, leviathan-moth, stag, kraken).
- Mouse: `vec2(zoom_config.y, 1 - zoom_config.z)` UV, y=0 bottom. Owl no longer divides by resolution. Stag no longer divides by `config.zw`. Forge no longer treats mouse as pixel coords.
- ACES display RGB; semantic alpha; hit-distance depth; `dataTextureA` = display RGBA. No B writes. No new springs. No extraBuffer.

## Params

- Existing `updatedParams` / bismuth `params` values byte-exact vs `origin/main`.
- Canonical `params` added where missing; bismuth gained additive `updatedParams`.

## Gates (Cloud VM, no GPU)

- Naga 8/8 (`wgsl_precommit_gate.py --files …`).
- extraBuffer new writes `[0..132]`: 0.
- dead sliders: 0 / 32.
- Catalog 1,367. `SKIP_WASM_BUILD=1 npm run build` green.
- Jest 689 pass / 6 fail = pre-existing WASM `./bridge/api.js` (4 suites).

Real-GPU visual QA is external.
>>>>>>> f6dd97e68a019af78b520bcf8959f4b8bc31c88e
