# Coordinator review — wave / audio twelve (2026-11-01)

Cards were written in `BRIEFS.md` before the WGSL edits. Each numbered idea has a `// ── Idea` comment. Saved `params` arrays were not renamed or re-defaulted.

| Shader | Verdict | Formula | Notes |
|---|---|---|---|
| sine-wave | pass | §12.2D deep-water dispersion | Group shade uses the existing packets. Nodes and Stokes kept. Telemetry A kept. |
| spectral-waves | pass | none from the shared rows | Slope split and contrast gain. Spring and caustic palette kept. |
| digital-waves | pass | none | Posterize and pixel shear. Nodes and crest scanlines kept. Diagnostic A kept. |
| sonic-distortion | pass | none | Harmonic product and rose nulls. Exact C load. Pre-ACES A. |
| audio-reactive-rgb-dispersion | pass | §12.2F Cauchy | No ACES, by design. Blend anchor is the undisplaced sample. |
| audio-reactive-pyramid | pass | §12.2A anti-halo | Anisotropic gate uses the blur pair the kernel already computed. No ACES. |
| audio-voronoi-displacement | pass | none | Site bulge and ridge. Fake audio removed. A now written. |
| moire-interference | pass | beat envelope (this file only) | Carriers, spring, and click emitters kept. |
| waveform-glitch | pass | §12.2B chroma delay | Symmetric VHS split kept. Afterglow uses the existing Lissajous. |
| signal-modulation | pass | none | AM and zero-crossing ticks. FFT source corrected. Naga `depth` redefinition fixed. |
| vertical-slice-wave | pass | none | Strip lag and stored velocity. Raw state A kept. |
| wave-halftone | pass | none | Dot gain and local density. Ellipse and 15° rosette kept. |

No §12.2 row is on more than one file. No new spring was added. Springs that were already in spectral-waves, digital-waves, moire-interference, and signal-modulation stayed.

`signal-modulation` was removed from `src/contracts/wgsl_validation.json` knownFailures and the ratchet went from 23 to 22.

Real-GPU visual QA: not done.
