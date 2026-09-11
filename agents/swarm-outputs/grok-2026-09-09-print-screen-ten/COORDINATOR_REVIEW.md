# Coordinator review — print-screen / dither / mosaic ten

Contract: `docs/SHADER_UPGRADE_BATCH.md`. Fail a file if the Idea Card is missing, ideas are not pointable, KEEP VERBATIM broke, or the diff is ≥70% plumbing overlay.

| ID | Card before WGSL | Ideas pointable | KEEP VERBATIM | Overlay? | A packing | Params | Springs | Naga + audits | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| spec-blue-noise-stipple | yes | `pack`; `skipExtra` | R2 / dual+golden / held / splat | no | display RGBA (fixed) | exact | none | pass | **PASS** |
| stipple-render | yes | Sobel `tangent`; `wetMemory` C | Lloyd / wet / paper | no | display RGBA | exact | none | pass | **PASS** |
| halftone-reveal | yes | `gainC/M/Y/K`; `knockout` | 4 plates / loupe | no | display RGBA (fixed) | exact | none | pass | **PASS** |
| bayer-dither-interactive | yes | `ign`; `bayerG`/`bayerB` | bayer8 / error / phosphor | no | display RGBA (fixed) | exact | none | pass | **PASS** |
| halftone | yes | `hiSkip`; `overprint` | ellipDot / misreg / fibre | no | display RGBA | exact | none | pass | **PASS** |
| adaptive-mosaic | yes | `subdivide`; `mortar` | depth tiles / C mix / grout | no | display RGBA (C history) | exact | none | pass | **PASS** |
| crystal-mosaic | yes | `crease`; `came` | triangle grid / lighting | no extra CA | display RGBA | exact | none | pass | **PASS** |
| cyber-halftone-scanner | yes | `amCell`; `hardAmt` | 15/75/0/45 / scan / burst | no | display RGBA | exact | none | pass | **PASS** |
| posterize-neon-edges | yes | `holdFlat`; `ridge` | Sobel / quantize / neonHue | no | display RGBA | exact | none | pass | **PASS** |
| color-channel-weave | yes | ply B; C gap ghost | warp/weft / spring / B leftover | no new springs | display RGBA | exact | HEAD kept | pass | **PASS** |

Did **not** clone Wave Halftone ellipse+hex-rosette.

Gates: Naga 10/10, extraBuffer 0 new, dead sliders 0, catalog 1,362, Jest 652 pass / 6 fail (pre-existing WASM `bridge/api.js`), SKIP_WASM_BUILD=1 build green. Real-GPU visual QA: **external** (Cloud VM has no adapter).
