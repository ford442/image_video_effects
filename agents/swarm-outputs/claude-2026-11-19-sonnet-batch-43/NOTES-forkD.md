# NOTES — fork D (gen-lichen-reaction-diffusion, gen-magnetic-storm) — both second pass

## gen-lichen-reaction-diffusion
IDENTITY: noise-driven RD lichen regimes over rock with zone lines, cups, soredia. KEEP VERBATIM: Ideas 1–5, evalLichen kernels, A packing (display RGB + density). Upgraded `2026-10-10, 2026-11-19`.
- **Rescue 1 (HEAD):** regime selector used hard `step()` on (kill−feed), which varies with uv → two straight diagonal seams cut the frame. Now smoothstep cross-fades (weights still sum to 1). Seams gone at 384.
- **Rescue 2 (HEAD):** alpha = density × |Δdensity| × depth → meanA 0.000 (invisible under alpha compositing). Now thallus coverage (0.3 bare rock → 1.0 dense, + growth activity). meanA 0.94.
- **Idea 6 lobate margin** — pale thickened rim just inside each Idea-3 zone line (same iso, gradient-scaled width).
- **Idea 7 areolate crust cracks** — dark Voronoi crack network on dense crust only (density > 0.5, not over apothecia); 2×2-cell Voronoi inside `if (crust > 0.001)` for cost.
- JSON features + `lobate-margin`, `areolate-cracks`. `params: []` at HEAD left as-is (sliders unexposed — open item; adding defaults could change the look).
- perf.sh 384, 4 rounds (load 35): 1.26 / 0.70 / 0.91 / 1.15 → median ≈1.03. First 3×3 Voronoi version was 1.28/1.74 → trimmed.

## gen-magnetic-storm
IDENTITY: curl-noise field-line bands round a mouse pole + corona/aurora. KEEP VERBATIM: Ideas 1–4, params. Upgraded `2026-10-10, 2026-11-19`. No HEAD defect found (one faint horizontal line at p.y≈0 exists at HEAD too, untouched).
- **Idea 5 reconnection X-point flares** — warm glow where |B| collapses (the pinched X knots), twin-jet weighting along B, flicker, Storm Power + bass.
- **Idea 6 radiation-belt drift band** — mirror-bounce double shell between plasmapause and auroral oval, beaded azimuthal drift; mids widen, treble brightens. Subtle at defaults.
- Visibility @384 vs HEAD: 70.2 % px > 0.02, meanΔ 0.066 (mostly flares + belt). nan 0, meanL 0.276→0.342.
- JSON features + `reconnection-flares`, `radiation-belt`.
- perf.sh 384 (load 35, very noisy): 0.50 / 0.75 / 0.96 / 2.14 → median ≈0.86 (wildly noisy; re-time alone). Additions are loop-free.

## Gates (both)
naga-wasm 2/2 valid; wgsl_precommit_gate 2/2 pass; audit:dead-sliders PASS (rewrote reports/dead_sliders_audit.*, reports/wgsl_precommit_report.json — coordinator decide). Not done: click-ripple render, real-GPU look.
