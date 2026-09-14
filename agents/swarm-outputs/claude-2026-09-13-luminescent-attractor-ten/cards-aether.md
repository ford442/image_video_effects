# Aether pair — Idea Cards (2026-09-13)

```
SHADER: gen-luminescent-aether-plasma-astro-axolotl
IDENTITY (one sentence): a pink raymarched axolotl with 4-generation fractal cyan gills drifting in a
  blue/purple noise nebula over a kaleidoscopic caustic ring lattice, mouse-orbit camera, click ripples.
KEEP VERBATIM: map() body/tail/gill SDF + gill fractal loop, rippleField, kaleido caustic layer, noise
  nebula, mouse-orbit camera, FFT-bin gill fold (extraBuffer[5..132] read-only), param roles
  (x Gill Expansion, y Current Warp, z Nebula Density, w Bioluminescence), depth near=1.
ADD (3 native ideas):
  1. Gill regeneration wave — a bass-kicked regrowth front runs root->tip through the fractal branch
     generations (per-generation thickness swell + generation index carried in the material id), so the
     gills visibly re-grow outward. Axolotls are the regeneration animal; the gills are the fractal.
  2. Gill capillary flow — emissive plasma bands travel along each gill filament from root to tip,
     speed from mids, brightness gated by the regeneration front (external gills are blood-filled rami).
  3. Leucistic iridophore speckle — gold iridophore flecks on the pink body skin (3D noise cells on the
     hit point), treble makes them glint. Real axolotl skin detail, native to the body material.
FORBID on this file: spring cursor, extra shockwave rings, IQ cosine palette, koi scales/fins/wake.
A PACKING: display RGBA (ACES) in A — C is not read (unchanged role: HEAD already wrote display RGBA).
```

```
SHADER: gen-luminescent-aether-plasma-nebula-koi
IDENTITY (one sentence): a blue iridescent spindle koi with voronoi plasma scales, fins and a waving
  tail, lit by warm/cool/violet lights inside a volumetric voronoi nebula with god rays; mouse bends rays.
KEEP VERBATIM: mapKoi() SDF (body/fins/tail wave), voronoi scale pattern, 3-light rig + rim + iridescent
  fresnel + SSS, 40-step volumetric fbm nebula, god rays, mouse gravitational ray bend, hue clamp -> ACES
  -> IGN dither, param roles (x plasma_intensity, y koi_speed, z nebula_density, w tail_length).
ADD (3 native ideas):
  1. Tail-fin wake (Karman vortex street) — alternating glowing vortex puffs shed behind the tail in
     the volumetric nebula march, phase-locked to the tail wave (koi_speed, tail_length), bass sheds
     stronger vortices. It is what a swimming koi leaves in the water.
  2. Scale-row shimmer — overlapping half-offset koi scale rows along the body axis with a mids-driven
     flash band travelling head->tail across the rows (a koi "turning" flash), treble sparkles scale rims.
     Deepens the existing voronoi scale pattern rather than replacing it.
  3. Honest C persistence — HEAD mixed readTexture (the input image, not history) as "previous frame" and
     packed masks into A. Now: exact textureLoad(dataTextureC) blend of the display, A = display RGBA.
FLOOR FIX: `audio = u.config.y` (ripple count!) replaced with plasmaBuffer[0] bass/mids/treble.
FORBID on this file: axolotl gills/regeneration, spring cursor, click shockwaves, IQ palette.
A PACKING: display RGBA (post-ACES) in A; C read exactly as display history. (HEAD packing was
  sss/density/fresnel masks with no C reader — a packing lie, fixed here.)
```

---

## NOTES — gen-luminescent-aether-plasma-astro-axolotl

- **Kept verbatim:** body/tail SDF, gill fractal loop structure, `rippleField`, `kaleido` caustic lattice,
  noise nebula, mouse-orbit camera, FFT gill/air bins (extraBuffer[5..132] read-only), all 4 param roles.
  Audio check: HEAD plasmaBuffer[0].xyz reads were real (bass breathing/gill expansion, mids wiggle and
  caustic fold count, treble gill emission), not stale. Kept.
- **A packing:** ACES display RGBA (HEAD already wrote display RGBA; C is not read).
- **Ideas in diff:**
  1. Regeneration wave — `regenFront()` (~L111); in `map()` gill loop `regrow` swells thickness/length
     per generation, `gill_gen` carried in material id `2.0 + gen*0.1` (~L163-193).
  2. Capillary flow — gill shading branch in `main()` (~L309-318): `pulse` along `length(p - root)`,
     mids speed, gated by `fresh` (distance to regen front).
  3. Iridophore speckle — body branch in `main()` (~L299-302): `fleck` noise cells, treble `glint`.
- **Floor changes:** Reinhard -> `aces()` on display RGB (gamma kept); alpha now coverage-aware
  (hit = ~0.9-1.0, nebula = luma transmission); material test switched from `== 1.0/2.0` to ranges.
- **Gates:** naga OK; wgsl_precommit_gate PASS; audit_dead_sliders PASS but scanned 0 definitions
  (JSON has only `updatedParams`, no `params`) — all four zoom_params verified live by grep.
- **JSON:** added `features` [mouse-driven, audio-reactive, upgraded-rgba]; nothing else touched.

## NOTES — gen-luminescent-aether-plasma-nebula-koi

- **Kept verbatim:** `mapKoi()` SDF, voronoi scale pattern, 3-light rig + rim + `iridescent_scale` + SSS,
  40-step fbm nebula, god rays, mouse ray bend, hue clamp -> ACES -> IGN dither, all 4 param roles.
- **Audio bug fixed:** `let audio = u.config.y` (ripple count) removed; glow uses bass (x0.6, clamped),
  bloom uses bass*0.5 + mids*0.2, mids drive scale flash, treble drives scale-rim sparkle, bass drives wake.
- **A packing:** ACES display RGBA; C read with exact `textureLoad(dataTextureC, ..)` as display history.
  HEAD wrote sss/density/fresnel masks into A and "persisted" from `readTexture` (the input image) —
  packing lie, fixed.
- **Ideas in diff:**
  1. Karman tail wake — `koiWake()` (~L128), accumulated in nebula march loop (`wake_acc`, ~L314).
  2. Scale rows + turning flash — `koiScaleRows()` (~L147), used in hit shading (~L291-300):
     `flash` band head->tail, `sheen`, `sparkle`.
  3. Wake-lingering C persistence — `persist` (~L342-344), blended post-ACES.
- **Floor changes:** depth now near=1 on koi hit, 0 on open nebula (HEAD wrote `t*0.08`, far=bright);
  alpha adds wake density term.
- **Gates:** naga OK; wgsl_precommit_gate PASS; audit_dead_sliders PASS (1 definition, 0 dead).
- **JSON:** added `features` [mouse-driven, audio-reactive, upgraded-rgba]; `parameters`/`updatedParams`
  byte-exact.
- **Distinctness:** axolotl = gill regeneration/capillaries/skin flecks (inside the creature);
  koi = water wake/scale-row flash/history (around and on the scales). No shared overlay code.
- Real-GPU visual QA still required (wake visibility behind the koi in on-axis camera is the main unknown).
