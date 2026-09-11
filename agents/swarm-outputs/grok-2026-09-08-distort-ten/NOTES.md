# Distortion / warp ten — notes

Per shader: kept verbatim, packing, ideas in the diff.

| ID | Kept | Ideas in WGSL | Packing |
|---|---|---|---|
| `sine-wave` | amp/speed/scale/chroma; packets; click fronts; crest CA | standing-wave nodes; Stokes drift | telemetry offset.xy, crest, alpha |
| `parallax-shift` | strength/layer-count/depthWeight/focus; mouse origin | occlusion peel; focus-plane CoC | ACES display RGBA |
| `perspective-tilt` | tilt/distance/pitch/scale; ray–plane | vanishing falloff; Scheimpflug graze | ACES display RGBA |
| `interactive-rgb-split` | strength/falloff/mode/angle; rad vs dir | wavelength-scaled R/G/B split; lateral vs longitudinal | ACES display RGBA |
| `radial-rgb` | k1/k2/anamorphic/dispersion; Brown lens | radial chromatic k1; mustache k3 | ACES display RGBA (B diagnostics kept) |
| `elastic-surface` | elasticity/tension/speed/depth; Hooke+Laplacian | Poisson contraction; exact C neighbors | raw disp.xy, vel.xy |
| `vortex-distortion` | Γ/ν/KH/aberration; Lamb-Oseen; KH m=6 | streamline smear; source-tied vorticity | vel.xy, vorticity, speed |
| `chromatic-swirl` | strength/radius/aberration/animate; percent² | angular chromatic; continuous spin | telemetry dist/angle/aberration/alpha |
| `infinite-zoom` | speed/distortion/rotation/iterations; Möbius | mouse pole c; log-polar seam | ACES display RGBA |
| `pixel-storm` | strength/chaos/trail/radius; spring eye [133..138] | luma debris; exact-C trail | ACES display RGBA |

No new extraBuffer owners. Pixel-storm spring eye kept. Saved `params` unchanged.
