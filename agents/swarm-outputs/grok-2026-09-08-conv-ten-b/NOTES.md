# Convolution ten B — notes

Per shader: kept verbatim, packing, ideas in the diff.

| ID | Kept | Ideas in WGSL | Packing |
|---|---|---|---|
| `conv-guided-video-filter` | rad/eps/guide/mouse; q=aI+b | depth-mixed guide; `textureLoad` C for P | display RGBA |
| `conv-stochastic-stipple` | cell/threshold/sat/mouse well | paper ground; gradient ellipses | ACES display RGBA |
| `conv-structure-tensor-flow` | LIC steps/coherency/flow/vortex; palette | minor-eigenvector LIC; source-luma tint | ACES display RGBA |
| `conv-spiral-blur` | tightness/arms/samples/mouse center | φ arm spacing; Archimedean/log mix | ACES display RGBA |
| `conv-steerable-pyramid` | sigma/scale/boost/steer; g2 | h2 quadrature energy; source reconstruct | ACES display RGBA |
| `conv-reaction-convolution` | diffA/B/feed/mouse; GS step; A,B,blue store | C.rg persistence; Pearson k from feed | A,B,mixed-blue,activity |
| `conv-guided-filter-depth` | radius/eps/depth_influence/mouse | luma range on guide; photo-edge hold | ACES display RGBA |
| `conv-bilateral-grid-splat` | spatial/intensity/grid/mouse | joint depth range; adjacent-bin slice | ACES display RGBA |
| `conv-frequency-domain-notch` | bands/bw/boost_cut/mouse freq | oriented cosine; residual cut mix | ACES display RGBA |
| `conv-fractal-kernel` | radius/zoom/iter/mouse warp | boundary weight; DE glint | ACES display RGBA |

No new extraBuffer owners. No springs. Saved `params` unchanged.
