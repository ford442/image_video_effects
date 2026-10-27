# Idea Cards — Grok high (`grok/batch-02`, 2026-10-25)

Written before WGSL edits. Fifteen shaders, 151–197 lines. Each card adds **two** new ideas. Earlier ideas stay. Saved `params` stay byte-exact. No shared spring, ripple stamp, or IQ palette.

Formula rule: a §12.2 row is used on at most one file here. Most additions are domain extensions of quantities the file already computes, so they are not table rows.

Eight pasted headers are migrated to `#include "_prelude.wgsl"` as infrastructure (seven by the codemod, `split-flap-display` by hand because `dataTextureA` was `read_write`). That swap is not the upgrade.

---

## gen-cymatic-plasma-mandalas

IDENTITY: a dihedral Chladni plate — radial standing waves, nodal sand, antinode bellies — swirled by the pointer.
KEEP VERBATIM: integer symmetry from the slider; plasma density; cymatic frequency with mids; swirl chaos; three-band radial sum; shared-node sand; antinode bellies; bass nodal rings; chromatic SDF glow; click nodes; the existing pointer spring.
MECHANISM:
- tactic 2: a real plate's nodes are a product of a radial mode and an angular mode. Sand leaves the bellies.
- tactic 3: `foldedAngle`, `waveSum`, `belly`, and `sandSpeckle` are already computed. The angular factor is only a multiplier on `wave`.
- tactic 6: C is display history. Neither idea repacks it.
ADD:
  1. Angular Chladni spokes — brighten the zero crossings of `cos(foldedAngle * symmetryOrder)`, the angular half of the product already forming `wave`. Intersections with the radial nodes are the true nodes.
  2. Belly evacuation — multiply the existing sand by `(1 - belly)` so grains leave the antinodes they already mark.
FORBID: a new palette, a second spring, shockwaves beyond the click nodes already here.
A PACKING: ACES display RGBA (unchanged).
FORMULA: no §12.2 row.

## gen-cellular-automata-tapestry

IDENTITY: Gray–Scott tapestry on the photo — substrate A, activator B, anisotropic grain, colony nuclei and halos.
KEEP VERBATIM: 9-point weights; Diffusion A/B, Feed, Kill; luma feed/kill bias; held-pointer B injection; kill-rate B bands; anisotropy striping and weft; nucleus, halo, apoptosis. Raw `(nextA, nextB, 0, 1)`.
MECHANISM:
- tactic 2: feed rebuilds depleted substrate behind a colony; the reaction `A·B²` is hottest on the rim, not in the spent core.
- tactic 3: `reaction`, `feed`, and `A` are computed for the step and then dropped. `nucleus` is already a mask.
- tactic 6: both ideas are display tints of the same A/B fields.
ADD:
  1. Replenishment wash — a pale stain where `feed·(1−A)` is refilling substrate and B has already left.
  2. Stoichiometric rim — a hot line where `reaction` is high and the pixel is not the existing nucleus.
FORBID: a second solver, springs, an IQ palette.
A PACKING: raw `(nextA, nextB, 0, 1)`. ACES on display only.
FORMULA: no §12.2 row (the 9-point Laplacian is already the solver).

## multi-scale-evolutionary-cellular-gardens

IDENTITY: two competing species plus a resource field, 8-neighbor diffusion, bioluminescent borders, mouse nurture.
KEEP VERBATIM: channel layout `(s1, s2, resource)`; Mutation / Competition / Fertility / Mouse Nurturing roles; distance-weighted 8-neighbor means; epoch drift; border-flip glow. Exact `textureLoad` of C replaces the filtering sample (floor).
MECHANISM:
- tactic 2: a barren plot gets founder individuals; a pasture eaten down to nothing scars.
- tactic 3: `newRes`, `newS1`, `newS2`, and the neighbor averages already exist. Emptiness is their sum.
- tactic 6: founders and scars write the same three fields and only recolor the display.
ADD:
  1. Founder inoculum — a stable hash speck of one species, and only while the cell and its averages are empty, so the competition rules have colonies to fight over.
  2. Overgrazing scar — ochre soil where both species are high and `newRes` has crashed.
FORBID: a third species, a Gray–Scott replacement, a spring.
A PACKING: raw `(s1, s2, resource, 0)`. ACES on display only.
FORMULA: no §12.2 row.

## gen-crystal-lattice-growth

IDENTITY: golden-angle mineral dendrites from a nucleation seed, with hopper edges, striae, twins, and a faceted core.
KEEP VERBATIM: Symmetry / Growth / Hue / Thickness; recursive segment SDF; twin reflection on odd arms; hopper inner edge; growth striae; faceted core; click fronts.
MECHANISM:
- tactic 2: growing crystals trap dust in planes normal to the growth axis, and the child branch leaves a bright triple junction.
- tactic 3: `onArm`, segment parameter `h`, and `tip` are already in the branch loop.
- tactic 6: C is HDR display history. Veils and junctions add glow; they do not repack A.
ADD:
  1. Inclusion veils — faint planes along each segment, using the along-arm coordinate the striae loop already has.
  2. Triple junction — a tight highlight at the tip where the child branch leaves the parent.
FORBID: a new lattice family, thin-film oil slick, a spring.
A PACKING: raw HDR display RGBA in A; ACES on `writeTexture` (unchanged).
FORMULA: no §12.2 row.

## gen-fireworks-ring-shell

IDENTITY: Saturn-tilted ring-shell fireworks — empty core, per-shell roll, far-side dimming, rocket ascent, gravity.
KEEP VERBATIM: Ring Radius / Thickness / Count / Color; inclined ellipse; roll; empty-core test; far-side gain; rocket trail; hex core flash; gravity `sparkPos`.
MECHANISM:
- tactic 2: Saturn's rings are split by a gap, and spokes rotate around the ring.
- tactic 3: `expand`, `thick`, `ang`, and `js` already place every spark. Thickness currently only widens the glow kernel.
- tactic 6: C is display persistence. Neither idea writes a new field.
ADD:
  1. Cassini division — split sparks onto an inner and an outer ringlet separated by `thick`, so Thickness opens a dark gap instead of only a fatter kernel.
  2. Ring spokes — a slow angular brightness modulation around `ang`, darker lanes rotating with the shell.
FORBID: a second firework species, a pointer spring, an IQ palette.
A PACKING: ACES display RGBA (unchanged).
FORMULA: no §12.2 row.

## gen-psychedelic-moire-flower

IDENTITY: a three-layer moiré flower, 8- and 13-count petals, 6.8% density detune between p1 and p2.
KEEP VERBATIM: Intensity / Speed / Scale / Color Shift; the three `moireFlower` stacks; 8/13 petal sines; the 1.068 detune; held-pointer recenters the flower; chromatic triple sample.
MECHANISM:
- tactic 1: a moiré's visible object is the difference frequency, which the detune implies and the product `|p1−p2|` does not draw.
- tactic 3: 8 and 13 are already the petal counts. Their vernier is 5. `d` and `angle` are already in `sampleFlower`.
- tactic 6: C is display history. Beats are pattern amplitude only.
ADD:
  1. Difference-frequency beat — a broad radial lobe at `|30 − 25·1.068|`, the detune the second layer already uses.
  2. Five-lobe vernier — `sin(angle·5)` gating the existing 8×13 petal product, the beat of those two counts.
FORBID: a new flower, a spring, a palette swap.
A PACKING: ACES display RGBA (unchanged).
FORMULA: no §12.2 row.

## gen-buddhabrot-aura

IDENTITY: a sampled Buddhabrot — nebulabrot escape channels, interior dust, orbit spine, cardioid and period-2 limb.
KEEP VERBATIM: Orbit Threshold / Density / Mouse Zoom / Aura; `z²+c`; nebulabrot early/mid/late bins; anti-Buddhabrot interior; min-distance spine; escape-argument streaks; dwell isochrones; cardioid and period-2 bulb; click kick on `c`.
MECHANISM:
- tactic 1: the escape index is an integer. The smooth count is the same iteration with the fractional part restored.
- tactic 2: the next landmark after the period-2 disk is the period-3 bulb.
- tactic 3: `dist` and `i` exist at the escape break. `center` is the `c` already tested against the cardioid.
- tactic 6: C is display history. No new buffer.
ADD:
  1. Smooth escape time (§12.2E) — replace the integer `esc` used by the nebulabrot bins, dwell, and density with the continuous iteration, so the bands are not stepped.
  2. Period-3 limb — a small circle at the period-3 bulb nucleus, drawn like the period-2 bulb already in the file.
FORBID: a different fractal, a new trap family, a spring.
A PACKING: ACES display RGBA (unchanged).
FORMULA: smooth iteration count (§12.2E), this file only.

## gen-echo-dunes

IDENTITY: wind-driven dune ridges on a sunset grade — slipface, wind streaks, crest saltation, avalanche tongues, mirage, echo rings.
KEEP VERBATIM: Dune Scale / Wind / Mirage / Echo; three-ridge sum; slipface from `−cos(phase)`; wind streaks; crest saltation; avalanche tongue; ridge shadow march; bass envelope in `extraBuffer[133]`.
MECHANISM:
- tactic 2: ripples sit on the stoss (windward) slope; the brink where crest becomes slipface carries a cornice.
- tactic 3: `ridgePhase`, `slipface`, and `crest` are already masks. The stoss is the complement of the slipface.
- tactic 6: C is HDR display. Ripples and cornice are shading.
ADD:
  1. Stoss ripples — fine transverse ridges only where `cos(ridgePhase)` is the windward face, absent on the slipface.
  2. Cornice — a thin bright lip where the crest mask overlaps the top of the slipface.
FORBID: a fluid solver, a spring cursor, an IQ palette as the sky.
A PACKING: HDR display RGBA in A; ACES on `writeTexture` (unchanged).
FORMULA: no §12.2 row.

## gen-dynamic-tessellation-ornate-fractal-tiles

IDENTITY: ornate Julia tiles — per-tile escape, blackbody glaze, grout, corner rosettes, equipotential contours.
KEEP VERBATIM: Fractal Detail / Motion / Tile Density / Mouse Warp; per-tile `c`; iteration; grout; rosettes; equipotential contours of `f_val`; click fronts.
MECHANISM:
- tactic 5: a real tile joint is a recessed groove, and ornate tiles run a rib from corner rosette to corner rosette.
- tactic 3: `tile_local` and `grout` already describe the joint. The rosettes sit at the corners the ribs should join.
- tactic 6: C is HDR history. Both ideas are shading inside the tile.
ADD:
  1. Recessed joint — darken a band just outside the existing grout highlight so the joint reads as a groove.
  2. Filigree ribs — a thin diagonal from the existing corner ornaments toward the opposite corner, killed inside the grout.
FORBID: a different fractal, a spring, scanlines.
A PACKING: HDR in A; ACES on `writeTexture` (unchanged).
FORMULA: no §12.2 row (blackbody is already the glaze, not a new idea).

## magnetic-flux-garden

IDENTITY: dipole field lines between two pointer poles, curled by noise, with a magenta bloom and gold seeds.
KEEP VERBATIM: Field Lines / Field Strength / Organic / Bloom; dipole march; curl-noise offset; harmonic warp; IQ mix on the bloom layer only; seed hash. Exact `textureLoad` of C replaces the filtering sample. A stays the field triple.
MECHANISM:
- tactic 2: a two-pole magnet has a neutral current sheet on the midplane, and each pole has a saturated core (the line march already bails out inside 0.02, so the core is undrawn).
- tactic 3: `poleA`, `poleB`, and `p` are the dipole the march uses. The inverse-square is already the line step.
- tactic 6: A is `(flux, curl, seed, alpha)` and C is read back as that triple mixed into the display. Cores and the sheet are display-only.
ADD:
  1. Neutral sheet — a thin bright seam on the perpendicular bisector between the poles.
  2. Soft inverse-square cores (§12.2F) — a saturated glow at each pole, `r0² / (d² + r0²)`, so the core the march skips is visible and finite.
FORBID: a second field family, ferrofluid spikes, a spring.
A PACKING: raw `(flux, curl, seed, alpha)` echoed into the display; ACES on `writeTexture` only.
FORMULA: soft inverse-square (§12.2F), this file only.

## gen-celestial-yggdrasil-matrix

IDENTITY: a raymarched KIFS world-tree — twisted trunk, plasma flow, golden buds, counterflowing sap, xylem rings, mycorrhizal nodes.
KEEP VERBATIM: Branch Complexity / Plasma Flow / Gravity Warp / Glow; KIFS map; buds; sap pair; xylem rings; node halos; mouse gravity warp; leaf swarm.
MECHANISM:
- tactic 2: bark cracks run along the trunk, and wood with no plasma flow is dry heartwood rather than more glow.
- tactic 3: `branch_angle`, `flow`, and `p` are already on the hit.
- tactic 6: C is unread. A stays display RGBA. No extra march.
ADD:
  1. Bark furrows — dark longitudinal cracks in `branch_angle`, cutting the rings that are already circumferential.
  2. Heartwood — where `flow` is low, mix the hit toward dry bark instead of leaving it as dim plasma.
FORBID: a new creature, a liquid solver, step-AO (the march is already 64 KIFS steps).
A PACKING: ACES display RGBA (unchanged).
FORMULA: no §12.2 row.

## gravito-phononic-accretion

IDENTITY: two orbiting accretors, advected display history, phonon ridge between them, shock shells.
KEEP VERBATIM: Accretion Speed / Lensing / Diffusion / Mouse Gravity; the two centers; pull and swirl; exact-C advection and cross blur; phonon fundamental; shock shells; audio spring in `extraBuffer[133..134]`; click fronts.
MECHANISM:
- tactic 2: two masses have a saddle where the pulls cancel, and a standing wave has an overtone.
- tactic 3: `pull1`, `pull2`, `along`, `across`, and `onSeg` are already the ridge.
- tactic 6: A is display RGBA and C is that history. The saddle only darkens; the overtone only adds.
ADD:
  1. L1 saddle — darken where the two pulls match, gated by the same on-segment mask as the phonon ridge, so the dimple sits at the midpoint.
  2. Phonon overtone — the second harmonic of the existing `sin(along·…)` ridge, narrower across the axis.
FORBID: a third body, a new solver, another spring.
A PACKING: ACES display RGBA (unchanged).
FORMULA: no §12.2 row.

## flow-sort

IDENTITY: photo pixels sorted along the luminance-gradient tangent, with an Asendorf run gate and a short LIC smear.
KEEP VERBATIM: Flow Strength / Sort Passes / Trail Persistence / Threshold; tangent flow; mouse vortex; ripple vortices; upstream/downstream swaps gated by the threshold; the existing short LIC; C as color persistence.
MECHANISM:
- tactic 7: the tangent is a direction. Where the field ahead agrees, the run is laminar and should smear farther; where it disagrees, a critical point should stay short.
- tactic 3: the gate already refuses a swap when upstream luma has left the run. That refusal is thrown away.
- tactic 6: C stays color. Both ideas composite into the sorted RGB.
ADD:
  1. Laminar extension — one extra LIC pair at a longer stride, mixed only by `dot(flow, flowAhead)`.
  2. Run-end bead — a pale cap where upstream was brighter but the existing threshold gate refused the swap.
FORBID: a new vector field, a spring, a palette grade.
A PACKING: ACES display RGBA; C is color (unchanged).
FORMULA: no §12.2 row.

## split-flap-display

IDENTITY: a Solari board — photo tiles that spin on a horizontal hinge, snap to half-turns, invert on the back.
KEEP VERBATIM: Grid Density / Mouse Radius / Auto Flip / Damping; one angle and one velocity per cell; magnetic snap to π; cosine foreshortening; back-face invert; hinge line; mouse push; idle flips.
MECHANISM:
- tactic 5: a split-flap's lower leaf arrives after the upper, and the drum shows which character it is on.
- tactic 6: state was read from `dataTextureA` at `cell_id`, which is not this cell (A is write-only after the prelude). Read C at the cell-center pixel, which this cell writes. Same `(angle, velocity)` packing.
- tactic 3: `velocity` and `angle` are the whole mechanism. The lag is a fraction of velocity on the lower half only.
ADD:
  1. Split timing — the lower half renders `angle - lag(velocity)` so the bottom leaf trails the top. At rest the lag is zero and the card is one plane again.
  2. Drum pip — a gold index on the right edge whose height is `fract(angle/π)`, the progress through the current half-turn.
FORBID: a spring cursor, click shockwaves, a character font, repacking display color into A.
A PACKING: raw `(angle, velocity, 0, 1)` in A, read from C at the cell-center pixel. ACES on display only.
FORMULA: no §12.2 row.

## gen-crystalline-mandala-bloom

IDENTITY: a photo folded into a gem mandala — kaleidoscope facets, petals, bass rings, per-facet refraction, treble on the petal edge.
KEEP VERBATIM: Symmetry / Facet Zoom / Bloom / Hue; polar fold; per-facet hash offset; petal SDF; bass rings; hue rotation; the existing edge sparkle; click blooms.
MECHANISM:
- tactic 2: a cut stone disperses along the facet normal it already bends, and the pavilion meets at a dark culet.
- tactic 3: `facetOffset`, `facetHash`, and `r` are the facet and the radius. The center is only a wide bloom today.
- tactic 6: A is raw HDR display. Dispersion resamples the photo; the culet only shades.
ADD:
  1. Cauchy dispersion (§12.2F) — red and blue samples along the same facet offset, at two scales, with green kept on the existing faceted coordinate.
  2. Culet — a tight dark pit at `r = 0` inside the existing bloom, with a small cold specular in the hole.
FORBID: thin-film iridescence as the look, a new fold family, a spring.
A PACKING: raw HDR display RGBA in A; ACES on `writeTexture` (unchanged).
FORMULA: Cauchy dispersion (§12.2F), this file only.
