# Notes — grid → hyper ten (2026-10-17)

Second pass. Prior ideas kept. Saved `params` byte-exact. Nine pasted headers migrated to `#include "_prelude.wgsl"` (infrastructure). Hopf already included it.

| Shader | Kept | A packing | New ideas in the diff |
|---|---|---|---|
| gen-grid | domain warp, Jacobian lattice, phosphor, spring well, click pulses | ACES display RGBA | cell-field wash; Jacobian crease |
| gen-grok4-life | SmoothLife kernel, hunt fronts, edge flash, extinction bloom | raw prey/predator/age/activity | carrying dimple; phase-portrait tint |
| gen-grok4-perlin | incision, terraces, shoreline foam, raw fields | raw erosion/sediment/water/uplift | talus apron; drainage rills |
| gen-grok41-mandelbrot | orbit histogram, rainbow, set body, dwell bands, linear history | linear RGB + presence | slow-escape comet; antenna tip |
| gen-grok41-plasma | Ylm, jets, storm eye, Rayleigh limb | raw pattern/storm/limb/validity | polar hood; belt boundaries |
| gen-grokcf-interference | Bessel modes, node tint, Lambert, strikes | raw u/r/phi/alpha | antinode disks; radial beat |
| gen-grokcf-voronoi | F1 nucleus, F2−F1 crack, starfield | cell id, edge mask, F1 | site comet; F1≈F2≈F3 junctions |
| gen-hopf-fibration-fiber-bundle | gaps, beads, S² inset, horizon, hot crossings | ACES display RGBA | equatorial generator; longitudinal seam |
| gen-hyper-labyrinth | gyroid SDF, midline, W-slice hue, neon history | raw HDR neon + alpha | cul-de-sac chambers; floor treads |
| gen-hyper-warp | fold caustic, stretch, isolines, prismatic C loads | pre-ACES HDR history | radial flux; octave grit |

Gates: Naga 10/10, extraBuffer 10/10, dead sliders 10/10, shader lists regenerated. Jest 157 passed on the full run; ShaderScanner and ShaderValidator failed under load (timeout / duplicate text) and passed when re-run alone. `SKIP_WASM_BUILD=1` build compiled. Ledger recorded with `--ids` for these ten.

Real-GPU visual QA: external. Cloud VM has no hardware GPU.
