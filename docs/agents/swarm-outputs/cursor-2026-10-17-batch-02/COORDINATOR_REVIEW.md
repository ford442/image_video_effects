# Coordinator review — cursor batch-02

Cards were in `BRIEFS.md` before the edits. Each numbered idea is named in the WGSL.

| Shader | Verdict | Notes |
|---|---|---|
| quantum-foam-pass2 | pass | Comet and scintillation are in the particle color / emission. Curl, dispersion, spectral mix kept. |
| quantum-foam-pass3 | pass | Glow smear and Beer veil are in the composite. Does not write A. |
| liquid-pass1 | pass | Crest lean and capillary fringe sit on the existing wave step. Height packing unchanged. |
| liquid-pass2 | pass | Caustics and wetting rim are shading on the existing refraction. No A write. |
| vortex-pass1 | pass | Pairing jet and viscous memory extend the four-core field. `velMag+2` sentinel documented. |
| vortex-pass2 | pass | Sim warp, Rankine eye, eyewall braids. Photo-as-flow fallback kept. No A write. |
| chromatographic-fluid | pass | Migration is in advect; solvent front is in render. Dye + temperature packing kept. |
| sim-fluid-feedback-field | pass | Self-advection and dye are in the only dispatched pass. Pass 2/3 left unwired. |
| gen-spectral-ferrofluid | pass | Beads and domain wall added on top of the five existing ideas. A packing unchanged. |
| gen-aethereal-ferrofluid-chrono-core | pass | Tip bulbs and equatorial sheet added. Clock ring and seam glow kept. |

Saved params: values unchanged. Springs were not added. Real-GPU visual QA is external.
