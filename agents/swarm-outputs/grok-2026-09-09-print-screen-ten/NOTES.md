# Print-screen / dither / mosaic ten — notes

Per shader: kept verbatim, packing, ideas in the diff.

| ID | Kept | Ideas in WGSL | Packing |
|---|---|---|---|
| `spec-blue-noise-stipple` | R2 jitter; dual+golden dots; held density; click splatter; param roles | `pack` jitter shrink; `skipExtra` from 4-neighbor ink | ACES display RGBA (was mask-in-A, C unused) |
| `stipple-render` | Lloyd jitter; wet bleed; paper; ACES; param roles | Sobel `tangent` hatch; `wetMemory` from exact C | ACES display RGBA |
| `halftone-reveal` | 4 rotated CMYK plates; loupe; paper; param roles | `gainC/M/Y/K` per-plate; `knockout` highlight holes | ACES display RGBA (was telemetry A) |
| `bayer-dither-interactive` | bayer8 table; neighbor error; phosphor; param roles | `ign` mix; `bayerG` +4 / `bayerB` +2 | ACES display RGBA (was telemetry A) |
| `halftone` | ellipDot; plate offsets; paperGrain; mono/CMYK | `hiSkip` / `skipContrast`; `overprint` gain | ACES display RGBA |
| `adaptive-mosaic` | depth tiles; mouse focus; exact C mix; grout runners | `subdivide` from luma variance; `mortar` from 4 neighbors | display RGBA (C is color history) |
| `crystal-mosaic` | triangle grid; existing lighting stack; param roles | `crease` along u=v; `came` grout | ACES display RGBA (was premultiplied write) |
| `cyber-halftone-scanner` | 15/75/0/45 angles; scan/glitch/burst/mouse bloom | `amCell` circular AM; `hardAmt` scan hard-dot | ACES display RGBA |
| `posterize-neon-edges` | Sobel; luma quantize; neonHue; FBM; param roles | `holdFlat` band-hold; `ridge` neon | ACES display RGBA |
| `color-channel-weave` | warp/weft; extraBuffer[133..138] spring; pluck; leftover B | two-ply `warpBrightB`/`weftBrightB`; exact-C gap ghost | display RGBA; B leftover kept |

No new extraBuffer owners. Springs only where HEAD already had them (`color-channel-weave`). Saved `params` unchanged; `updatedParams` aligned by index on defs that lacked them.

Did **not** stamp Wave Halftone’s ellipse+hex-rosette onto this family.
