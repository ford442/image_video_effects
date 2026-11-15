# Coordinator review — glass-flora ten (2026-11-15)

Structural review against the Idea Cards. Not visual QA. Naga is recorded after the pollen `arm` rename (10/10).

| Shader | Card | Ideas pointable | Kept | Packing | Formula overlap | Verdict |
|---|---|---|---|---|---|---|
| hybrid-voronoi-glass | yes | bevel at facet tilt; caustic after history | F1/F2, Cauchy, Snell, Schlick, TIR, fracture | ACES display RGBA | none new | pass |
| gen-harmonic-ferrofluid-kinetics | yes | pinch in `map`; crest in shade; `aoTap` ×3 | Voronoi spikes, held mound, spec, SSS, fog | ACES display RGBA, C unread | §12.2E AO, this file only | pass |
| bio-touch | yes | nucleus/wall from `v`; `C.a` decay | disk, pulse, curl, clicks, tints | display RGB, raw glow in A.a | none | pass |
| gen-liquid-metal-chrono-flora | yes | Schlick on chrome; six-fold vein | torus/sphere smin, time wave, crevice energy | ACES display RGBA, C unread | §12.2F Fresnel, file 1 of 2 | pass |
| mouse-kaleidoscope-tunnel | yes | cos⁴ after fog; C streak toward pointer | log-z, wavelength split, layers | ACES display RGBA | §12.2A cos⁴, this file only | pass |
| gen-aetherial-chromatic-tesseract | yes | `folded.w`; `thinFilm`; `boxEdge` | four folds, box SDF, march glow | ACES display RGBA, C unread | fold-count, thin-film, box edge, this file only | pass |
| quantum-prism | yes | `cauchyRatio` on the wheel; `fres` from hex distance | hex, grout, bands, runners, clicks | display RGBA, C is display | §12.2F Cauchy (only); Fresnel, file 2 of 2 | pass |
| gen-psychedelic-time-warp-kaleidoscope | yes | opposite sine; `seam` hairline | fold, curl, bass mirrors, fold smear | ACES display RGBA | none | pass |
| rain-lens-wipe | yes | `lens` in the drop; head/tail packet | mask in A.r, meniscus, beads | raw mask in A.r | none | pass |
| gen-audio-reactive-quantum-pollen | yes | `restDir` golden angle; `lobes` | gather, envelopes, spiral, orbit | raw envelopes, ACES on display only | §12.2E golden-angle, this file only | pass |

Checklist:

- [x] Idea Cards written before the WGSL edits (`BRIEFS.md`)
- [x] Mechanism interrogation is in each card
- [x] Each numbered idea is named in the WGSL
- [x] KEEP VERBATIM holds: modes, kernels, param roles
- [x] Diffs are the ideas plus the floor (ACES, alpha, depth, A), not a spring/ripple stamp
- [x] No shared overlay. The two Fresnel uses are chrome on the flower and a hex rim on the prism
- [x] A packing matches how C is read. Bio stores glow in A.a and reads C.a. Rain still stores the wipe in A.r. Pollen still stores envelopes
- [x] Saved `params` unchanged
- [x] No new springs or click systems. Existing click fronts were left where the file already had them
- [x] No §12.2 row on more than two files
- [x] No `fwidth` / `dpdx`. Signed `pow` in the rain streak was removed
- [x] Naga 10/10

Notes that are not failures:

- Tesseract gravity was restored into the ray's uv. The old pointer was divided by the resolution and the well did not move the picture. Direction of the warp is the old one.
- Quantum prism and bio-touch were tagged `upgraded-rgba` without ACES. ACES landed as floor.
- Ferrofluid crest uses height and an upward normal together, so the flat sheet does not take the glint.
- Real-GPU visual QA is external.
