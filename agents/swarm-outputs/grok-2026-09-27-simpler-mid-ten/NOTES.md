# Notes — simpler / mid generative ten

Idea Cards were written in `BRIEFS.md` before WGSL. Eight files kept their 2026-09-06 or 2026-09-15 mechanisms and gained two more. Art Deco Sky and Alien Flora had no prior `Ideas:` line. Saved `params` were not edited. No new springs. Existing `extraBuffer[133..138]` springs were left in place.

## gen-acid-lissajous
- Kept: STRANDS×SAMPLES, origin beads, 1:1 glow waist, gravity, spring.
- Added: nearest-sample cusp dwell; 2:1 lobe tint by sample `y` sign.
- A packing: ACES display RGBA.

## gen-audio-spirograph
- Kept: epi + hypo loops, additive gears, rolling hubs, spring.
- Added: faint stator circle of radius `R`; cusp flash where segment tangents reverse.
- A packing: history RGB + coverage.

## gen-barnsley-fern
- Kept: `pickIFS` probabilities, `barnsleyInv`, stem-vs-leaflet tint, idx-0 rib, spring.
- Added: thinner rib and pale tint when the last map is idx 2 or 3; crozier density at high `y`.
- A packing: ACES display RGBA.

## gen-apollonian-gasket
- Kept: five seed circles, `circle_inv`, packing rims, last-`k` tint, spring.
- Added: ring frequency scales with `invCount`; contact sparks where seed circles nearly touch.
- A packing: linear RGB + alpha (ACES on display).

## gen-aperiodic-monotile
- Kept: odd-cell reflection, chevron brim, relief march.
- Added: kite notch opposite the brim; faint 4-cell metatile edge (`metaEdge`, `meta` is reserved).
- A packing: ACES display RGBA.

## gen-bifurcation-diagram
- Kept: logistic loop, continuous palette mix, `lyap≈0` ridges, spring.
- Added: dim pre-skip transient; six cobweb ticks in the pointer column.
- A packing: HDR density RGB + alpha.

## gen-chaos-game-ifs
- Kept: `ifsPoint` vertices, last-vertex tint, Sierpinski hole, existing SDF hero, spring.
- Added: late-iterate settle weight; screen-space edges of the generating triangle.
- A packing: ACES display RGBA.

## gen-conway-game-of-life
- Kept: Classic / Day&Night / HighLife, neighbor heat, still-life amber, spring.
- Added: `n<2` cold death vs `n>3` hot death; neighbor-centroid lean.
- A packing: raw alive, generation, activity, alpha.

## gen-art-deco-sky
- Kept: fluting, gold bands, drag searchlight, click halos, density / ascent / gold / fog.
- Added: repeating four-step ziggurat width; casement mullions on glass.
- Floor: display alpha from emission, metal, and halo coverage. A stays pre-ACES history RGB.
- JSON: `upgraded-rgba` added. Params unchanged.

## gen-alien-flora
- Kept: stem+cap, sway, SSS, organic alpha, density / sway / glow / color shift.
- Added: underside gill grooves; three spore spheres lifting off the cap rim (bass lift, treble glint).
- Floor: `textureLoad` of C; ACES only on `writeTexture`; organic alpha stored in A.
- JSON features: `upgraded-rgba`, `audio-reactive`, `mouse-driven`. Params unchanged.

## Gates
- Naga 10/10 (`wgsl_precommit_gate.py`).
- extraBuffer full-tree: 0 new violations.
- Dead sliders on these ten ids: 0 new.
- Catalog 1,373. Generative list 478.
- Jest: 741 passed, 6 failed, 1 skipped. The 6 suites fail on the pre-existing `./bridge/api.js` resolver.
- `SKIP_WASM_BUILD=1 npm run build` compiled.
- Real-GPU visual QA: external.
