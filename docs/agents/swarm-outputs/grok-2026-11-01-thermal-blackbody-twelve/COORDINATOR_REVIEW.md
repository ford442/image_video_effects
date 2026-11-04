# Coordinator review — thermal / blackbody twelve

Cards were written in `BRIEFS.md` before the WGSL edits. Each numbered idea has a `// ── Idea` comment in that file's main path.

| Shader | Verdict | Why |
|---|---|---|
| thermal-vision | pass | Isotherms and the 5-tap unsharp are on the existing heat. Ramp, split-tone, and blur role kept. No pointer. |
| thermal-vision-blackbody | pass | Narcissus is display-only; lag still stores pre-narcissus T. Glow mix now follows well saturation. NUC and lag kept. |
| thermal-touch-blackbody | pass | Dwell reads same-pixel C.a under the iron. Scorch is before Original Blend. Halo and ember streak kept. |
| spec-blackbody-thermal | pass | Edge cooling uses `tempGrad`. Glow spend is §12.2F and only here. Wien fringe and ember persistence kept. |
| sim-heat-haze-blackbody | pass | Binomial weights on the existing 3×3. Heat is carried off the ground. Schlieren and shear kept. Not the §12.2D Laplacian. |
| heat-haze-gpt52 | pass | Glitter uses the existing pools. Veil is Beer–Lambert and only here. Inferior mirage and the 22% C blend kept. |
| honey-melt-blackbody | pass | Neck uses stored speed. Crust uses stored temperature and thickness. Hex solver and packing kept. |
| melting-oil-blackbody | pass | Marangoni uses the stored temperature neighbors. Meniscus uses molten vs neighbor molten. Downhill flow kept. |
| warp-drive-blackbody | pass | Pocket is inside the existing wall. Wake reads C.a, which A already wrote. Bow/wake split kept. No Cauchy. |
| energy-shield-blackbody | pass | Conduction samples the trail one cell away. Cooling tail is blackbody; fresh strikes stay cyan. Hex SDF kept. |
| gamma-ray-burst | pass | Cooling and jet break use the cycle and Jet Spread already in the jet. The non-compiling IQ clock-ring is gone. Spring kept. |
| gamma-ray-burst-blackbody | pass | Shell is the burst's own ring. Afterglow tint uses the RGB C already stored. Lobes kept. No spring. |

Formula cap: §12.2A once, energy-conserving bloom once, Beer–Lambert once. No row on three files. No shared narcissus, isotherm, or well-bloom.

Checklist: cards exist; ideas are commented; params byte-exact; springs only where gamma-ray-burst already had one; A packing matches the C read; Naga 12/12; precommit 12/12; extraBuffer 0 new; dead sliders 0 new. gamma-ray-burst left the known-failure list (ratchet 21). Vitest 180 files / 1532 passed (1 skipped). `SKIP_WASM_BUILD=1 npm run build` succeeded.
