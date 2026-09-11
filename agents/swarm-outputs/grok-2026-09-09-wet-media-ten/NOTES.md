# Wet media / charcoal / ink / paint ten — notes

Per shader: kept verbatim, packing, ideas in the diff.

| ID | Kept | Ideas in WGSL | Packing |
|---|---|---|---|
| `charcoal-rub` | hardness / texture / reveal / fade; paper fbm; mouseDown brush; C.r mask | `fiberUV` valley catch; `vineDust` halo | raw A.r reveal (HEAD) |
| `charcoal-rub-diffusion` | Perona-Malik kappa/dt; mouse heat; charcoal conversion | `vineStroke` along diffused Sobel; `kneadSkip` highlight reserve | raw A.r reveal (HEAD) |
| `alpha-paint-thickness` | pigment+thickness A; hue brush; click splatters; wash/medium/thick | `knifeRidge` along thickness grad; `weave` tooth in thin wash | raw pigment+thickness. Wired z/w. Exact C |
| `ink-diffusion` | spread/decay/turbulence/density; curl+vorticity; wet-edge spec; ACES | `fiberDir` steered vel; `nijimi` laplacian on wetEdge | raw ink/vel (HEAD). Exact C |
| `sim-ink-diffusion` | 3-channel Gray-Scott; Wolfram F/k; paperTexture | anisotropic `laplacian9` along fiber; `ring` coffee-ring V | raw U.rgb + V.a. Viscosity into Du/Dv |
| `ink-bleed-fluid` | vel/pressure/ink; Jacobi; vorticity; mouse/ripple inject | `valley` capillary + peak vel damp; `wetRim` darken | raw vel/pressure/ink. Exact C |
| `mouse-paint-splatter` | sample-at-mouse; dry/spread; click splash; (0,0) mouse stash | `satMask` cast-off; `dryCrack` craquelure | paint.rgb + wetness.a (HEAD) |
| `alpha-fluid-simulation-paint` | NS packing; audio visc; Jacobi; vorticity | `densGrad` surface tension; density-gradient spec | raw vel/pressure/dye (HEAD) |
| `alpha-watercolor-wetness` | water/pigment A; gravity; existing granulation/backrun | `cockleUV` from water Laplacian; `salt` on leaving water | raw pigment+water. Wired w. Exact C |
| `artistic_painterly_oil` | Kuwahara; quantize; impasto height; canvas | `scumble` skip on peaks; wet-in-wet from exact C | pre-ACES color + thickness. ACES write only |

No new extraBuffer owners. No springs added. Saved `params` unchanged; `updatedParams` aligned by index.

Did **not** stamp watercolor-bloom granulation+backrun as the upgrade (watercolor already had those). Did **not** take `mouse-ink-bleed` (idea-rich + extraBuffer[0..7]).
