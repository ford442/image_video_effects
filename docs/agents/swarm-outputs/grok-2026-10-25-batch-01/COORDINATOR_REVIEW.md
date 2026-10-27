# Coordinator Review — Grok high (`grok/batch-01`, 2026-10-25)

Cards were written in `BRIEFS.md` before the WGSL edits. Each numbered idea is marked `// ── Idea:` in the shader.

| Shader | Verdict | Why |
|---|---|---|
| cellular-automata-rgba | pass | Holling divisor and Allee gate sit on the existing predation and `avgPlants`. Species packing and slider roles unchanged. |
| gen-conway-game-of-life | pass | Rings read the generation counter. Knife-edge uses the neighbor count. Rules, spring, and prior tints stay. |
| gen-bioluminescent-reaction-diffusion | pass | Veins use the Laplacian's A samples. Bleach uses luciferin age and the existing deep-water color. Solver unchanged. |
| gen-dla-copper-deposition | pass | Facets follow stored oxidation. Crowding uses `activity * exposed`, separate from spark and front sheen. |
| wave-equation | pass | Capillary term damps the existing velocity. Whitecaps write the existing foam channel. Only §12.2D use in the batch. |
| slime-mold-on-video | pass | Decay is spatially gated by food. Deposit uses drift · ∇food. Packing unchanged. |
| galaxy-compute | pass | Dust lane reuses the log-spiral phase. Blackbody rides the existing bulge temperature. Only §12.2F blackbody. Slider mapping not retargeted. Prelude, ACES, and A write are floor. |
| gen-verlet-cloth-wind | pass | Selvage damps free side columns of the same height field. Slack uses the stretch already computed for sheen. |
| gen-phyllotaxis-galaxy-spiral | pass | Bracts are streaks on the existing floret positions. Meristem tints large-`r` florets. PHI and prior galaxy ideas stay. |
| gen-plasma-mandala | pass | X-point is filament × ring. Cavity is outside the ring; the Debye sheath stays inside. |
| gen-fractal-tree-growth | pass | Reaction wood thickens the compressed side of the existing bend. Lenticels sit on segment `h` between rings. |
| gen-hyperbolic-tree | pass | Rim heat is branch glow near the boundary. Sector tint is the existing 7-fold in negative space only. |
| gen-fireworks-dahlia-burst | pass | Tip lobes use the petal perpendicular. Pollen uses `sparkPos` gravity from the pistil. |
| particle-dreams-hdr | pass | Bloom subtracts spread from the source. The eye uses layer `dist`. Only energy-conserving bloom in the batch. HDR packing kept. |
| nano-assembler | pass | The front is Assembly Progress as a position. Vacancies are cell-hash holes that close at high progress. |

## §9 / §12.7 checklist

- [x] Idea cards and mechanism notes exist in `BRIEFS.md`
- [x] Each new idea is pointable at a `// ── Idea:` comment
- [x] Prior kernels, modes, and param roles kept
- [x] Diffs are the two ideas plus, where needed, prelude / ACES / A write (galaxy, particle-dreams)
- [x] No spring+ripple+IQ stamp shared across the batch
- [x] A packing matches how C is read (raw fields stay raw; display writes are display)
- [x] Saved `params` unchanged
- [x] Springs left only where they already existed (Conway)
- [x] Naga 15/15, extraBuffer clean, dead sliders clean
- [x] Vitest 1433 passed. Two `RendererManager` device-loss tests failed because the WebGPU probe never recovered (`probe pipeline failed` on this VM). They do not load these shaders.
- [x] `SKIP_WASM_BUILD=1 npm run build` succeeded. Visual QA was not run.
- [x] §12.2 rows: dispersion on wave-equation only; blackbody on galaxy-compute only; energy-conserving bloom on particle-dreams-hdr only

Batch size is 15, above the contract ceiling of 12. The cards do not share a formula pair, which is the failure mode that ceiling is there to prevent.
