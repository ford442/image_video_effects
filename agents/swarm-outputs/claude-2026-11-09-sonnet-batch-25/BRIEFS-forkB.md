# BRIEFS — Fork B (sonnet/batch-25): crystal-illuminator (1st pass, non-compiling), crystal-mosaic (2nd pass), crystalline-shatter (2nd pass)

Written 2026-11-09 BEFORE any WGSL edit. HEAD renders: scratchpad/forkB/ (`<id>_head_{192,576}_{idle,held}.png`; crystal-illuminator's are from a scratch copy `head_crystal-illuminator.wgsl` with ONLY the two compile errors removed).
Stats (192, idle / held+audio 0.4,0.3,0.2): illuminator(scratch-fixed) meanL .359/.345 stdL .178/.165 meanA .447/.447 · mosaic meanL .480/.497 stdL .185/.160 meanA .971/.990 · shatter meanL .492/.497 stdL .166/.170 meanA 1/1. No NaN anywhere.

---------------------------------------------------------------------------------------------------
## 1. crystal-illuminator  (RESCUE: does not compile at HEAD)

### HEAD observation
naga/WGSL: `let aspect` is declared twice in `main` (line 45 and 192) and `__finalRGB` starts with two underscores → 2 compile errors, so the effect has been dead in the app (it is on the naga knownFailures ratchet). With only those two removed it renders as: Voronoi facets (3×3, animated seeds), each with a random normal, lit by a lamp at the cursor (diffuse + spec 32 + 1/(1+10d²) attenuation), Fresnel-IOR rim, refracted single tap `normal.xy*0.1*(ior−1)`, absorption/transmission as alpha (clamp .2..1). On top sits a full-screen concentric `clockRings` rainbow (radial dark-green rings centred on the SCREEN centre, `sin(length(uv-.5)*95 - time*(5+treble*7))`, tinted by a cosine palette) plus a click ring — it reads as a ring tunnel pasted on a gem and is the dominant look at 576 px. `edge_factor` and `tir` are computed and never used. No A write, no ACES, output unclamped, lamp distance not aspect-corrected, `bass` unused.

### Idea Card
```
SHADER: crystal-illuminator
IDENTITY: a faceted glass/gemstone slab over the photo, lit by a lamp at the cursor; facets refract the
  photo, Fresnel/absorption decide how much light is transmitted (alpha = transmission).
KEEP VERBATIM: 4 params + roles (crystal_size → cell density 5..30; ior → quartz→diamond mix 1.54..2.42;
  light_intensity → lamp power ×2; purity → roughness + per-cell absorption + transmission);
  animated 3×3 Voronoi seeds; per-cell random facet normal blended toward the dome by roughness;
  lamp = cursor at z 0.2 with diffuse + spec(32) + 1/(1+10d²); Fresnel-IOR; absorption path length;
  alpha = transmission clamp(.2,1); depth passthrough.
MECHANISM INTERROGATION (§12.1):
  tactic 1 (deepen the kernel): the refraction is one small-angle tap `n.xy*0.1*(ior-1)` — the next-better
    approximation of the SAME operator is Snell's vector refraction through the facet normal the file already
    builds, displaced by a slab thickness (§12.2F Snell). It also yields the refracted ray, which is the input
    the next idea needs.
  tactic 2 (physics one step further): a gem's defining optical behaviour is total internal reflection at the
    back facets: the refracted ray inside hits a pavilion facet; past the critical angle sinθc = 1/ior it is
    mirrored back out (brilliance), otherwise it leaves (window). θc is 40.5° for quartz and 24.4° for diamond —
    the `ior` slider therefore sets how many facets go "bright and dark" instead of transparent. HEAD even
    computed a `tir` term and dropped it.
  tactic 3 (promote an intermediate): `edge_dist = second_min_dist − min_dist` (and `edge_factor`) were computed
    and thrown away; the second-nearest site gives the seam direction, i.e. a bevel (arris) normal for free.
  tactic 5 (device artifact): a cut gem has arrises — the chamfered ridges between facets catch the lamp as thin
    glints; a struck gem flashes facet by facet.
  tactic 6 (history): C is not read at HEAD and stays unread (no continuity is native to a slab).
ADD (4 native ideas, all in the existing main path):
  1. Snell vector refraction through the facet (§12.2F) — `refract(view, facet_normal, 1/ior)` displaced by a
     slab thickness replaces the small-angle offset; the facet slope and `ior` both bend it correctly.
  2. Total internal reflection at the critical angle — a per-cell pavilion normal (second hash of the same cell)
     tested against `cosθc = sqrt(1 − 1/ior²)`; TIR facets show a darkened second-bounce sample, pick up a
     second lamp glint and lose transmission (alpha). `ior` slider keeps its role and now also sets the TIR share.
  3. Arris bevel — within a narrow band of `edge_dist` the facet normal tilts toward the neighbouring site
     (chamfer), so the seams refract hard and catch the lamp as thin glints (treble sharpens them).
  4. Click strikes the gem — HEAD's click-ring (which painted a rainbow ring over the picture) is re-expressed per
     facet: the front is evaluated at each cell's SITE and flashes the whole facet once as it passes.
FORMULA ADMISSION: Snell (row granted to this file in COMMON) consumes `facet_normal` + `ior` already present;
  Ideas 2–4 are tactic-derived (critical angle, promoted `edge_dist`, per-cell click front) and consume
  `ior`, `edge_dist`/second site, `cell_id`, ripples already read at HEAD. Deletion test: removing any one
  leaves the lit faceted slab; keeping only an idea (no lamp/facets) is not this effect.
FORBID on this file: springs (the lamp follows the raw cursor at HEAD and is not tethered), IQ rainbow rings,
  a second voronoi layer, thin-film, any new param, a change to the saved slider roles.
A PACKING: ACES display RGBA written to A (HEAD wrote nothing); C not read.
```
### RESCUE list
- **R1** compile: duplicate `let aspect` (drop the second, same value), `__finalRGB` → no leading underscores. Two naga errors → 0; removes the id from `knownFailures` (coordinator edits the ratchet).
- **R2** HEAD has no valid look to preserve — everything the code evidently intended is kept (lit voronoi slab, alpha transmission); the unclamped output gets clamp+ACES (clamp before aces).
- **R3** generic overlay: full-screen `clockRings` rainbow rings removed (not native to a crystal; radial about the screen centre irrespective of lamp); the click ring is kept as Idea 4 but per facet.
- **R4** lamp distance/direction aspect-corrected (the pool was an ellipse on 16:9). Voronoi cell layout per uv unit kept.
- **R5** dead intermediates (`edge_factor`, `tir`) either used (Ideas 2/3) or dropped; A now written.

---------------------------------------------------------------------------------------------------
## 2. crystal-mosaic  (2nd pass; existing Ideas: facet crease along u=v; lead came at triangle borders)

### HEAD observation (576 idle/held)
A near-square grid of tiles with dark lead came and a diagonal crease per tile; the photo is almost unchanged; each tile has a small dim diamond "dot" in its centre. Numbers show why the crystal part is invisible:
- `edge = smoothstep(0.15, 0.0, |v−.5| + |u−.5|·.5)` is **1 at the tile CORE** (a flat diamond), not at the edges. Everything labelled "edge" — chromatic aberration, env Fresnel, rim light, the SSS `thickness = 1 − edge` ("thinner at edges") — lands on that dot.
- `chromaticAberration(...)` (radial about the screen centre) offsets by `r·0.02·(edge·chroma·(1+bass))` ≈ 4e-5 uv: dead code. The RGB split that is live is ±`chroma·0.01·edge` = ±0.003 uv (1.7 px @576) inside the core only: the **Chromatic Edge slider is visually near-dead at its default 0.3**.
- `triCenter = (triID + (0.5, 0.57735))/density` — y should be `(j+.5)/(0.866·density)`; it drifts by `0.1547·j/density` (up to 0.13 uv at the bottom) and odd rows add a 0.5 tile x-shift that the drawn grid (`u_frac = fract(s.x)`, no parity) does not have. The rotation pivot and the **mouse-influence centre are displaced from their tile** (influence disc is wrong by up to 0.13 uv near the bottom of the screen).
- `sparkle = hash21(triID + time·0.2)·treble…` re-hashes every frame (frame-hash strobe) — audio-only.
- Alpha / A packing (ACES display RGBA) are fine; mouse = raw cursor (kept).

### Idea Card
```
SHADER: crystal-mosaic
IDENTITY: the photo cut into a mosaic of crystal tiles with lead came; tiles rotate near the cursor; lit like
  glass (caustics, rim, SSS glow, sparkle on treble).
KEEP VERBATIM: 4 params + roles (density → tile count 5..40; rotation → per-tile rotation amount;
  chroma → chromatic edge strength; influence → mouse influence); rhombus tile lattice, u=v crease (idea 1
  last pass) and lead came (idea 2 last pass); rotation = (rotation + influence + bass·.1)·.5 about the tile
  centre; caustics/SSS/border/sparkle terms; alpha formula; ACES display RGBA in A; depth passthrough.
MECHANISM INTERROGATION (§12.1):
  tactic 1: tile rotation is one global angle (+ mouse term) — the next-better model of the SAME operator is
    tesserae set by hand, i.e. a per-tile spread of that angle (the rotation slider stays its amplitude).
  tactic 2 (physics one step further): a glass tessera is chamfered; the chamfer is a prism wedge: it deviates and
    disperses the image just inside the border and its four faces catch a lamp differently depending on facing.
  tactic 3 (promote an intermediate): `u_frac`, `v_frac`, `borderDist` are already computed (for the came and the
    "border" glow); the nearest border side gives the chamfer direction with no new state.
  tactic 4 (second-order the param): `chroma` ("Chromatic Edge") is a scalar that never reached an edge —
    make it the dispersion amplitude of the chamfer where its name says.
  tactic 6: C not read; stays unread (A = display RGBA).
ADD (3 native ideas):
  1. Chamfered tessera refraction — a bevel band inside the came (borderDist ≈ .07–.27) shifts the sample toward
     the tile centre (thin-prism small-angle deviation, NOT the Snell row) and splits R/G/B along that slope with
     the Chromatic Edge slider as amplitude.
  2. Bevel facets lit by the cursor lamp — four chamfer normals (left/right/top/bottom of each tile) get Lambert +
     a Blinn glint from the lamp at the cursor (z .25), so chamfers facing the cursor brighten and the rest
     darken; reads as 3-D cut glass and follows the pointer (the file already owns it).
  3. Hand-set tesserae — per-tile hash adds a ±rotation jitter scaled by the Rotation slider (0 → aligned grid)
     plus a ±6 % per-tile brightness/tint, so neighbouring tiles no longer rotate in lockstep.
FORMULA ADMISSION: no §12.2 row claimed (thin-prism is the small-angle form of the same bend; Snell/Cauchy rows
  belong to others in this batch). Each idea consumes `u_frac/v_frac/borderDist`, `rot`, `mousePos`, `triID`
  that exist. Deletion test: remove any → still the lead-came crystal tile mosaic.
FORBID on this file: springs, click ripples, IQ palette, new params, replacing the lattice/came/crease.
A PACKING: ACES display RGBA (unchanged).
```
### RESCUE list
- **R1** pivot/influence centre: `triCenter` → true tile centre `(i+.5, j+.5)/(density, 0.866·density)` (`triID` kept for hashes/colour so those do not change).
- **R2** "edge" is the tile core: rename `core`; chromatic/env/rim now ride the real chamfer band (`bevel`), caustics/sparkle/SSS stay on the core (a domed tile focuses light in the middle). Default look change: tile-centre dots lose their rim, chamfer bands appear.
- **R3** dead `chromaticAberration()` radial branch removed (no-op at ±4e-5), its `mix` with it. Chromatic Edge slider now visible at default.
- **R4** sparkle frame-hash → 8 Hz stepped hash with a smooth per-tile envelope (no per-frame strobe).

---------------------------------------------------------------------------------------------------
## 3. crystalline-shatter  (2nd pass; existing Ideas: facet tilt Fresnel + light flash; conchoidal ribs; stress-line crack branching)

### HEAD observation (576 idle/held)
Healthy: Voronoi facets with independent refraction shifts, thin bright cracks, fine hairline branches near cracks; fringes only visible on strong photo edges (R/B offset ±0.0048 uv at the default, identical magnitude and direction scale for every facet). No NaN, A = ACES display RGBA, alpha semantic. Nothing broken. `mouseDist` is not aspect-corrected (zone is an ellipse on 16:9) — left alone (identity of the proximity falloff).

### Idea Card
```
SHADER: crystalline-shatter
IDENTITY: the photo shattered into Voronoi crystal facets, each refracting with its own vector, tinted and
  edged by bright cracks; mouse proximity and bass amplify the shatter.
KEEP VERBATIM: 4 params + roles (cell_scale, refraction, chromatic_aberration, edge_glow); 5×5 Voronoi + per-cell
  refVec; conchoidal ribs; facet-tilt Fresnel + sweeping key-light flash; edge crack lines + glint pulse;
  hairline branch layer; iridescent facet tint; semantic alpha; ACES display RGBA in A (C not read);
  facet-relief depth.
MECHANISM INTERROGATION (§12.1):
  tactic 1 (deepen the kernel): the chromatic split is ±c along one direction, equal for R and B and for every
    facet. The next-better approximation of the SAME operator is Cauchy dispersion scaled by the facet's wedge.
  tactic 2 (physics one step further): a crack is a thin air gap that traps and leaks light (light piping) — the
    glow around a real fracture is light taken from the glass beside it, not light created.
  tactic 3 (promote an intermediate): `|refVec|` (the facet slope) already drives the facet's tilt for Fresnel; it is
    also the prism wedge angle. `edgeDist` is already the crack-proximity field the ribs and branches hang on.
  tactic 8 (energy accounting): the crack lines ADD light (they replace colour with a bright tint) and nothing pays
    for it.
  tactic 6: C unread, stays unread.
ADD (2 new native ideas, appended after the 3 existing ones):
  4. Wedge-scaled Cauchy dispersion (§12.2F Cauchy) — per-facet fringe amplitude ∝ `|refVec|` (flat facets barely
     disperse, steep ones fringe hard) and R/G/B spacing from n(λ)=A+B/λ² relative to green
     (R −0.73 : G 0 : B +1.27, mean magnitude 1 so the default amplitude is unchanged). Same 3 taps.
  5. Light-piping crack halo with energy taken from the facet (§12.2F energy-conserving bloom, analytic from
     `edgeDist`, no new taps) — a soft exponential glow on both walls of each crack, paid for by darkening the
     facet beside it; strength rides Edge Glow (its existing role).
FORMULA ADMISSION: both rows are on this file's allowance (Cauchy: chroma-lens-iridescence + this; energy-conserving
  bloom: glass-bead-curtain-iridescence + this); both consume `refVec`/`edgeDist`/`crackTint`/`glintPulse` that
  exist. Deletion test: removing either leaves exactly the shattered photo; keeping only the halo (no facets) is
  not this effect.
FORBID on this file: springs, click fronts, any new param, a second crack system, replacing the crack/branch look.
A PACKING: ACES display RGBA (unchanged).
```
### RESCUE list
- none required (healthy at HEAD). Verified: no NaN, A packing consistent, no dead slider.
