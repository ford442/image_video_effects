# Coordinator review — spectral-field ten (2026-11-15)

Review is against `BRIEFS.md` and the diff. Naga is green on the twelve WGSL files (photon-bins is three passes). Visual QA is external.

| Shader | Verdict | Why |
|---|---|---|
| photon-bins | pass | Beer and Schlick are in the march loop. Travel-axis splat uses `q.z`. Present tints by albedo and does not write A. Mids-on-dispersion is declared audio, not a fifth idea. |
| conv-guided-filter-depth | pass | Gaussian, variance epsilon, and the min/max clamp sit in the existing window. Linear model, luma weight, and photo-edge hold remain. |
| datamosh | pass | P-frame vector comes from the block-centre C load. Quantize is on the predicted colour and is skipped on I-frames. Ghost still uses per-pixel C. Existing spring kept, not copied elsewhere. |
| spectral-mesh | pass | Gauge uses `gradMag`. Face darkening is masked off the wires. A packing unchanged. |
| gen-fractal-lightning-canvas | pass | Stroke, tip, and neighbour scorch are inside the existing bolt and the existing Afterglow. A.r stays raw. C is an exact load. |
| gen-bioluminescent-mycelial-nexus | pass | Hermite uses the weights the noise function already built. Bulb is smin'd with the three tubes. Pulse uses the normal. AO is three taps and does not darken the emit. |
| rainbow-vector-field | pass | Crest, spokes, and held swirl are on the polar field. Depth is still a displacement strength. Prelude migration and the mouse-uniform fix are floor. |
| alpha-depth-fog-volumetric | pass | Tint, mid-slab lobe, and aerial cooling use transmittance, source luma, and Color Temperature. Beer composite and the seven layers stay. |
| cross-spec-alpha-spectral-bloom | pass | Knee, Cauchy PSF, and energy give are in the existing bloom loop. Header packing matches the store. |
| hyb-spectral-fbm-displace | pass | Cauchy scales the existing split. History is upwind. Filament follows `dispVec`. Conveyors and the oil-slick stay. |

Formula rows newly applied:

- Cauchy (§12.2F): bloom, hyb-spectral-fbm-displace. Two files.
- Energy-conserving bloom (§12.2F): bloom only.
- Beer–Lambert and Fresnel–Schlick (§12.2F): photon march only. Fog already had Beer and did not get it again.
- Anti-halo envelope (§12.2A): guided filter only.
- Block DCT quantization and macroblock motion carry (§12.2B): datamosh only.
- Step-count AO (§12.2E): mycelium only, three taps.

No row is new on a third file. No spring, ripple, or IQ palette was added to a file that did not already have it.

Checklist:

- [x] Idea Cards and mechanism notes exist in `BRIEFS.md`, written before the edits
- [x] Each numbered idea is marked in the WGSL
- [x] Kernel, modes, and slider roles kept
- [x] Diff is the ideas plus the floor the thin files were missing, not a shared overlay
- [x] A packing matches how C is read
- [x] Saved `params` unchanged
- [x] Naga, extraBuffer, and dead sliders passed on these files
