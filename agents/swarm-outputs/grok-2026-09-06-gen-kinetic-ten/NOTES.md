# Notes — Grok simpler generative / kinetic ten (2026-09-06)

Cards: `BRIEFS.md`. Underscore-backed files kept (`gen_grid.wgsl`, `gen_grok4_*.wgsl`, `gen_grokcf_*.wgsl`). Saved `params` not rewritten.

| ID | Kept verbatim | A packing | Ideas in the diff |
|---|---|---|---|
| gen-grid | warp/density/thickness/palette; domainWarp; moiré; existing spring well | ACES display RGBA | Jacobian H/V stretch in `gridLine`; C phosphor at intersections |
| gen-grok4-life | SmoothLife + LV; four sliders; toroidal wrap | raw prey/pred/age/act | `predGrad` hunt; `edgeFlash` display + A.a |
| gen-grok4-perlin | erosion solver (not a Perlin rewrite) | raw erosion/sediment/water/uplift | display terraces; shoreline foam |
| gen-grok41-mandelbrot | Buddhabrot orbits; linear A | linear RGB + presence | set body; dwell bands on `c_pixel` |
| gen-grok41-plasma | Y(l,m) sphere; telemetry A | pattern, storm, limb, valid | zonal jets; storm eye |
| gen-grokcf-interference | Bessel drum (not Young slits) | raw u, r, φ, alpha | radial vs azimuthal node tint; Lambert on `u_total` |
| gen-grokcf-voronoi | FBM Worley | cell id, edge, F1 | F1 nucleus; F2−F1 crack |
| gen-fourier-epicycles | 1/n wheels; bassEnv trail pack | bassEnv, trail.rg, alpha | arm segments; pen ink |
| gen-dragon-curve | LSB Heighway; existing spring | ACES display RGBA | crease at `closestTurn`; gen thickness |
| gen-de-jong-attractor | de_jong iterate + hero tube | density, hue, tubeDepth, alpha | stretch tint; dwell rings |

No new extraBuffer owners. Springs only where HEAD already had them (grid, mandelbrot nav, dragon, de-jong).
