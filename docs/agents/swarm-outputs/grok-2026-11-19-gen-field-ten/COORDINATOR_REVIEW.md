# Coordinator review — generative field ten (2026-11-19)

Cards were written in `BRIEFS.md` before the WGSL edits.

| Shader | Card | Ideas pointable | Keep holds | Not a header-only diff | No shared overlay | Packing | Params | Naga |
|---|---|---|---|---|---|---|---|---|
| gen-plasma-psychedelic-wormhole | yes | yes | yes | yes | yes | yes | unchanged | valid |
| gen-lichtenberg-storm | yes | yes | yes | yes | yes | yes | unchanged | valid |
| gen-galactic-aether-crystal-geode-core | yes | yes | yes | yes | yes | yes | unchanged | valid |
| gen-bifurcation-diagram | yes | yes | yes | yes | yes | yes | unchanged | valid |
| gen-thermal-rainbow-topography | yes | yes | yes | yes | yes | yes | unchanged | valid |
| gen-astral-plasma-accretion-forge | yes | yes | yes | yes | yes | yes | unchanged | valid |
| lorenz-attractor-flow | yes | yes | yes | yes | yes | yes | unchanged | valid |
| gen-topology-flow | yes | yes | yes | yes | yes | yes | unchanged | valid |
| gen-metaball-soft-body | yes | yes | yes | yes | yes | yes | unchanged | valid |
| gen-sentient-liquid-neon-fractal-heart | yes | yes | yes | yes | yes | yes | unchanged | valid |

Formula names: Cauchy on the wormhole only. Fresnel–Schlick on the metaball only. March-step occlusion on the geode only (the step counter, not the 5-tap map AO). No other §12.2 row.

Springs and click fronts were left where the file already had them (Lichtenberg electrode, bifurcation pointer lens, Lorenz ripples, metaball impulses). None were added.

`extraBuffer` audit: pass (0 new writes into 0..132). Dead-slider audit: pass on the six definitions that declare top-level `params`. The other four keep all four `zoom_params` reads (topology x/y/z/w, Lichtenberg x/y/z/w, heart x/y/z/w, thermal via the `params` alias).

Prelude: `gen-topology-flow` and `lorenz-attractor-flow` removed from `src/contracts/prelude_migration.json` `pending`.
