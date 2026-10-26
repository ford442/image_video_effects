# Coordinator review — Grok (`grok/liquid-ten`, 2026-10-26)

Cards were written in `BRIEFS.md` before the WGSL edits. Each new idea is marked with `// ── Idea`.

| Shader | Verdict | Why |
|---|---|---|
| quantum-foam | pass | Neck uses `cell.y - cell.x`. Memory uses C luma and the existing diffusion blend, and only at cell centers. A stays linear because that blend reads C as color. |
| vortex | pass | Billows sit on the Lamb-Oseen peak already computed per vortex. Caustic uses `dimple.yz` and stays off the throat. Vortex count and profile unchanged. |
| liquid-optimized | pass | Bead and crawl both consume `hCenter` and `hg.yz`. Surface Tension and Turbidity still own wave amplitude and absorption. |
| hybrid-particle-fluid | pass | The wake uses the curl step the advect loop already took. Milk scales with `particleIntensity / particleCount`. Palette and packing unchanged. |
| ink-bleed | pass | Wet edge is the neighbor difference the fibre stencil already loads, written back into ink. Granulation is the existing paper hash on the thin wash. Stored ink is ungranulated. |
| ambient-liquid | pass | 9-point weights sum to 1 and are scaled by 4 so the Gray-Scott rate matches the old cross. Stain is display-only on spent U. |
| magnetic-interference | pass | Crackle is gated by the existing `switching` window. Filings are three taps along `totalDisp`, mixed only inside `influence`. |
| lava-lamp-blobs | pass | Rolls scroll with Rise Speed inside `blobShape`. Cap uses `fy`, which the meniscus gradient already computed. Packing unchanged. |
| tornado-vortex | pass | Eye clears fog inside the existing core radius. Bulb scales that radius and stalls `vVertical`. Rankine formula unchanged. |
| gen-reaction-diffusion | pass | The gate multiplies only the FHN stimulus sum. Curvature uses `lap.x` and the gradient magnitude already computed for feed. Stored state is still unclamped. |

## Formula rows

| Row | Files |
|---|---|
| Wet-edge accumulation (§12.2C) | ink-bleed |
| Paper granulation (§12.2C) | ink-bleed |
| Isotropic 9-point Laplacian (§12.2D) | ambient-liquid |

No row is on more than one file. No new solver, binding, or spring. `vortex` did not receive the 9-point row. `gen-reaction-diffusion` already had a 9-point stencil and was not given a second one.

## Checklist

- [x] Idea card before the diff, with mechanism notes
- [x] Each idea is pointable in the WGSL
- [x] Modes, kernels, and param roles kept
- [x] Diff is the ideas plus the prelude swap
- [x] No shared spring / ripple / IQ stamp
- [x] A packing matches how C is read
- [x] Saved `params` unchanged
- [x] Springs only where the file already had one (ink nib, lava pointer, magnetic envelope)
- [x] Naga 10/10, extraBuffer clean, dead sliders clean
- [x] Vitest 169 files / 1435 passed, 1 skipped; `SKIP_WASM_BUILD=1 npm run build` succeeded
