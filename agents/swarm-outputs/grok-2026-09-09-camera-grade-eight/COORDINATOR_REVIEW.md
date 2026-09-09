# Coordinator review — Camera / shutter / grade eight

Checklist vs `docs/SHADER_UPGRADE_BATCH.md` §9.

| Shader | Card before WGSL | Ideas in diff | KEEP VERBATIM | Not overlay | A packing | Params exact | Springs native | Naga |
|---|---|---|---|---|---|---|---|---|
| pp-ssao | yes | cosine hemisphere; bent-normal bleed | yes | yes | display RGBA | yes | no new | pass |
| long-exposure | yes | reciprocity fade; highlight plate | yes | yes | raw HDR A | yes | existing ripples | pass |
| tone-histogram | yes | spot meter; per-channel shoulder | yes | yes | display RGBA | yes | none | pass |
| temporal-halation-freeze | yes | red dye lag; C freeze-hold | yes | yes | halo RGB+env | yes | none | pass |
| double-exposure-zoom | yes | registration drift; highlight key | yes | not HDR bloom | display RGBA | yes | none | pass |
| night-vision-scope | yes | MCP scintillation; bright bloom | yes | yes | display RGBA | yes | existing [133..138] | pass |
| chromatographic-separation | yes | solvent Rf; capillary tailing | param roles kept | yes | display RGBA | yes | none | pass |
| double-exposure-hdr | yes | overlap bloom knee; pivot lock | yes | not registration | display RGBA | yes | none | pass |

Verdict: **pass** (structural). Real-GPU visual QA external.
