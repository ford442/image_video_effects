# Coordinator review — chromatic ten (2026-11-01)

Self-review by the batch author against the cards in `BRIEFS.md` and the §9 + §12.7 checklists. There was no
separate coordinator; treat this as a checklist a human reviewer should re-run, not as independent sign-off.
All verdicts are **structural** (no GPU here). "PASS" never means "looks right".

## Per file

| File | Cards written first | Each idea pointable | KEEP VERBATIM holds | A packing matches C read | Saved params exact | Springs/ripples only if native | Verdict |
|---|---|---|---|---|---|---|---|
| chromatic-folds | yes | `Idea 1`, `Idea 2` comments | yes | yes (pre-ACES RGB, C colour) | yes | none added | PASS |
| chromatic-folds-2 | yes | `Idea 1`, `Idea 2` comments | yes | yes | yes | none added (click front is HEAD) | PASS (+ slider repair) |
| chromatic-folds-bilateral | yes | `2026-11 Idea 1–3` | yes | yes (HEAD ACES-in-A kept) | yes | none added | PASS |
| chromatic-manifold | yes | `Idea 1`, `Idea 2` | yes (signed debt kept in A) | yes (raw signed A, ACES on display only) | yes | none | PASS — shadow look changed, GPU review needed |
| chromatic-manifold-2 | yes | `Idea 1`, `Idea 2` | yes | yes (A.a curvature memory untouched) | yes | none | PASS (+ slider repair) |
| chromatic-crawler | yes | `2026-11 Idea 1`, `2026-11 Idea 2` | yes | yes | yes | none added (cursor term is HEAD) | PASS |
| chromatic-crawler-structure | yes | `2026-11 Idea 1–3` | yes | yes | yes | none added (ripples are HEAD) | PASS |
| chromatic-focus | yes | `2026-11 Idea 1`, `2026-11 Idea 2` | yes | yes (mask, no reader) | yes | none | PASS |
| chromatic-focus-guided | yes | `Idea 1`, `Idea 2` | yes (spring untouched) | yes | yes | spring/ripples are HEAD, not extended | PASS |
| chromatic-focus-coupled | yes | `Idea 1`, `Idea 2` | yes (raw A kept) | yes (fields) | yes | spring/ripples are HEAD, not extended | PASS — solver stability needs GPU review |

## §9 checklist

- [x] Idea Card exists and was written before the diff (`BRIEFS.md` first; the prelude migration of four files came after it, and is infrastructure).
- [x] Each numbered idea is pointable in the WGSL (labelled comments; see NOTES per-shader list).
- [x] KEEP VERBATIM still holds (modes, kernel family, param roles).
- [x] Diff is not ≥ 70 % header / ACES / spring boilerplate: 336 insertions / 160 deletions across the ten WGSL files; the four prelude-migration files lose their ~20 pasted binding/struct lines each, the rest is idea code.
- [x] No generic overlay shared between files: no spring, ripple, IQ palette, holographic scan or oil-slick added anywhere. No two files share an idea.
- [x] A packing matches how C is read (raw fields stay raw in `chromatic-focus-coupled`; signed debt stays raw in `chromatic-manifold`).
- [x] Saved `params` unchanged (parsed `params` identical to HEAD for all ten; `x-meta` unchanged).
- [x] Springs/ripples only if native: none added.
- [x] naga-wasm + SwiftShader pipeline + extraBuffer + dead sliders on every file.

## §12.7 additions

- [x] `BRIEFS.md` has mechanism-interrogation answers per file.
- [x] Formula rows named in `NOTES.md` and the `Ideas:` lines.
- [x] Row use across the batch (limit 2 files per row):

| §12.2 row | files | count |
|---|---|---|
| E fold-count-as-material | folds-2 | 1 |
| D semi-Lagrangian advection | manifold-2 | 1 |
| A structure tensor / edge-directed taps | crawler-structure | 1 |
| A guided-filter base/detail | focus-guided | 1 |
| D vorticity confinement | focus-coupled | 1 |
| none (tactic-derived) | folds, folds-bilateral, manifold, crawler, focus | — |

- [x] Each formula consumes a quantity the file already had (fold strengths, depth taps, tensor eigenvalues, guided base, C velocity/density) — no new solver, state, binding or spring. `extraBuffer` is untouched in all ten.
- [x] No `fwidth`/`dpdx`; no `pow` with an unguarded base (the one `pow(x, 2.0)` I wrote was replaced by an explicit square); no negative input into ACES from new code. `chromatic-manifold` previously fed negative colour to ACES — fixed there.

## Things the reviewer should look at first on a GPU

1. `chromatic-folds-2`, `chromatic-manifold-2`: the sliders now drive their named roles again after the order repair; compare against the pre-migration look, not against HEAD (HEAD's sliders were mis-wired). `depthInfluence` / `noiseAmount` changed from engine time to a constant.
2. `chromatic-manifold`: the shadow area (negative debt) now displays through the complement ghost instead of tone-mapped negatives; contour lines were added before the persistence mix.
3. `chromatic-focus-coupled`: stability of vorticity confinement at low viscosity and under sustained stirring.
4. `chromatic-crawler-structure`: per-channel LIC (+12 taps) and the epoch change are visible differences in motion; check cost at 4K.
5. `chromatic-folds-bilateral`: with the bilateral base now live, flat regions are blended toward the smoothed image (up to 0.6).

## Not done / left open

- Mouse-position and time reads that act as hidden parameters in `chromatic-folds` (mouse x/y), `chromatic-manifold` (mouse y persistence), `chromatic-folds-bilateral` (time/mouse x/mouse y) — flagged, not changed (see NOTES finding 3).
- Resurrecting the cursor-pinch / bass-breathing / nested-band behaviour that `chromatic-folds`' old JSON description promised.
- Thumbnails for the ten ids are stale after this change (the ledger record marks them); regenerate on a GPU machine.
