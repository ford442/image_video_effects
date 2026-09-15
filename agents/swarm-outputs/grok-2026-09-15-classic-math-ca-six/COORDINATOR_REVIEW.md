# Coordinator review — classic math / CA leftover six (2026-09-15)

Checklist from `docs/SHADER_UPGRADE_BATCH.md` §9.

| ID | Card before WGSL | Ideas pointable | KEEP VERBATIM | Diff not ≥70% boilerplate | Distinct overlay | A packing matches C | params exact | Springs native-only | Naga |
|---|---|---|---|---|---|---|---|---|---|
| gen-rgb-diffraction | yes | blazeEnv; freq*2 ghosts | yes | ideas in slitIntensity + loop | yes | display RGBA | updatedParams unchanged; params added (were missing) | no spring | **OK** |
| gen-verlet-cloth-wind | yes | warp/weft; crease from lap | yes | lighting kept | yes | lattice raw / off-lattice display | params added (were missing) | no new spring | **OK** |
| gen-sierpinski-tetrahedron | yes | F centroids; genIdx | yes | IFS kept | yes | telemetry A | params added (were missing) | extraBuffer[0..5] removed | **OK** |
| gen-cellular-automata-tapestry | yes | weave; Pearson glaze | yes | GS kernel kept | yes | raw A/B | params byte-exact | no spring | **OK** |
| gen-turing-morphogenesis | yes | halo; front | yes | closed-form kept | yes | display RGBA | params added (were missing) | no spring | **OK** |
| gen-buddhabrot-aura | yes | nebulaRGB; interior | yes | z²+c kept | yes | display RGBA | params byte-exact | no spring | **OK** |

Skipped (not this batch): langton/klein/koch/phyllotaxis/newton (already 09-14 Ideas), percolation extraBuffer[0..], BZ/protocell/hyperbolic-tree (idea-rich metadata), physarum agents, tropism mycelium-network.

Real-GPU visual QA: external (no adapter in Cloud VM).
