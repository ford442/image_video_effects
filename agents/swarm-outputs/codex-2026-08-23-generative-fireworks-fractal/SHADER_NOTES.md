# Shader notes

| Shader | Upgrade |
| --- | --- |
| Ring Shell | Removed the secondary feedback write; the established HDR halo, three-band temperature, held-pointer shell, ACES, depth, and semantic A history remain intact. |
| Roman Candle | Added mid-band flight flutter, preserved held and discrete click candles, and moved semantic display history exclusively to A. |
| Smoke Bloom | Corrected normalized mouse space, replaced filtered C bloom with a five-tap exact-load kernel, removed B writeback, and generated luminance/smoke depth. |
| Strobe Shell | Corrected normalized mouse space, removed B writeback, and replaced zero depth with flash-luminance depth. |
| Willow Cascade | Preserved advected exact-load willow trails and stored their semantic alpha in A. |
| Wind Ripple | Preserved click shock fronts, held shells, wind advection, and stored semantic alpha in A. |
| Fluffy Raincloud | Replaced unsupported WGSL `mod()` with a floor-based time wrap and removed derived telemetry from B; raw A packing remains `[density, velocity.x, velocity.y, moisture]`, with spring state only in `[133..136]`. |
| Fourier Epicycles | Added an invocation bounds guard, pixel-center UVs, and exact C state loads while preserving packed A state `[bass envelope, trail R, trail G, alpha]`. |
| Spore Network | Added ACES, exact-load bioluminescent history, aspect-correct pointer injection, bounded click rings, and a live mid-band complexity pulse. |
| Chrono Dendrite Forge | Replaced reserved extraBuffer FFT reads with three-band plasma shimmer, corrected pointer space, and added exact-load forge persistence plus bounded chrono click rings. |

All ten definitions expose four named params. The nine newly added arrays match the existing `updatedParams` names, defaults, ranges, and steps without changing the indexed slider contract.
