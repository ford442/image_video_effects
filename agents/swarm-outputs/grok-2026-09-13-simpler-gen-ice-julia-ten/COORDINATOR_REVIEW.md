# Coordinator review — Grok-1 simpler generative ten (ice → Julia)

Date: 2026-09-13

Checklist per `docs/SHADER_UPGRADE_BATCH.md` §9.

| ID | Card before WGSL | Ideas pointable | KEEP VERBATIM | Diff not ≥70% plumbing | No shared overlay | A packing honest | params exact | Springs only if native | Naga + extraBuffer + dead sliders | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| gen-ice-crystal-lattice | skip (09-09) | — | — | — | — | — | — | — | n/a | SKIP |
| gen-ifs-fractal-flame | yes | xfColor; fang affine | yes | ideas in loop | not classic log+spherical | display RGBA | exact | none new; bass [133] | pass | PASS |
| gen-interference-moire-field | skip (09-09) | — | — | — | — | — | — | — | n/a | SKIP |
| gen-inverse-mandelbrot | yes | stalkMin; argBand | yes | stalks+arg in kernel | not Julia Classic DE | HDR A | exact | none | pass | PASS |
| gen-iris-bloom-fractal | skip (09-09) | — | — | — | — | — | — | — | n/a | SKIP |
| gen-islamic-geometric-tiling | skip (09-09) | — | — | — | — | — | — | — | n/a | SKIP |
| gen-islamic-star-rose | yes | nested φ; 10-fold rose | yes | not tiling dart stamp | distinct from 09-09 tiling | display RGBA | exact | none | pass | PASS |
| gen-isometric-city | yes | dPodium/dTower; occ | yes | massing+windows | not voxel mortar | display RGBA | exact | none | pass | PASS |
| gen-julia-set | yes | trap lerp; velTrap | yes | not Classic DE/stripe | no Pickover (inverse owns stalks) | packing lie fixed | exact | none | pass | PASS |
| gen-julia-set-classic | skip (09-09) | — | — | — | — | — | — | — | n/a | SKIP |

**Batch:** 5 upgraded, 5 skipped (already idea-stamped). Did not substitute IDs.

**Gates:** Naga 5/5, precommit 5/5 extraBuffer 0, dead sliders 0 on scanned defs, catalog 1,365 unified / 1,378 defs, SKIP_WASM_BUILD=1 build green. Jest 689 pass / 6 fail = pre-existing WASM `bridge/api.js`. Real-GPU visual QA external.
