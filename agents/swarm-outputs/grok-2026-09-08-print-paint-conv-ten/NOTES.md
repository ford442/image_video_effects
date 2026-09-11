# Print / paint / convolution ten — notes

Per shader: kept verbatim, packing, ideas in the diff.

| ID | Kept | Ideas in WGSL | Packing |
|---|---|---|---|
| `conv-non-local-means` | patch/search/h/overdrive; SSD NLM; mouse h-well | luma+chroma SSD in `patchDistance`; `alongEdge` tangent weight | ACES display RGBA (A now written; C was already color) |
| `conv-anisotropic-diffusion` | kappa/dt/iterations/mouse heat; 4-neighbor PM | `tukeyConductivity` mix; `followH`/`followV` coherence | ACES display RGBA |
| `conv-difference-of-gaussians-cascade` | 4-scale DoG; cosine palette; mouse emphasis | `tanh` XDoG mix with source; `zeroCross` Marr–Hildreth | ACES display RGBA |
| `conv-morphological-erosion-dilation` | min/max SE; mouse elongate; top-hat | `blackHat`; `skeleton` local-max along SE | ACES display RGBA |
| `conv-gabor-texture-analyzer` | 0/45/90/135 bank; mouse rotate; palette | even/odd quadrature energy; `domTheta` grain | ACES display RGBA |
| `watercolor-bloom` | 13-tap bloom; wet-edge; paper; C dry advection | valley granulation; `backrunAmt` cauliflower from C | display RGBA (B leftover kept) |
| `film-cross-process` | per-channel S-curve; skew; vignette; existing enlarger spring | per-channel grain seeds; highlight `xproHi` cyan-green | ACES display RGBA |
| `engraving-stipple` | hatch/cross/contour; burin; click rings | `roulette` dots; `taper` from `|grad|` | HEAD telemetry A |
| `rotoscope-ink` | Sobel; posterize; tapered stroke | `inkWeight` from edge mag; `holdFlat` cel snap | HEAD telemetry A |
| `encaustic-wax` | 3 strata; melt displace; SSS/spec | `waxBloom` on cool; held `scrape` thins wax | HEAD telemetry A |

No new extraBuffer owners. Springs only where HEAD already had them (`film-cross-process` enlarger). Saved `params` unchanged; `updatedParams` aligned by index on defs that lacked them.
