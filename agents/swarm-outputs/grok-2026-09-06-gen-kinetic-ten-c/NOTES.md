# Notes — Grok simpler generative / kinetic ten C (2026-09-06)

Cards: `BRIEFS.md`. Underscore-backed Hyper Warp kept (`gen_hyper_warp.wgsl` / `.json`, catalog id `gen-hyper-warp`). Saved `params` not rewritten (JSON diffs are `features` tags only).

| ID | Kept verbatim | A packing | Ideas in the diff |
|---|---|---|---|
| gen-echo-dunes | scale/wind/mirage/echo; FBM warp; ridge shadows; [133] bass env | HDR display RGBA | leeward slipface; along-wind streaks |
| gen-erosion-strata | erosion/density/veins/water; `li`/`lf` beds | ACES display RGBA | bedding contacts; intra-layer cross-beds |
| gen-ghost-flame | height/turb/cool/diff; [133..134] envelopes | raw T, fuel, vx, age | wick column; ignition blue edge |
| gen-fractured-monolith | spread/levitation/glow/rot; cell fracture | ACES display RGBA | cellId tint; crack-plane glint |
| gen-fractal-clockwork | scale/teeth/speed/material; sdGear; orbit spring | ACES display RGBA | tooth sparks; inter-gear mesh line |
| gen-fractal-ember-lattice | glow/size/scale/sparks; shatter/reform | disp.xy, seed, reform | triple junctions; cell-core heat |
| gen-hyper-labyrinth | 4D gyroid maze; neon history | persisted neon RGB + a | gyroid zero ridge; W-slice hue |
| gen-hyper-warp | intensity/speed/scale/detail; q/r warp; stabilizeHistory | raw HDR history | first-warp folds; \|r−q\| stretch |
| gen-hyper-rainbow-vortex | Rankine core + 1/r; spiral layers | HDR vortex RGBA | Rankine seam at r=a; braid beads |
| gen-hyperbolic-tessellation | Poincaré fold; Möbius mouse | HDR tessellation RGBA | ideal vertices; horocycles |

No new extraBuffer owners. Dunes keep bass envelope; flame keeps envelopes; clockwork keeps existing orbit spring.
