# COORDINATOR_REVIEW — sonnet/neural-vortex-ten

Checked against `BRIEFS.md` (cards committed in `b765c43e`, before any idea edit; the 7-file prelude migration is its own commit `ece93c36`). Structural / harness evidence only; no real-GPU visual QA.

| id | Idea (as on the card) | Rescue / floor | Formula row | Verdict |
|---|---|---|---|---|
| neural-nexus | 1 axon fibres + action potentials · 2 spike-rate afterglow | – | – | pass |
| conv-reaction-convolution | 1 9-pt Laplacian of stored chemicals · 2 luma-painted Pearson regime | – | Isotropic 9-pt Laplacian (D) | pass (speckle in smooth skies comes from the synthetic photo's ±0.02 noise; fronts bounded at 500 frames) |
| fluid-grid-rgba-fluid | 1 stirring (added, BRIEFS A1) · 2 vorticity confinement · 3 spun tiles | exact bilinear C (proven equivalent) · semantic alpha | Vorticity confinement (D) | pass — card amended: HEAD's force is curl-free, the first two cards' ideas were invisible without a rotational source |
| gen-chromatic-vortex | 4 depth-sheared twist · 5 comet trails | exact bilinear C helper | – | pass (twist strength cut 0.6 → 0.12 after viewing: depth edges tore the picture) |
| mouse-neural-dreamscape | 1 impulse packets · 2 Hebbian trace | exact C load | – | pass (trace strength cut 0.4 → 0.22 after viewing) |
| spectral-distortion | 1 Cauchy dispersion · 2 per-channel lag | – | Cauchy (F) | pass, quietest of the batch — judge it in motion |
| scan-slice | 1 slit-scan stretch · 2 per-channel aperture | – | – | pass (aperture gated by `bestLive` after a first-draft leak) |
| chroma-vortex | 1 third counter-rotating vortex · 2 rotation-phase hue | mix weight clamped | – | pass |
| neural-resonance | 1 streamline persistence · 2 eddy-core glow | exact bilinear C | – | pass |
| phosphor-magnifier | 3 beam-spot growth · 4 held magnet | – | – | pass with re-picked ideas (BRIEFS A2): the carded convergence error acts only on R/B, which HEAD's grille multiplies by 0 |

## Checklist (§9 + §12.7)
- [x] Idea Cards written before the diff; mechanism interrogation (T1/T2/T3/T4/T5/T6/T7 per file) is in `BRIEFS.md`; the three post-implementation amendments are appended with their evidence, the originals left intact
- [x] Each numbered idea pointable: `grep -n "Idea [0-9]"` finds every number on every card (fluid-grid 1–3, gen-chromatic-vortex 4–5, phosphor-magnifier 3–4 continue the file's own numbering)
- [x] KEEP VERBATIM holds: modes, kernels and param roles untouched; saved `params` byte-exact (only `x-meta.upgrade.params` added to 4 definitions)
- [x] Diff composition (added/removed vs the cards commit): nexus 49/2, conv 32/5, fluid 77/10, gen-vortex 39/6, dreamscape 40/7, spectral 29/3, scan-slice 31/3, chroma-vortex 25/10, resonance 35/4, phosphor 19/4 — all idea / helper code; no header, ACES, spring or ripple boilerplate was added
- [x] No generic overlay: no spring, ripple stamp or IQ palette was added to any file. No two files share an idea
- [x] A packing matches how C is read (A = C round-trip checked in the harness; mouse-neural-dreamscape and neural-nexus now read back the same channels they write)
- [x] Springs/ripples only if native: none added
- [x] Each formula consumes a quantity the file already had; no new binding / solver / param; row de-dup: 3 distinct §12.2 rows, none repeated
- [x] No `fwidth`/`dpdx`; no `pow` introduced (the two Gaussian packets first used `pow(signed, 2.0)`, indeterminate for a negative base on real GPUs — caught on review, now an explicit square, numerics identical); no `time × audio` introduced; every divide is guarded
- [x] Naga 10/10 · precommit gate 10/10 · extraBuffer audit PASS · dead sliders 0 new · 120-render harness sweep 0 NaN / 0 Inf
- [x] Reserved identifiers: `target` was caught and renamed (`axonEnd`) before the first gate run

## Not done, on purpose
ACES on the photo resamplers (fluid-grid, spectral-distortion, scan-slice) and on the additive neural composites — a tone curve there changes the picture, not the effect. See `NOTES.md` open items 1–6 for the pre-existing defects found along the way (dead springs ×4, phosphor grille, inert fluid pressure, conv packing, chroma-vortex slider range, tag drift).
