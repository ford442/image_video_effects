# Notes — cursor/batch-30 physical materials (2026-11-01)

Second pass on files that already had a material look. New ideas are additive. Saved `params` stay byte-exact. No new spring, and no shared formula except the two photographic rows on `texture`.

`kinetic-tiles` is `public/shaders/kinetic_tiles.wgsl`.

| Shader | Kept verbatim | A packing | Ideas in the diff |
|---|---|---|---|
| crumpled-paper | fbm5 height and ridge, mouse ironing disk, C.a height memory, crease-tangent fibre, Crumple Scale / Depth / Smooth Radius / Light Strength | display RGB + height in A.a. ACES on the display write | facet cockle; calender sheen |
| paper-burn | burn in A.r, 8-neighbour fibrous diffusion, held pointer and click ignition, ember / char / hole, Burn Speed / Spread / Char Width / Reset | raw burn in A.r. ACES on the display write | scorch browning; char curl |
| plastic-bricks | half-brick offset, stud and mortar, underside tubes, injection knit, plastic BRDF, pointer deconstruct | ACES display RGBA (C unread) | stud pip; parting line |
| pin-art-3d | luma height, pointer push, bass vibration, sphere cap, neighbour occlusion, shaft | ACES display RGBA (C.rgb is a short colour trail) | friction steps; cap rim |
| bubble-wrap | hex lattice, pop flag and time in A.rg, 6-neighbour sympathetic pop, collapse and jiggle, refraction. Fourth slider stays the highlight | raw pop flag, pop time, neighbour count in A.rgb. ACES on the display write | seal web; membrane flash |
| interactive-origami | three triWave creases, fold parity, wet-fold shadow, runners, click rings | ACES display RGBA (C.rgb is a short colour trail) | score line; reverse face |
| kintsugi-repair | Voronoi edge, F2 T-junction, gold width, shatter shift, sparkle, meniscus | ACES display RGBA (C unread) | urushi bed; glaze lip |
| venetian-blinds | slat count, openness, slat brightness, phase, mouse-Y openness, bass snap, mids glint, downward gap shadow | ACES display RGBA (C unread). This file had no ACES before | tilt view; ladder tape; slat bounce |
| kinetic-tiles | grid, spring in extraBuffer[133..138], domino row delay, grout compression, rotation and scale, click fronts, bevel glint | linear pre-ACES trail RGB in A (C.rgb is that trail). ACES on writeTexture only | leading lip; mortar joint |
| interactive-emboss | luma gradient, Strength / Intensity / Color Mode / Emboss Depth, self-shadow march, Blinn glint, click stamp | ACES display RGBA (C.rgb is the light trail) | ink squeeze; tooled groove |
| texture | 3×3 Laplacian, box unsharp, Temporal Blend, Edge Strength and Unsharp Amount as the gains, golden vignette, treble sparkle, voronoi glitch | ACES display RGBA. C is textureLoad colour history | structure-tensor gain (§12.2A); anti-halo envelope (§12.2A) |
| zipper-reveal | spread, tooth size, angle, tooth amplitude, staggered teeth, puller, weave, metal spec | ACES display RGBA (C unread) | binding stitch; lip shadow |

Formula use: structure tensor and anti-halo only on `texture`. No other §12.2 row in this batch. No new spring (kinetic-tiles keeps the one it had).

Floor: `#include "_prelude.wgsl"` on all twelve. `paper-burn`, `bubble-wrap`, `venetian-blinds`, and `interactive-emboss` had pasted headers; `migrate_to_prelude.py` swapped those before the idea edits. 16×16. Exact C where C is read (`texture` no longer samples C with the filtering sampler). `x-meta.upgrade.params` added for venetian-blinds and texture. `upgraded-rgba` added to paper-burn features. Saved params unchanged.

Gates: Naga 12/12, precommit 12/12, extraBuffer 0 new, dead sliders 0 new on these twelve, lists regenerated. Vitest 180 files / 1532 passed (1 skipped). `SKIP_WASM_BUILD=1 npm run build` succeeded. Real-GPU visual QA is external.
