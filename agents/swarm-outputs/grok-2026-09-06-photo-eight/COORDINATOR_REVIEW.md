# Coordinator review — photo / print / grade eight

Fail list from `docs/SHADER_UPGRADE_BATCH.md` §9.

| Shader | Card before diff | Ideas pointable | KEEP VERBATIM | Diff not overlay | Packing | Params | Springs only if native | Naga |
|---|---|---|---|---|---|---|---|---|
| pp-bloom | yes | extractBright; streak loop | yes | yes | display | exact | none | pass |
| pp-tone-map | yes | mix chain; applyContrastHue | yes | yes | display | exact | none | pass |
| analog-film-degrade | yes | gR/gG/gB; weave/hair; textureLoad C | yes | yes | display | exact | none | pass |
| color-blindness | yes | mixMat; assist hatch | yes | yes | display | exact (`unused` kept) | none | pass |
| crumpled-paper | yes | fibre; prev.a iron | yes | yes | RGB+height | exact | none (mouse already irons) | pass |
| retro-gameboy | yes | lcd mask; dataTextureA | yes | yes | display | exact | none | pass |
| conv-bilateral-dream | yes | lumaDist+depthDist; dataTextureA | yes | yes | display | exact | none (existing ripples kept) | pass |
| tilt-shift | yes | hex; hi bloom | yes | yes | display | exact | none | pass |

**Pass.** Batch is an example of incremental ideas on photo/print/grade filters, not a hygiene stamp.

Gates: Naga 8/8, extraBuffer 0 new, dead sliders 0, lists + unified manifest 1,359, params exact vs HEAD, Jest 91/94 (3 pre-existing WASM `bridge/api.js` resolve failures), `SKIP_WASM_BUILD=1 npm run build` compiled. Real-GPU visual QA external.
