# Notes — simpler / mid crystal-math ten

Idea Cards were written in `BRIEFS.md` before WGSL. Six files kept their dated mechanisms and gained two more. Crystal caverns, celestial forge, cosmic web, and DLA copper had no `Ideas:` line. Saved `params` were not edited. No new springs. Existing `extraBuffer[133..138]` springs on forge, cosmic web, cyclic automaton, and de Jong were left in place. Did not copy twin facets or weld seams from `gen-radiant-quantum-crystalline-forge`.

## gen-crystal-lattice-growth
- Kept: golden-angle `crystalBranch`, odd-arm twin mirror, hopper inner edge, click fronts.
- Added: striae along each segment (`across` / `stria`); faceted seed at the origin (`coreFace`).
- A packing: raw HDR in A; ACES on `writeTexture`.

## gen-chromatic-zonohedron
- Kept: four generators, axis dichroism, pair IDs, vertex stars.
- Added: `zonoZone` parallel-edge belts; `zonoInset` half-width rhomb inside the winning cell.
- A packing: ACES display RGBA.

## gen-cyber-terminal
- Kept: curvature, 3×5 `segmentGlyph`, white-hot leader, scanlines, HDR history in A.
- Added: seeded `gap` blanks along the drop; cold-green `wrapFlash` plus `wrapGen` glyph reseed at the column wrap.
- A packing: raw HDR display RGBA history.

## gen-cyclic-automaton (`gen_cyclic_automaton.wgsl`)
- Kept: GH state machine, chirality, `nextState == 2` halo, leading-edge tracer, pointer spring.
- Added: gold tint when a firing cell has `cardFiring == 0`; even/odd bands for `nextState >= 3`.
- A packing: raw `(state, fire, refract, bloom)`.

## gen-cycloid-bloom
- Kept: coarse+refine hypotrochoids, `bestT` vein, origin stamen.
- Added: one `epicycloid` layer with opposite spin; caustic where two layer distances are both small, off the origin.
- A packing: ACES display RGBA. No spring.

## gen-de-jong-attractor
- Kept: `de_jong` iterate, stretch tint, dwell rings, spring, click deformation.
- Added: display-only critical curves `cos(a y)` / `cos(c x)`; orbit also splats `−p`.
- A packing: raw density, hue, tube depth, alpha. ACES is display-only.

## gen-crystal-caverns
- Kept: octahedron / hex prism / pyramid habits, caustics, SSS, click shocks. No spring.
- Added: basal pinacoid `max(habit, -0.2 - qCrystal.y)`; phantom shell from an earlier-time scaled habit, mixed out as Purity rises.
- A packing: ACES display RGBA.

## gen-celestial-forge
- Kept: spring, greebles, trenches, panels, arcs, hammer-strike ripples.
- Added: ring index packed into `mat` and read back as a white-hot → straw → blue temper; four-flat chamfer on the torus tube, stronger with `g_strike`.
- A packing: ACES display RGBA.

## gen-cosmic-web-filament
- Kept: Zel'dovich displacement, filament ridge, striation, quasar junctions, spring void well.
- Added: mid-range `F2−F1` wall sheet; `hash31` beads on the filament, suppressed near junctions.
- A packing: ACES display RGBA.

## gen-dla-copper-deposition
- Kept: center cathode, held electrode, click nuclei, oxidation, tip sparks.
- Added: `exposed` screening so `attach` falls with `neighborMean` (seeds still use `max`); copper rim where deposit meets empty electrolyte.
- A packing: raw `(deposit, depletion, oxidation, activity)`.

## Gates
- Naga 10/10. Precommit 10/10. extraBuffer full-tree pass, 0 new writes to `[0..132]`. Dead sliders 0 on these ten.
- Jest 741 pass / 6 fail / 1 skip. The 6 are the pre-existing missing `src/wasm/bridge/api.js` resolver.
- `SKIP_WASM_BUILD=1 npm run build` compiled. Catalog stayed 1,373.
- Real-GPU visual QA: external.
