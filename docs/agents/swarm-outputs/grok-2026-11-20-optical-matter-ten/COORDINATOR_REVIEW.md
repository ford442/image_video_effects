# Coordinator review — optical / matter ten (2026-11-20)

Cards were written before the WGSL. Each numbered idea is marked in the shader with a `// ── Idea n:` comment. Saved params were not renamed or re-defaulted.

| Shader | Verdict | Why |
|---|---|---|
| mouse-polarized-light-field | pass | Malus term that was already computed now darkens the field. Luma scales the existing retardation. Analyzer, moiré, fringes, vortices kept. |
| spec-iridescence-engine | pass | Finesse blends the existing cosine. Transmission uses the existing Fresnel cover. Spectral loop and spring kept. |
| gen-turing-morphogenesis | pass | Gradient already used for grain tightens the threshold. Stain walks the existing ramp via C luma. Regimes kept. |
| aero-chromatics-prismatic | pass | Curl gated to the wake. `speedMag` thins the trail. Cauchy loop and Schlieren kept. |
| mercury-temporal-mirror | pass | Meniscus is an addend on the existing accel. Tarnish uses `surfaceH`. K1/K2 and raw `(h, v)` kept. |
| frosty-window | pass | Needle uses the dendrite angle. Rime sits on the branch tips. Nucleation, meltwater, and the Sparkle→melt mapping kept. |
| encaustic-wax | pass | Soak and furrow use the heat channel A already wrote. Strata, bloom, and held scrape kept. |
| glass-wipes-coupled | pass | Confinement uses stored `C.z`. Beading uses neighbor density. Semi-Lagrangian step kept. |
| photonic-caustics | pass | Inverse-square uses Light Size and `lightDist`. Fold uses `detJ`. Irradiance packing kept. |
| virtual-lens | pass | Zone softness uses the Aberration slider on the existing disc. cos⁴ multiplies the existing darkening. Single UV kept. |

Formulae, one file each: vorticity confinement (§12.2D) `glass-wipes-coupled`; soft inverse-square (§12.2F) `photonic-caustics`; cos⁴ (§12.2A) `virtual-lens`. No other §12.2 row is new. No formula is on two files.

- [x] Idea Card exists and was written before the diff
- [x] Each numbered idea is pointable in the WGSL
- [x] KEEP VERBATIM still holds
- [x] Diff is not header / ACES / spring boilerplate. Prelude migration is separate and is not the upgrade
- [x] No generic overlay shared across the batch
- [x] A packing matches how C is read
- [x] Saved `params` unchanged. `"upgraded-rgba"` added only on `spec-iridescence-engine` and `glass-wipes-coupled`, which already tone-map and now have the cards
- [x] No new spring. The iridescence spring that was already there stayed
- [x] Naga 10/10, extraBuffer 0, pasted headers 0, dead sliders 0
- [x] `npm run build` succeeded
- [ ] `verify:shaders:fix` is red on pasted headers already on this branch versus `origin/main` (`cosmic-flow`, `distortion-gravitational-prismatic`, `distortion_gravitational_lens`, `ethereal-swirl-coupled`, `gen-raptor-mini-flow`, `gravitational-lensing-nlm`, `kinetic-dispersion`, `optical-flow-tracer`). Not these ten. `--fix` also dropped three already-migrated ids from pending: `luminance-wind`, `mirror-dimension`, `mouse-mandelbrot-zoom-portal`.

Real-GPU visual QA: external. This VM has no hardware GPU.
