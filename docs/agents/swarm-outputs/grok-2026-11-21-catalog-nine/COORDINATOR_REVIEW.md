# Coordinator review — catalog nine (2026-11-21)

Reviewed against `BRIEFS.md`. Naga 9/9. Precommit 9/9 (extraBuffer 0, pasted headers 0). Dead sliders 0 on these nine.

| Shader | Card before edit | Both ideas in the WGSL | Keep verbatim | Packing matches C | Params exact | Springs only if already there | Verdict |
|---|---|---|---|---|---|---|---|
| tensor-flow-sculpt | yes | anisotropic yield; rake striations | tensor, frequency split, LIC, sheen, creep | display history | yes | no spring | pass |
| physarum | yes | leading-edge glint; food bite | Eulerian update untouched | raw (trail, mx, my) | yes | no spring | pass |
| vhs-tracking | yes | Schmitt lock (§12.2B); field interlace (§12.2B) | walk, azimuth, DOC, chroma phase | row state; A.g is now the lock | yes | existing spring kept | pass |
| plasma | yes | bowed filaments; field afterglow | eight orbs, corona, shadow | envelope in A.a; display RGB | yes | no spring | pass |
| chroma-lens | yes | Cauchy (§12.2F); zonal r²(1−r²) | seven taps, rim seam, astigmatism | pre-tone-map RGBA | yes | no spring | pass |
| datamosh-brush | yes | DCT quant (§12.2B); held motion vector | DC hold, mosquito, spring smear | display RGBA | yes | existing spring kept | pass |
| steamy-glass | yes | low-pane linger; contact line | four-field sim, runoff, beads | raw sim | yes | no spring | pass |
| voronoi | yes | feature gather; seed pits | Worley, drift, palette, sparkle | display RGBA | yes | no spring | pass |
| digital-decay | yes | dropout bursts (§12.2B); pointer shear | block tear, stuck row, ghost | display RGBA | yes | existing spring kept | pass |

Formula de-duplication: Schmitt lock, field interlace, Cauchy, DCT quant, and dropout bursts each appear on one file. No file shares both formulae with another file in this batch.

`chroma-lens`, `steamy-glass`, and `voronoi` were migrated to `#include "_prelude.wgsl"` before the idea edits. That migration is not an idea and is not why `Upgraded:` moved.

Vitest 2019 passed, 1 skipped, before the production build. `npm run build` succeeded. The build re-encoded `public/shader-search-index.json` and the ranking test then missed `crt-phosphor-decay`. That index was restored, and the ranking test passed again. Alias `generated_at` date bumps were reverted. Regenerated `reports/` audits were discarded; `reports/shader-upgrade-ledger.json` was kept.

`verify:shaders:fix` passed 9 of 11 gates. The two failures are this branch versus `origin/main`: prelude pending still lists shaders that paste a header here, and the changed-file precommit flags those same 21 pasted headers. None of the nine in this batch are in that list.

Real-GPU visual QA: external.
