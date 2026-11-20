# Coordinator review — mirror / portal ten (2026-11-19)

Reviewed against `BRIEFS.md`. Cards were written before the WGSL. Each numbered idea is named in a `// ── Idea` comment.

| Shader | Verdict | Why |
|---|---|---|
| quad-mirror | pass | Bevel, seam split, and quadrant registration sit on the existing abs() fold. Offsets, warp, ribbons, and the trail are intact. |
| reality-tear | pass | Curl, fibers, and void parallax use the rim, the angle, and the void sample. Radius, burn, static mix, spring, and rifts are intact. |
| stereoscopic-3d | pass | Crosstalk, vergence, and defocus use the two eyes and sceneDepth. A is still the raw state tuple. |
| fractal-noise-dissolve | pass | Cracks are ridges of the existing FBM. Embers sit in the burned hole. Heat shimmer, scorch, and pinholes are intact. |
| mirror-dimension | pass | Bevel, caustic, and fold fringe use the folded angle and r. Segment count, spin, spring, and seam glow are intact. |
| neon-pulse-dissolve | pass | Striations use the Sobel gradient the magnitude threw away. Afterglow reads the display history the shader already wrote. |
| mouse-mandelbrot-zoom-portal | pass | Orbit trap (§12.2E) is a min inside z = z² + c. Windows are gated by Portal Blend. Palette and portals are intact. |
| split-dimension | pass | Jump and hinge use the existing normal and distance. The lip replaces the gray band on the same cut. |
| quantum-tunnel-interactive | pass | Ridges reuse the log-z sine. The streak is a shorter radius on the same ray. The pupil sits under the existing glow. |
| cyber-physical-portal | pass | Photon ring and Doppler use the horizon and the spin angle. A is still the throat smear. |

Formulae this batch: orbit trap (§12.2E) on `mouse-mandelbrot-zoom-portal` only. No other §12.2 row. No row is shared.

Checklist:

- [x] Idea Card exists and was written before the diff
- [x] Each numbered idea is pointable in the WGSL
- [x] KEEP VERBATIM still holds (modes, kernel family, param roles)
- [x] Diff is not header / ACES / spring boilerplate
- [x] No generic overlay shared with the previous file
- [x] A packing matches how C is read
- [x] Saved `params` unchanged
- [x] Springs and ripples only where the file already had them
- [x] Naga 10/10, extraBuffer 0, dead sliders 0, pasted headers 0
- [x] Mechanism interrogation is in `BRIEFS.md`
- [x] The one §12.2 formula is named in `NOTES.md` and the `Ideas:` line
- [x] No new solver, binding, or spring
- [x] No `fwidth` / `dpdx`. New `pow` bases are in 0..1. ACES inputs are clamped, or the call is `aces()` which clamps

Gates: Naga 10/10. Precommit on these ten passed. Dead sliders 0. Vitest 1944 passed, 1 skipped. `npm run build` succeeded. `verify:shaders:fix` still fails on three shaders this branch already had pasted against `origin/main` (`emergent-calligraphic-weave`, `physarum-gemini`, `physarum-grokcf1`). `--fix` also dropped five already-migrated ids from the prelude pending list.

Real-GPU visual QA: external. The cloud VM has no hardware GPU.
