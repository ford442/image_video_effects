# Coordinator review — cursor/batch-33 (2026-11-01)

Cards were written in `BRIEFS.md` before the WGSL edits. Each numbered idea is marked with a `// ── Idea` comment.

| Shader | Verdict | Why |
|---|---|---|
| holographic-contour | pass | Sobel ridge is added on top of the luma gate. March distance beats a tilted reference; levels is still the frequency. The lattice march is still the picture. |
| holographic-crystal | pass | Bevel is the lit side of the existing groove. Caustic is \|x\| = \|y\| inside the square. Orders and the 0.7 cutoff stay. |
| holographic-failure-iridescence | pass | Holes open on the glitch rows and return the photo, with a rim. The second sample steps along the carrier (28, 14). The wavelength loop stays. |
| holographic-flicker | pass | Speckle cell size follows the hopped wavelength. Red smear is a C tap to the left of the existing red ghost. Slip and the three laser lines stay. |
| holographic-glitch | pass | Nulls sit where the existing scan sine crosses zero. Moiré is interferencePhase against that scan. Peel, orders, and blackout stay. |
| holographic-interferometry | pass | Dark ink is the half-crossing of the same cosine. Visibility uses the path difference that function already computed. Speckle scale is unchanged. |
| holographic-prism | pass | Cauchy replaces the fixed 0.8/1.2 split; Dispersion is still the amount. TIR is the glass-to-air critical angle on the facet edge. Snell stays. |
| holographic-projection | pass | Undiffracted photo shows in dark fringes, more as Glitch rises. Off the cursor's vertical angle the plate gives way to that photo. Speckle, Bragg tint, and the refresh band stay. |
| holographic-projection-failure | pass | One field inside a tear band takes an extra V-Hold shift. Dropout is a scanline streak whose odds follow Static. Cone, stale tears, and the lock line stay. |
| holographic-projection-gpt52 | pass | Bragg colour bands with scene depth. The sample offset steps along the Bragg angle by the existing sinc efficiency. Scan Speed is still the raw 0..5 slider. |
| holographic-shatter | pass | Bevel sign is the flight direction on the existing rim. The crack reveals the ghost this shader already draws. Grid and grating stay. |
| holographic_interference | pass | Contrast falls with mean \|object path − reference path\|. Speckle scales follow Wave Scale. The loop is still three sources. Underscore id unchanged. |

Formula check: Cauchy (§12.2F) on one file. Field interlace and dropout (§12.2B) on one file, and that file's theme is the failing raster. No shared second formula. No new spring. No extraBuffer write was added. Saved `params` arrays are unchanged.

`holographic-contour` and `holographic-prism` left the Naga known-failure list.

Gates: Naga 12/12, precommit 12/12, extraBuffer 0 new, dead sliders 0 new, lists regenerated. Vitest 180 files / 1532 passed (1 skipped). `SKIP_WASM_BUILD=1 npm run build` succeeded. Real-GPU visual QA is external.
