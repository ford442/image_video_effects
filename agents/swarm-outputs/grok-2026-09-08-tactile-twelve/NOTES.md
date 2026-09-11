# Tactile twelve — notes

Per shader: kept verbatim, packing, ideas in the diff.

| ID | Kept | Ideas in WGSL | Packing |
|---|---|---|---|
| `kintsugi-repair` | shard/gold/shatter/sparkle; nearest Voronoi; gold runners | `f2Ridge` T-junctions; `meniscus` bead | ACES display RGBA (was unused telemetry) |
| `plastic-bricks` | density/stud/relief/bevel; per-brick sample | `tubes` underside rings; `knit` weld line | ACES display RGBA |
| `wave-halftone` | hex dots; Wave Speed stays chromaticAmt | elliptical `hexDist`; 15° `maskB` rosette | ACES display RGBA |
| `spec-histogram-equalize` | CLAHE clip/strength/tileBlend/colorPreserve; mouse lens | `shoulder` highlight rolloff; exact-C mix | ACES display RGBA |
| `pin-art-3d` | density/radius/push/metallic; sphere-cap | `neighborOcc`; `shaftMask` | ACES display RGBA (A now written) |
| `triangle-mosaic` | scale/rotation/twist/mix; triangle grid | `grout`; centroid `tilt` | ACES display RGBA |
| `polka-wave` | four CMYK angles; invertRipple | `gain` dot swell; grid rides wave | ACES display RGBA |
| `honey-melt` | hex A/B; melt radius | `sag` gravity; `meltHeld` capillary | ACES display RGBA (A now written) |
| `slime-drip` | speed/viscosity/amount/tint; wipe | `yStretch` gravity; C `drip` hang | raw fields; ACES on writeTexture |
| `velvet-scatter-bloom` | scatter/bloom/subsurface/lightAngle | `napSheen`; held `crush` | ACES display RGBA |
| `page-curl-interactive` | radius/shadow/feedback/depth; cylinder | `backLin` peek; `fiber` along theta | ACES display RGBA |
| `fabric-step` | Verlet; stiffness/tear/gravity/damping | `warp`/`weft` weave; `textureLoad` C | raw sim A `(pos, prevPos)` |

No new extraBuffer owners. Saved `params` unchanged; `updatedParams` aligned on defs that lacked them.
