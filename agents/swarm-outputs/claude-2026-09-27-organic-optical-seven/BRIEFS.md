# BRIEFS — Organic / Optical Seven (2026-09-27)

Draft Idea Cards written BEFORE any WGSL edit. Agents refine into `card-<id>.md`.

### 1. gen-abyssal-chrono-coral (3D IFS coral, Batch-63 overlay → second pass)
- IDENTITY: folded-fractal coral raymarch racing down an abyssal current, glowing tip nodes, cursor time-dilation well.
- KEEP: abs-fold/rotate/smin loop, `growthRings`, `gravitationalLensing`, well (`zoom_params.w`), sediment rings from `u.ripples` (already age-based), 4 params, abyssPalette.
- ADD: (1) growth-band strata carved into the branch SDF along the branch axis, band phase running on `local_time` so bands visibly age faster inside the well; (2) gravitational red/blue-shift: hue and glow shift toward red inside the well, with an Einstein-ring rim at its edge; (3) growth-front budding: tip-node radius swells in a travelling wave along branch depth.
- FORBID: new spring/ripple layers, polyp crown (sibling coral-reef owns that).
- Cleanup: the `extraBuffer[133..138]` spring never persists (resets each frame), so it is a dead no-op. Delete it or leave it and note it.
- A PACKING: keep — ACES display trail (`prev*0.94` mix).

### 2. gen-abyssal-silicate-geode-weaver (Voronoi geode + gyroid silk threads)
- IDENTITY: rotating Voronoi cavity hung with fast iridescent gyroid threads, click waves.
- KEEP: `voronoi`, `gyroid`, mouse gravity well, 4 params, `getPalette` iridescence, click waves, fast rotation.
- ADD: (1) agate/chalcedony banding inside geode facets from the (F2−F1) Voronoi field, colour-zoned; (2) dew-bead knots along threads (radius beads along the gyroid parameter, specular pearls) so it reads as woven silk; (3) optional: thread thickness feeds the thin-film phase.
- FORBID: new palette overlay, springs.
- Plumbing that changes the look: replace `textureSampleLevel(dataTextureC, u_sampler, …)` (filtering sampler on rgba32float) with manual bilinear `textureLoad`, keeping the tangential advection; alpha `1.0` → thread coverage / emission; add ACES on display only. The current HDR `max(col, previous*0.9)` history stays in A.
- A PACKING: keep — HDR history (documented on the `A packing:` line).

### 3. gen-aurora-silk (2D curtains, domain-warped ribbons, HDR grade)
- IDENTITY: warped ribbon curtains with bloom, god rays, split-tone, cool→warm grade.
- KEEP: `ribbons`/`band` formula, curtain falloff, palette, grade chain, 4 sliders.
- ADD: (1) satin anisotropic sheen from the ribbon phase gradient (fold highlights, "silk"); (2) fine warp-thread striations along the ribbon direction; (3) fold occlusion, darkening in creases.
- FORBID: altitude emission colour (sibling `aurora-borealis-synthesis` owns it), spring/ripples.
- A PACKING FIX: HEAD writes `(wind, band, shimmer, alpha)` to A but reads C as `prev.rgb` colour, so it feeds field data back as colour. Switch A to display RGBA and say so on the card.

### 4. gen-aurora-borealis-synthesis (20-step fbm volume over source image)
- IDENTITY: chromatic-split volumetric aurora added onto the input image; mouse sets the storm direction.
- KEEP: `fbm` volume march, R/G/B split by treble/mids/bass, `applyGenerativePrimaryControls` tail, existing param roles (x=height, y=swirl, z=brightness, w=mouse).
- SILENT BUGS, fixed and disclosed:
  - The colour comes from `plasmaBuffer[color_index]` with index up to 127, and only index 0 is written. The aurora is effectively black and shows just the base image.
  - `ripple.w` is always 0 and `ripple.z` is used as a radius, so clicks do nothing.
  - Filtering sampler on C.
- ADD: (1) procedural altitude emission layers, replacing the dead LUT: 557 nm green base, 630 nm red upper fringe, blue-magenta lower edge, keyed on step depth `i`; (2) curtain pleats: sheared fbm sampling so the volume reads as vertical rayed curtains, not cloud; (3) click substorm arcs: age-based expanding brightening fronts.
- **Default look changes a lot** (from near-nothing to a real aurora). This is the fix, and I'll flag it to the user.
- A PACKING: display RGBA.

### 5. gen-bio-luminescent-jelly (2D SDF jelly + 8 segment tentacles)
- IDENTITY: one drifting SDF jellyfish, domed bell, chained tentacle segments, sparkles, mouse attraction.
- KEEP: bell SDF, tentacle chain loops, 4 params, drift/attraction, held shockwave, pulsePhase in `A.r` (per-pixel identical, documented).
- ADD: (1) jet propulsion: bell contraction phase drives motion, tentacles lag and stream opposite the analytic drift velocity; (2) anatomy: 4 radial canals, gonad horseshoe and a lappet-notched bell margin replacing the generic `innerGlow`; (3) marine snow lit by the jelly's own glow (halo on drifting specks).
- FORBID: springs, ripples, another creature.
- A PACKING: keep raw pulsePhase in `A.r` plus alpha, and document it.

### 6. gen-bioluminescent-abyss (3D tube-worm field, vents)
- IDENTITY: endless raymarched deep-sea floor: swaying tube worms, cone vents, glowing tips, mouse spotlight.
- KEEP: `map` (floor fbm, worm domain repetition, vent cones), seasons, 4 params, premultiplied output, alpha model.
- SILENT BUG: `time = u.config.x*0.1` is used for click age (`time - ripple.z`), so click blooms age 10× too slowly, and ripple xy→world is arbitrary. Fix with the true clock and a consistent mapping.
- ADD: (1) tube-worm plume crown: radial gill lamellae (angular modulation in shading/bump, not SDF, to protect the 128-step cost) that retract under the spotlight or a click; (2) chemosynthetic bacterial mats: floor glow with a falloff toward the nearest vent centre (cheap, from the existing vent cell hash); (3) click chain-reaction: neighbour worm tips light after a delay proportional to distance (arrival-gated).
- FORBID: marine snow (jelly owns it), new SDF-heavy plumes.
- A PACKING: fix `A` alpha (hardcoded 1.0) to real alpha, and replace the filtered `textureSampleLevel` of C with `textureLoad`.

### 7. gen-coral-reef-colony (2D branch/polyp field)
- IDENTITY: procedural coral colony: branch noise, polyp grid, aragonite stress→healthy colour, mouse pull, click nutrient fronts.
- KEEP: growth/polyp/colorVariety/mouseAttraction roles, `aragoniteColor`, `clickFront`, caustics.
- SILENT BUG: `fbm` returns raw `hash21` with no interpolation, so branch angle is per-pixel static, not branches. Replace with value noise.
- ADD: (1) coherent forking branches: per-cell angle plus two ±35° sub-branches, tapering to tips; (2) skeleton accretion and bleaching memory in `C.a`, the same precedent as crumpled-paper's ironing memory: fed cells grow and persist, starved cells bleach through the existing `aragoniteColor` stressed state; (3) star-lobed polyp mouths that retract near the pointer and extend with treble.
- A PACKING: display RGBA in rgb; `A.a` = skeleton memory (not display alpha), documented. `writeTexture` keeps the semantic alpha.

