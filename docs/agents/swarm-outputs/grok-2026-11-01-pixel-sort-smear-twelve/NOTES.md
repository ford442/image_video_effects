# Notes — pixel-sort / smear twelve (2026-11-01)

Second pass on files that already named ideas. New ideas are additive. Saved `params` byte-exact. No new spring.

| Shader | Kept verbatim | A packing | Ideas in the diff |
|---|---|---|---|
| glitch-pixel-sort | Threshold, Sort Mode (H / V / noisy diagonal), Glitch Amount, fp128 displacement, hash jump, C melt, streak packet, RGB split, held melt, click rings | ACES display RGBA. C is last frame's colour for the melt | chroma delay line (§12.2B); dropout tail (§12.2B) |
| pixel-sorter | Direction, Reverse, Intensity Scale, Threshold, Asendorf close, span seam, wavelength tint, prev-mouse in extraBuffer[133..134] and [138] | ACES display RGBA | head-to-tail ramp; sort-axis comb |
| pixel-sort-radial | Stretch, Luma Thresh, Radius, Direction, radial Asendorf, ring seam, chromatic sample, twist, runners, click fronts | ACES display RGBA (C unread) | spoke gutter; inward stack |
| pixel-sort-explorer | Threshold, Spot Radius, Direction, Smoothness, bidirectional walk, luma-hold from C.a, streak persist, scan band, surround dim | ACES display RGBA. C.a hold, C.rgb persist | interval ticks; tail dust |
| spectral-glitch-sort | Sort Length, Threshold, Direction, Digital Noise, spring [133..138], four-step walk, chroma sort, exact-C trail, FFT voice | ACES display RGBA | block-shared step (§12.2B); directional tear |
| spectral-flow-sorting | Flow Sensitivity, Sort Threshold, Frequency Influence, Temporal Smoothing, exact-C Lucas-Kanade, Asendorf along flow, cursor flow | raw previous RGB in A. ACES on writeTexture only | aperture gate; flow barb |
| hybrid-spectral-sorting | Sort Sensitivity, Spectral Bands, Displacement, Hue Shift, Y walk, band displacement, palette, hue shift, bass glitch | ACES display RGBA (C unread) | band gutter; band head |
| pixel-drag-smear | Brush Radius, Drag Strength, Decay, Mode, three exact-C taps, treble bleed, lumaMix, comb, click fronts | ACES display RGBA | bristle splay; drying (§12.2C) |
| pixel-stretch-interactive | Stretch, Bloom, Grain, Chromatic Scale, tensor, coherence tear length, luma-sorted taps, parallax, grain | ACES display RGBA (C unread) | Cauchy channel scale (§12.2F); coherence gutter. Chromatic Scale still sets the old ±0.5 reach |
| luma-smear-interactive | Decay, Luma Threshold, Color Shift, Eraser, (0,0) state texel, downhill slide, R-lag / B-lead, wet-edge ridge | linear pre-ACES trail RGB + energy in A.a. (0,0) is the pointer state. ACES on writeTexture only | uphill stick; fringe spends the trail |
| spectral-smear | Trail Decay, Brush Radius, Color Speed, Intensity, spring [133..138], flow advection, exact C, palette, click bloom | ACES display RGBA | speed-thinned brush (§12.2C); stroke-sheared hue |
| quantum-smear | Intensity / Speed / Scale / Detail stay scatter, entropy, coherence, density. Stochastic advection, foam, void subtract, click mix-back | clamped pre-ACES smear RGB in A (motion). ACES on writeTexture only | still-lock; void rim |

Formula use: chroma delay and dropout only on glitch-pixel-sort. Macroblock step only on spectral-glitch-sort. Drying only on pixel-drag-smear. Speed-thinning only on spectral-smear. Cauchy only on pixel-stretch-interactive. No new wet-edge (luma-smear already has the ridge). No new spring.

Floor: `#include "_prelude.wgsl"` on all twelve (six pasted headers migrated, no `Upgraded:` bump for that swap). 16×16. Exact C where C is read. `x-meta.upgrade.params` added for glitch-pixel-sort, spectral-flow-sorting, hybrid-spectral-sorting, and pixel-stretch-interactive. Saved params unchanged.

Gates: Naga 12/12, precommit 12/12, extraBuffer 0 new, dead sliders 0 new on a full catalog re-scan, lists regenerated. Vitest 180 files / 1532 passed (1 skipped). `SKIP_WASM_BUILD=1 npm run build` succeeded. Real-GPU visual QA is external.
