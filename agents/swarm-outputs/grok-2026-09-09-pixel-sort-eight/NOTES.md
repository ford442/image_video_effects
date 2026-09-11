# Pixel-sort eight — notes

Per shader: kept verbatim, packing, ideas in the diff.

| ID | Kept | Ideas in WGSL | Packing |
|---|---|---|---|
| `pixel-sorter` | direction / reverse / intensity / threshold; luma+hue key; cursor Gaussian; wavelength tint | Asendorf walk `for i<=10` close on luma; `seam` when next sample drops | ACES display RGBA. Prev-mouse extraBuffer[133..134] (1-frame delay, not a spring). Stopped writing B. Exact C. |
| `pixel-sort-explorer` | thresh / radius / dir / smooth; interval walk; wobble; scan sweep; spotlight | `holdThresh` / `heldLum` from C.a; `mix(sc, prevC.rgb, …)` persist | ACES display RGBA (HEAD never wrote A) |
| `spectral-flow-sorting` | flow_sensitivity / sort_threshold / freq_influence / smoothing; LK; mouse gravity | `textureLoad` LK; Asendorf `sortAlongFlow` brightest-until-close | raw RGB in A for next LK. ACES writeTexture only. Killed `zoom_config.x` as audio. |
| `hybrid-spectral-sorting` | sort_threshold / spectral_bands / displacement / hue_shift; vertical band; existing palette | Y walk inside `floor(uv.y*bands)`; `plasmaBuffer[0].xyz` | ACES display RGBA (HEAD wrote no A) |
| `flow-sort` | flowStrength / sortPasses / strandPersist / threshold; perp Sobel flow; mouse vortex | LIC two extra taps; interval gate on upstream/downstream swaps | ACES display RGBA. Stopped writing B (HEAD stored flow in A and read C as color). Exact C persist. |
| `magnetic-luma-sort` | pull / threshold / decay / attract-repel; extraBuffer spring; exact C; click vortices | `tangent * speed * 0.35` dipole; `fract(luma*6)` domain gate | ACES display RGBA (HEAD already). Spring kept. |
| `pixel-sort-radial` | stretch / thresh / radius / dir; radial dir; existing CA / runners | radial walk close on luma; `ringSeam` at next-below-thresh | ACES display RGBA |
| `mouse-pixel-sort` | threshold / length / direction / invert; mouse loupe; existing curl/attractor/voronoi | V/H Asendorf walk; exact-C ghost mix | ACES display RGBA (HEAD packed telemetry, never read C) |

No new extraBuffer springs. `pixel-sorter` only stores a 1-frame mouse delay in [133..134]/[138] so the existing mouse-velocity axis still works (HEAD wrote mouse into B, which A→C overwrites). Saved `params` unchanged; `updatedParams` aligned by index.

Did **not** take Batch 58–66 overlay files (`pixel-sort-glitch`, `glitch-pixel-sort`, `scanline-sorting`, `spectral-glitch-sort`). Did **not** restamp explorer’s scan-sweep onto the other seven.
