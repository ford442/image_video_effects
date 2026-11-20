# COORDINATOR_REVIEW — sonnet/batch-45 (2026-11-19, Sonnet 5.5)

Base: origin/main 8c537fe6. Ten shaders, five 2-shader forks (COMMON.md). Eight second-pass, two first-pass (`galaxy-sim`, `lenia`). Coordinator migrated `galaxy`, `snow`, `luminance-wind` to `_prelude.wgsl` (header-only, no `Upgraded:` bump from that step).

## Per file (against the Idea Cards in BRIEFS-fork*.md)

| id | formulae (§12.2 row) | rescues | A packing | px >12/255 vs HEAD | cost vs HEAD (SwiftShader) | verdict |
|---|---|---|---|---|---|---|
| conv-steerable-pyramid | line-vs-edge phase classing; second à-trous octave underpainting | `pow(neg,2)`→`q*q`; one shared tap loop (726→484 samples) | ACES display RGBA | 40 % (low-amplitude tint; same effect on side-by-side) | ~0.54× | pass |
| conv-anisotropic-diffusion | Catté–Lions regularised conductivity; edge threshold lifted by pointer/ripples; 9-pt stencil | CA overwrote R/B with raw source (only G diffused); `pow(neg,2)`; no stability bound at max heat+bass; negatives into ACES | ACES display RGBA | 18 % | 1.06× | pass |
| conv-fractal-kernel | circle orbit trap (§12.2E); defocus-scaled aperture | `log2` of negative for interior pts (NaN on real GPU); alpha was Σv/Σw up to 2.0 | display RGBA | — | 1.07× | pass |
| data-moshing | 4:2:0 chroma block bleed (§12.2B); intra-refresh sweep | none | raw (offset.xy, confidence, age) | 0.4 % calm / 42 % loud+held | 0.95× | pass |
| crt-phosphor-decay | beam-current scanline bloom; dynamic convergence error | none | ACES display RGBA | 0.0 % at defaults (sub-pixel on 192² mid/dark scene); 14.9 % with scanline=1 + audio | 0.93–1.10× | pass (see flag) |
| rgb-glitch-trail | per-primary decay order; tail-aligned fringe | none | raw sim (unchanged) | 1.5 % default / 10.4 % stressed | 1.06–1.31× (noisy) | pass |
| galaxy-sim (galaxy.wgsl) | arm dust lanes (Beer–Lambert, §12.2F); arm-born stellar population + HII knots | atan2-cut seam (fractional arm count); star hash re-rolled with `time`; square star cores | raw (density, armDensity, starBright, alpha) | 10.9 % | ~1.2–1.3× (borderline) | pass (see flag) |
| lenia | μ localization (Flow-Lenia zones); kernel-potential aura + growth front | `pow(neg,2)`→`z*z` | raw (field, growth, trail, 1) | n/a (chaotic sim) | ~1.0× | pass |
| snow | depth-occluded flake layers; wind-carried bank | flakes rose (time sign); wind sign inverted vs pointer; accumulation slider dead | A.r bank / A.g coverage (unchanged) | flakes 16.4→6.2 % inside near disc | ~0.87× | pass (see flag) |
| luminance-wind | wake-edge eddies; depth-veered wind | injection ignored trail decay (steady state 1.25–3.9×, washed-out defaults) | raw HDR trail + semantic alpha | 0.6–3.8 % (eddies) / 14–16 % (veer) | ~1.04× | pass (see flag) |

Checklist (§9/§12.7): cards exist for all 5 forks; every idea is pointable via `// ── Idea n` comments (counts 2–5 per file); `Ideas:` + `Upgraded:` lines updated everywhere; JSON `params` byte-equal to origin/main on all 10 (only `description` changed; `depth-aware` added to features on snow and conv-fractal-kernel, both now read depth); no pasted bindings; no springs/ripples/IQ overlays added; no §12.2 row on more than 2 files; no `fwidth`/`dpdx`. The `1.0` alpha in `lenia` and `snow` A stores is HEAD's documented raw-state "initialised" flag, not display alpha.

## Flags for the user (decisions, not defects)

1. **luminance-wind injection rescue changes the default look of every saved preset** (static scene now settles at ~1.25× source instead of ~1.9× ACES). New content also takes ~1/(1−decay) frames to build up. Revert = restore the old `injection` line.
2. **snow wind sign flipped** (positive wind now blows toward +x, matching pointer-right feeding +wind) and flakes now fall instead of rising. One-token revert if the old direction was intentional.
3. **galaxy arm count is now an integer** (default 3.6 → 4; slider steps 2..6) to remove the atan2 seam. Saved `arm_count_p` values map to the nearest integer.
4. **conv-steerable-pyramid**: HEAD's steering mix is a pure quadrupole (band 90° = −band 0°, 135° ≡ 45°, only 2 of 4 bands independent). Fork A built the exact steering but it dropped default saturation ~30 % and changes the kernel, so it was NOT applied.
5. **data-moshing pointer spring is dead at HEAD** (`writeExtraBuffer` re-uploads all 256 floats each frame, so `springVel` is always 0). Not fixable in place without new state.
6. **crt-phosphor-decay** new ideas are invisible at default params on a small mid/dark synthetic scene; they appear with scanline raised / bright content / full resolution.
7. galaxy timing is borderline against the ~1.3× cap; rgb-glitch-trail's range is 1.06–1.31× under load 13–21.

## Gates (coordinator re-ran independently)

precommit 10/10, naga-wasm `--files` 10/10, dead sliders 0 new, extraBuffer 0 violations, `npm run verify:shaders:fix` all 11 gates pass, `upgrades:record` 10 changed (scoped `--ids=`), `generate_shader_lists` run, Vitest 212 files / 1944 tests pass, `npm run build` ok. Real-GPU visual QA: external, not done. Report-timestamp churn under `reports/` and `public/shader-search-index.json` discarded (not part of the batch).
