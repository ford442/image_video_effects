# Coordinator review — glass / crystal eleven (2026-11-20)

Reviewed against `BRIEFS.md`. Cards were written before the WGSL. Each numbered idea has a `// ── Idea` comment.

| Shader | Verdict | Why |
|---|---|---|
| luma-refraction | pass | Dispersion divides the existing speed. Cauchy multiplies the existing normal. Wave step, rain, and raw `(h, v)` kept. |
| mouse-time-crystal | pass | Glint, cooling, and veins use the gradient and density the DLA already had. Stick test unchanged. Raw state kept. |
| refractive-bubbles | pass | Snell replaces the rim offset; the ball-lens mix, film, and contact wall stay. Airy sits on the existing specular. |
| alpha-paint-thickness | pass | Wet edge uses the four thickness taps. Directional shadow uses the existing light. Knife ridge, tooth, and raw thickness kept. |
| gen-protocell-division | pass | Scar is the furrow ring after the split. Nucleolus is the core of the existing nucleus distance. Lobes and film kept. |
| kaleido-portal-interactive | pass | Lip and spin smear use the portal radius and the spin the file already integrates. Fold, spring, and border kept. Not the mirror bevel. |
| bismuth-crystallizer | pass | Riser sits inward of the existing lip. Oxide grade is `terraceEdge` added to the existing phase. Hopper loop kept. |
| hybrid-reaction-diffusion-glass | pass | Absorption multiplies the photo before the mix. Meniscus is `\|laplacian\|`. Solver and raw chemistry kept. |
| reactive-glass-grid | pass | Pillow is `localUV` with the pointer bulge still in charge up close. Grout sits under the existing glow. Spring and shockwaves kept. |
| fractal-noise-dissolve-nlm | pass | Edge scale, residual, and ash all come from the NLM the file already computes. Search loop kept. |
| quantum-wormhole | pass | Drag is added to the curl. Redshift edits the existing HSV. The ring resamples the photo. Trail and void invert kept. |

Formula check: deep-water (§12.2D) and Cauchy (§12.2F) only on luma-refraction. Snell and Airy (§12.2F) only on refractive-bubbles. Wet edge (§12.2C) only on alpha-paint-thickness. Beer–Lambert (§12.2F) only on hybrid-reaction-diffusion-glass. No row is on two files.

Saved `params` were not edited. `x-meta.upgrade.params` was added for `mouse-time-crystal` and `fractal-noise-dissolve-nlm`, matching the saved defaults. Kaleido and the glass grid gained `audio-reactive` and `upgraded-rgba` because the shaders do those things.

Naga 11/11. Precommit on these eleven: extraBuffer 0, pasted headers 0. Dead sliders 0 (gen-protocell-division has no top-level `params` array; its four `zoom_params` are still read).

Real-GPU visual QA: external.
