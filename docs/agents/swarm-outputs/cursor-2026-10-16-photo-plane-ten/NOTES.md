# Photo-plane ten — notes

Date: 2026-10-16. Model: Grok 4.7. Cards in `BRIEFS.md` were written before the WGSL edits.

`tone-histogram-apply` was considered and skipped. It still reads `extraBuffer[1..258]` as a histogram, and `tone-histogram.wgsl` no longer writes that buffer.

## Per shader

- **bismuth-crystallizer** — Kept the hopper loop, offset cycle, thin-film iridescence, Fresnel, and the four sliders. Added terrace rims (`hitTerrace` / `terraceEdge`) and tarnish in the stair center. ACES and `dataTextureA` are new; this shader does not read C. A packing: ACES display RGBA.
- **molten-glass** — Kept heat in `A.r`, upward advection from `C.r`, cooling, held injection, click fronts, Fresnel, Beer-Lambert, four sliders. Added a cooling crust where heat fell, and drew the existing convection packet as a drip highlight. ACES is on `writeTexture` only. A packing: raw heat.
- **circular-pixelate** — Kept hex cells, dome refraction, chromatic aperture, glint, clicks, and density / radius / hardness / bg mix. Added a hex diaphragm on the round stop and a grout seam between cells. A packing: ACES display RGBA.
- **spectral-mesh** — Kept gradient-adaptive density, ortho plus triangle wires, spectral mix, four sliders. Added junction beads and a grating fringe along the wire normal. A still stores `(line, triLine, pull, alpha)`. C is not read as color.
- **cross-conv-mouse-bilateral** — Kept the 7×7 bilateral, spatial Gaussian, luma range weight, brush falloff, three sliders. Added range coring and a wet-edge ring. A packing: ACES display RGBA.
- **selective-color** — Kept voronoi, fbm, polar sectors, hex/star SDF, ripple masks, and radius / softness / desat / feather. Added a hue window around the pointer sample and a dark contour on the existing mask boundary. No `plasmaBuffer` (not tagged audio-reactive). A packing: ACES display RGBA.
- **plasma** — Kept eight orbs, orbit radius and speed, metaball field, velocity trails, shadow offset, four sliders. Added arc filaments and a luma corona. The cluster now orbits the pointer; the JSON already said mouse-driven and the pointer had been unused. Audio is `plasmaBuffer[0]`, not `u.config.y`. A packing: ACES display RGBA.
- **poincare-tile** — Kept the disk clip, Möbius translate toward the pointer, sector fold, and curvature / symmetry / speed / tile scale. Added geodesic ink and q-fold cusps at the rim. Outside the disk now writes A as well. No audio tag. A packing: ACES display RGBA.
- **quantum-fractal** — Kept the z² step, c1/c2, and the four slider roles (including `zoom_params.w` as the existing time scale). Added phase fringes and a photo sample pulled by the second phase. Audio is `plasmaBuffer[0]`, not `u.zoom_config.x`. The pointer offsets the fractal center. A packing: ACES display RGBA.
- **liquid-chrome-ripple** — Kept multi-sine height, Fresnel metal, RGB dispersion, caustics, thin film, C afterimage, and flow / distort / metal / freq. Added crest beads and a trough meniscus. A stays HDR display history; ACES is on `writeTexture` only.

## Floor

Bindings via `#include "_prelude.wgsl"` (five pasted headers migrated, then ideas added). 16×16. Exact `textureLoad` on C where C is history or heat. Saved `params` unchanged. `x-meta.upgrade.params` added only where it was missing.

## Gates

Naga 10/10 (`verify-naga-wasm.mjs`). Precommit gate 10/10. extraBuffer audit pass (no new writes to `[0..132]`). Dead sliders 0. `node scripts/generate_shader_lists.js` and `check_duplicates.js` pass. Jest: 159 suites, 1332 passed, 1 skipped. `SKIP_WASM_BUILD=1 npm run build` compiled.

Real-GPU visual QA: external. This VM has no hardware GPU.
