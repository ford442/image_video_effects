# Coordinator review — sonnet batch 15 (2026-11-01)

Self-review by the batch author against `BRIEFS.md` and the §9 + §12.7 checklists; no separate coordinator existed, so a human should
re-run the checklist. Verdicts are **structural** plus SwiftShader numeric experiments. PASS never means "looks right".

## Per file

| File | Cards first | Ideas pointable | KEEP VERBATIM holds | A packing matches C read | Saved params exact | Verdict |
|---|---|---|---|---|---|---|
| gen-julia-set | yes | `2026-11 Idea 1`, `2` | yes | yes (unchanged) | yes | PASS (lace width calibrated) |
| gen-mandelbox-explorer | yes | `Idea 1`, `2` | yes | yes | yes | PASS |
| gen_mandelbulb_3d | yes | `Idea 1`, `2` | yes (Reinhard-style curve kept) | yes | yes | PASS — was non-compiling at HEAD; thresholds calibrated on measured data |
| spec-quaternion-julia | yes | `Idea 1`, `2` | yes | yes | yes | PASS (+ bounds guard) |
| hyperbolic-dreamweaver-julia | yes | `Idea 1`, `2` | yes | yes | yes | PASS |
| gen-audio-spirograph-julia | yes | `Idea 1`, `2` | yes | yes | yes | PASS |
| gen-grok41-mandelbrot | yes | `Idea 1`, `2` | yes | yes (linear accumulation unchanged) | yes | PASS (+ dead sliders/click repaired, verified) |
| kimi-fractal-dreams | yes | `Idea 1`, `2` | yes | yes | yes | PASS (+ FFT-bin repair) |
| multi-fractal-compositor | yes | `2026-11 Idea 1`, `2` | yes (identity = zoom tunnel) | n/a (no A) | yes | PASS — description rewritten; not a fractal renderer |
| gen-3d-sierpinski-chaos | yes | `Idea 1`, `2` | yes | yes | yes | PASS |

## §9 checklist

- [x] Idea Card written before the diff (`BRIEFS.md`; the prelude migration of eight files came after and is infrastructure).
- [x] Each numbered idea is pointable in the WGSL (labelled comments).
- [x] KEEP VERBATIM still holds. Exceptions stated: `gen_mandelbulb_3d` (three compile-level fixes), `multi-fractal-compositor` / ghost composite (a dead intermediate promoted).
- [x] Diff is not ≥ 70 % boilerplate: net idea code per file; migration removes ~20 pasted binding/struct lines in eight files.
- [x] No generic overlay shared between files; no spring, ripple shockwave, IQ palette, holographic scan or oil-slick added.
- [x] A packing matches how C is read; no packing changed.
- [x] Saved `params` unchanged (parsed `params` and `x-meta` identical to HEAD in all ten JSONs).
- [x] Springs/ripples only if native: none added; `gen_grok41_mandelbrot`'s existing click pull and spring were *repaired*, not extended.
- [x] naga-wasm, Tint pipeline creation, extraBuffer and dead-slider audits on every file.

## §12.7 additions

- [x] BRIEFS has mechanism-interrogation answers per file.
- [x] Formula rows named in NOTES and `Ideas:` headers; no row on more than two files (E step-AO and E curvature both sit on gen_mandelbulb_3d only).
- [x] Each idea consumes a quantity the file already had (orbit |z|, `n`, DE field, `lastVi`, `projZ`, `baseColor`, neighbour taps); no new solver, state, binding or spring. `extraBuffer` writes untouched (reads of FFT bins added in two files).
- [x] No `fwidth`/`dpdx`; guarded `log` arguments (`max(…, 1e-6)`, `max(…, 1e-4)`); every `pow` base non-negative; `refract` handles TIR (zero vector → undisplaced tap); `acesToneMap` inputs clamped non-negative in `multi-fractal-compositor`.
- [x] Thresholds that depend on field statistics (bulb curvature/AO, Julia lace) were measured, not guessed — see NOTES deviations 1–2.

## Look at first on a GPU

1. `gen_mandelbulb_3d`: it rendered nothing at HEAD; check the whole look, then AO and ridge/crevice wear (constants fitted from a 64 px SwiftShader measurement).
2. `gen_grok41_mandelbrot`: Center X/Y now move the view (verified numerically), clicks pull toward the click point for 1.4 s, Nebulabrot colours and ray checker.
3. `multi-fractal-compositor`: up to 55 % layer composite over the image, staggered octave zoom; it is a different picture from HEAD's (which showed only the photo with fog/edge glow).
4. `gen-julia-set`: lace density at the default animated c, and the interior bands across the Exponent slider range.
5. `spec-quaternion-julia`: slice drift range (±0.18) keeps the set present; shadow cost on top of 64-step marching.
6. `kimi_fractal_dreams`: near-white default colour balance (also at HEAD).

## Not done / left open

- A real fractal-compositor (Mandelbrot/Julia/Newton blend) would be a new shader; `multi-fractal-compositor` keeps its zoom-tunnel identity.
- Cost of `gen_grok41_mandelbrot`, `gen_mandelbulb_3d` and `spec-quaternion-julia` at high resolution.
- Thumbnails for the ten ids are stale after this change.
