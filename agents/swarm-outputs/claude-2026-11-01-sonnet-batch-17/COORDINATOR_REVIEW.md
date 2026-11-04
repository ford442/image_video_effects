# Coordinator review — sonnet batch 17 (2026-11-01)

Self-review by the batch author against `BRIEFS.md` and the §9 + §12.7 checklists; no separate coordinator existed, so a human should re-run
the checklist. Verdicts are **structural** plus SwiftShader numeric experiments. PASS never means "looks right".

## Per file

| File | Cards first | Ideas pointable | KEEP VERBATIM holds | A packing matches C read | Saved params exact | Verdict |
|---|---|---|---|---|---|---|
| astral-kaleidoscope | yes | `2026-11 Idea 1`, `2` | yes | yes (pre-ACES feedback, exact load) | yes | PASS |
| astral-kaleidoscope-gemini | yes | `Idea 1`, `2` | yes | yes | yes | PASS |
| astral-kaleidoscope-grokcf1 | yes | `Idea 1`, `2` | yes | yes | yes | PASS |
| astral-kaleidoscope-julia | yes | `Idea 1`, `2` | yes | yes (raw A, no reader) | yes | PASS (+ unbounded zoom repaired) |
| astral-kaleidoscope-morph | yes | `Idea 1`, `2` | yes (slider roles = saved names) | yes | yes | PASS — hand migration; look differs from HEAD because HEAD's sliders were mis-wired |
| kaleidoscope | yes | `2026-11 Idea 1`, `2` | yes | yes | yes | PASS (+ even segment count, FFT bins) |
| prismatic-mosaic | yes | `Idea 4`, `5` | yes | yes | yes | PASS |
| prism-displacement | yes | `Idea 4`, `5` | yes | yes | yes | PASS |
| liquid-prism | yes | `2026-11 Idea 1`, `2` | yes | yes | yes | PASS (+ FFT bin) |
| spec-prismatic-dispersion | yes | `Idea 1`, `2` | yes | yes | yes | PASS (cast mostly removed, measured) |

## §9 checklist

- [x] Idea Card written before the diff (`BRIEFS.md`; the prelude migration came after and is infrastructure).
- [x] Each numbered idea is pointable in the WGSL (labelled comments).
- [x] KEEP VERBATIM still holds. Exceptions stated: `astral-kaleidoscope-morph` (slider wiring), `kaleidoscope` (even segment count: 4.8 → 4 at default), `spec-prismatic-dispersion` (the red cast is removed).
- [x] Diff is not ≥ 70 % boilerplate: net idea code per file; the migration removes ~20 pasted binding/struct lines in nine files.
- [x] No generic overlay shared between files; no spring, ripple shockwave, IQ palette, holographic scan or oil-slick added. (The click-front/clock-ring overlay in `astral-kaleidoscope` is HEAD's.)
- [x] A packing matches how C is read; no packing changed.
- [x] Saved `params` and `x-meta` unchanged in all ten JSONs.
- [x] Springs/ripples only if native: none added.
- [x] naga-wasm, Tint pipeline creation, extraBuffer and dead-slider audits on every file.

## §12.7 additions

- [x] BRIEFS has mechanism-interrogation answers per file.
- [x] Formula rows named in NOTES and headers; no row on more than two files (Cauchy weighting on exactly two).
- [x] Each idea consumes a quantity the file already had (wedge index, `r_pulse`, `n`, `cosV`, the displacement field, `segIndex`, the superellipse terms, the tile id, band weights); no new solver, state, binding or spring. `extraBuffer` writes untouched (reads of FFT bins added in two files).
- [x] No `fwidth`/`dpdx`; `pow` bases positive (`pow(rho, bounces)`, `pow(1-cos, 5)`); `smoothstep` edges ascending; ACES inputs clamped non-negative where added.

## Look at first on a GPU

1. `astral-kaleidoscope-morph`: the whole look. HEAD's segments grew with time and its sliders drove other things, so there is no valid "before" to compare against; compare against the siblings.
2. `kaleidoscope`: default is now 4 segments (was 4.8 with a seam); slider moves in steps of 2.
3. `astral-kaleidoscope-gemini`: eyepiece falloff (f = 1.1) and the 35 % outside-stop floor — strength was chosen by arithmetic, not by eye.
4. `prism-displacement`: Beer–Lambert centre tint (aqua, ~26 % red loss at the centre at default) — constants are a guess.
5. `liquid-prism`: caustic brightness gain and the TIR weight (critical cos ≈ 0.79) at several Prism Strength / Wave Frequency settings.
6. `astral-kaleidoscope-julia`: zoom is now fixed at 2.75 (HEAD's grew without bound).

## Not done / left open

- The feedback veil in gemini/grokcf1 (history mean ≈ 0.99) is HEAD's look and was not changed.
- Thumbnails for the ten ids are stale after this change.
