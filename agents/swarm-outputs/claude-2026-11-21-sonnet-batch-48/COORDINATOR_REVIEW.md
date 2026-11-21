# COORDINATOR_REVIEW — sonnet/batch-48 (11 shaders, 6 forks A–F)

Reviewed against `docs/SHADER_UPGRADE_BATCH.md` §9 checklist + §12.7 additions. Cloud VM = SwiftShader, **no real-GPU visual QA** and **no real-GPU timing**; every pixel/timing number below is synthetic-source SwiftShader.

## Coordinator-run checks (independent of the fork reports)

- **Saved `params` byte-exact vs `origin/main`:** 11/11 (`json.dumps` equality). Changed keys: `description` on all 11; additive `x-meta.upgrade.params` on `tone-histogram-apply` only (mirrors the saved params).
- **naga-wasm** (`verify-naga-wasm.mjs --files`, the stricter gate): 11 valid, 0 invalid, 0 known, 0 new.
- **Prelude:** all 11 `#include "_prelude.wgsl"`; coordinator migrated 5 header-only first (vortex-distortion, cyber-focus, tone-histogram, pixel-focus, tone-histogram-apply), no `Upgraded:` bump for that.
- **Headers:** every file carries `Upgraded: <old>, 2026-11-21` (or first-pass `2026-11-21`), an `Ideas:` line naming each new idea with its §12.2 row, and an `A packing:` line.
- **§12.4 de-dup:** no §12.2 row sits on more than one file. Nearest neighbours (distinct rows, kept): block-DCT quantization (cyber-focus) vs macroblock motion carry (data-moshing-diffusion).
- **Timing, re-measured by the coordinator** (quiet box, load ≈2, interleaved HEAD/new ×7, median of per-round ratios, 512²): vortex-distortion 1.21×, cyber-focus 1.15×, rgb-topology 1.27×, pixel-focus 0.99×, data-moshing-diffusion 1.09×, **conv-guided-video-filter 1.42× (min 1.31×)**. Fork A's generic `pkill` may have disturbed other forks' in-flight perf rounds, which is why these were re-run.

## Per-file verdict

| id | pass | ideas findable in WGSL | rows (§12.2) | KEEP VERBATIM | A packing | verdict |
|---|---|---|---|---|---|---|
| tone-histogram | 2nd | density-weighted grain; Wallis local-brightness pull | A, A | metering window, per-channel shoulder, 4 params | ACES display RGBA (unchanged) | PASS. 3 HEAD rescues (half-texel uv, inverted Haze Removal, hard 1→2.5× gain switch) change the default look. |
| tone-histogram-apply | 1st | clip-limited CDF equalisation blend; percentile-anchored levels | A (CLAHE clip), A | 4 params + roles, HEAD reduction (mean, p05/p95, peak bin), peak-bin hue shift, A stats field | raw stats field, never ACES (unchanged) | PASS with flags. Orphan-Pass-2 rescue: in-pass workgroup-atomic histogram over a 32×32 whole-frame grid. Two deliberate deviations from verbatim: contrast span measured *after* the tone curve and pivoted on the tone-mapped mean; contrast gain capped ×3; alpha now `src.a` (was 1.0). Cost ≈3.6× a degenerate HEAD. |
| cyber-focus | 1st | block-DCT quantization; luma-weighted defocus | B, — | aperture, glitch offset, CA, box blur | display RGBA pass-through (unchanged) | PASS. Half-texel rescue changes the in-focus pool from a half-pixel blur to the exact source pixel. HEAD's `fast-motion` feature tag left in place. |
| pixel-focus | creative 1st | Cauchy dispersion; CFA zipper | F, A | mosaic, click pulses, depth-aware focus, 4 params | display RGBA pass-through (unchanged) | PASS. Mosaic now samples cell centres (HEAD sampled cell corners). |
| scanline-cyberpunk | 1st | sync-edge line hook; dropout bursts | B, B | fp128 offset sum, head-roll bar, phosphor runner, triad masks | display RGBA (unchanged) | PASS. Texel-centre rescue changes ~54 % of synthetic pixels by >1/255. |
| spectrum-bleed | 2nd | chroma delay line; paper-fibre wicking | B, C | all three existing Ideas | ACES display RGBA (unchanged) | PASS. |
| data-moshing-diffusion | 2nd | macroblock motion carry; 9-point isotropic stencil | B, D | tangent diffusion, packet wake | raw sim (unchanged) | PASS. Quantize ≥0.947 near-black rescue. 9-pt stencil is quiet (≤0.8 % px) by design. |
| vortex-distortion | 2nd | vorticity confinement; MacCormack backtrace correction | D, D | streamline smear, source-tied vorticity | raw field (unchanged) | PASS. Rescue: saturating vortex age (core no longer grows with app clock). C is now genuinely read, so the `temporal` tag is true. |
| hyb-kaleidoscope-pulse | 1st | mirror-bounce fold-count material; object-cell twist | E, E | kaleido wedge, radial pulse, remix | none (A/B unwritten) | PASS with flag: integer wedge count (9.5→10) changes the default. |
| rgb-topology | creative 1st | hillshade; dashed half-interval contours; elevation parallax | — (native) | contour field, R/G/B line masks | raw masks (unchanged) | PASS. 3 ideas; at the cost cap (1.27×). |
| conv-guided-video-filter | 2nd | edge-aware ε weighting (weighted guided filter); guide-gated anti-halo envelope | A, A | depth-augmented guide, exact integer C loads, display RGBA | writeTexture = ACES display; A = pre-ACES guided state + α (changed, see flags) | PASS with flags. **Over the cost cap.** |

## Open calls for the user (none are blockers; all are default-look or cost decisions)

1. **conv-guided-video-filter cost.** Coordinator re-time: 1.26–1.28× at r=4, **1.37–1.47× at the default r=3** (fork F reported 1.16–1.25×; not reproduced on a quiet box). The overhead is a ~constant +65 ms at 512², so the ratio is worst at small radii. It is intrinsic to the two per-tap accumulator sets; fork F measured and rejected cheaper variants (if-gated 3×3 1.69×, `textureLoad` guide taps slower, luma-only envelope weakens Idea 2). SwiftShader is ALU-bound and this kernel is texture-bound on a real GPU, so re-time there. If it must come down, drop Idea 2's per-channel envelope to luma-only.
2. **conv-guided-video-filter A packing changed (R3).** HEAD stored ACES'd colour in A and re-read it as P, so a self-fed run collapsed to flat grey. A now holds pre-ACES guided colour + α; `writeTexture` keeps HEAD's exact display formula. A later chain slot reading C therefore sees different data than at HEAD. Confirm.
3. **tone-histogram-apply deviates from KEEP VERBATIM** in two spots (post-curve contrast span + mean pivot; ×3 gain cap) — both belong to rescuing a degenerate HEAD (×3.5 exposure, ×63 contrast). Slider roles and ranges are intact. Cost ≈3.6× HEAD (HEAD did almost nothing).
4. **hyb-kaleidoscope-pulse default changes** (wedges 9.5→10; mean luma −12 %). Twist amplitude (0.35·mix) and hairline depth (0.20) are taste values. No aspect correction on non-square canvases (pre-existing, left).
5. **vortex-distortion JSON default `circulation` = 0.5 ⇒ Γ = 0.** At JSON defaults it is the image plus a chroma fringe; `shaderDefaults.ts` ships 0.45. Mapping left alone (saved presets).
6. **spectrum-bleed spring is dead (library-wide).** `src/renderer/webgpu/audioDepth.ts` `writeExtraBuffer` re-zeroes `extraBuffer[133..255]` every frame, so spring state never persists (`springPos` = raw mouse, `springVel` = 0). `docs/agents/WGSL_BUILTINS_GENERATIVE.md` still calls that range safe for persistent state. Not fixed here; other pointer-spring shaders likely share it.
7. **cyber-focus.json still carries `fast-motion`** from HEAD (§8 says not unless a brief opted in). `cyber-focus` and `pixel-focus` keep `upgraded-rgba` without ACES (matches the `pp-sharpen` precedent: the in-focus pool must return the source pixel).
8. Default-look changes from half-texel / texel-centre rescues (cyber-focus, pixel-focus, scanline-cyberpunk, tone-histogram) are real on photos with fine detail; the percentages above are mostly synthetic-source.

## Not verified (external)

Real-GPU visual QA and timing for all 11; real-photo content (all renders are synthetic sources); 4K behaviour of the 8-px macroblocks (cyber-focus); fast pointer jump with one-frame-stale C (vortex-distortion); 20 live ripples (vortex-distortion); non-multiple-of-16 frame sizes (harness limit).
