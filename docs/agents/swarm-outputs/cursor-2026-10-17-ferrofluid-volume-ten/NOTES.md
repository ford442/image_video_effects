# Notes — ferrofluid → volume ten (2026-10-17)

Prior ideas kept. Saved params byte-exact. Eight pasted headers migrated to `#include "_prelude.wgsl"`. Magnetic sculpture and the lotus already included it.

| Shader | Kept | A packing | New ideas in the diff |
|---|---|---|---|
| ferrofluid-spikes | Rosensweig lattice, magnet spring, eruptions, GGX | pre-ACES HDR history | valley pool; tip bead |
| gen-quantum-entangled-ferrofluid-engine | \|ψ\|² spikes, pair filaments, nodal contours | ACES display RGBA | measurement scar; pair neck |
| gen-sentient-ferro-silicate-swarm | assemble breath, facets, Si-O struts, curl wake | ACES display RGBA | fluid inclusions; shatter dust |
| gen-magnetic-ferrofluid-sculpture | Taylor cones, dipole chains, lean, thin-film | ACES display RGBA | contact meniscus; magnetite grain |
| volumetric-cloud-nebula | echo shell, absorbing cores, star streaks | ACES display RGBA | silver lining; virga |
| liquid-warp | RK4, Cauchy-Green, fold caustics, click rings | raw velocity / displacement / vorticity | stretch threads; vortex eye |
| gen-neuro-fluid-plasma-lotus | florets, flux ropes, veins, reconnection plumes | ACES display RGBA | anther pollen; petal scallop |
| gen-rainbow-smoke | CFL, rings, KH billows, raw smoke state | raw velocity, density, temperature | soot cap; ash fall |
| quantum-foam-pass1 | curl layers, voronoi, three-wave interference | raw warp.xy, pattern, cellBoundary | diffused voids; wavefront ridges |
| volumetric-depth-zoom | five-slice DOF, parallax, fog | display RGBA, no A history | slice drift; focal sheet |

`quantum-foam-pass1` still writes the same four field roles pass 2 reads. Diffusion Rate, previously unread, sets the void radius.

Gates: Naga 10/10, extraBuffer, dead sliders. Jest 158 passed on the full run; GraphLabPanel failed to lazy-load under load and passed when re-run alone. `SKIP_WASM_BUILD=1` build compiled. Ledger recorded with `--ids` for these ten.

Real-GPU visual QA: external.
