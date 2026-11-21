# Coordinator review — optical / geometry ten (2026-11-21)

Reviewed against `BRIEFS.md`. Naga 10/10. Precommit on these ten: extraBuffer 0, pasted headers 0, workgroup 0. Dead sliders 0 on the ten (Klein gained a top-level `params` block copied from its existing `x-meta`, so the audit can see the four sliders).

| Shader | Card before edit | Ideas pointable | Keep holds | Not a boilerplate diff | Formula row | A packing matches C | Params exact | Springs only if native | Gate |
|---|---|---|---|---|---|---|---|---|---|
| pp-chromatic | yes | Petzval + coma | yes | yes | none new (Cauchy already present) | display RGBA | yes | existing click lens kept | pass |
| crt-clear-zone | yes | interlace + H-sync | yes | yes | field interlace (§12.2B) only here | display RGBA, C is phosphor | yes | existing degauss click kept | pass |
| pixel-storm | yes | blocks + eye-wall jet | yes | yes | none | display RGBA | yes | existing storm spring kept | pass |
| gen-temporal-motion-smear | yes | shutter tent + upstream trail | yes | yes | none | display RGBA, exact C | x-meta copied to top-level, values unchanged | no spring added | pass |
| infinite-fractal-feedback-hdr | yes | preimage feedback + bloom | yes | yes | energy-conserving bloom (§12.2F) only here | linear in A, ACES on display, C read as linear | yes | existing focal spring kept | pass |
| gen-hyperbolic-tessellation | yes | metric darkening + ideal horocycles | yes | yes | none | raw HDR in A | yes | no spring | pass |
| gen-klein-bottle-walk | yes | sheet hue + Gaussian K | yes | yes | none | display RGBA | x-meta copied to top-level, defaults still 0.5 | no spring | pass |
| solarize-warp | yes | per-channel Sabattier + Mackie re-exposure | yes | yes | none | display RGBA | yes | existing spring kept | pass |
| spec-importance-sampled-bokeh | yes | cat's eye + Airy | yes | yes | Airy disc (§12.2F) only here | linear in A, C unread | yes | existing focus spring kept | pass |
| gravity-lens | yes | magnification + Doppler limb | yes | yes | none | raw fields, no C reader | yes, names not retitled | no spring | pass |

No §12.2 row is on more than one file. Each new formula consumes a quantity the file already had. No `fwidth` / `dpdx`. ACES inputs are clamped. Real-GPU visual QA is external.
