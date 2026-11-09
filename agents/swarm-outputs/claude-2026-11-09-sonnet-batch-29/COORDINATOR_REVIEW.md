# COORDINATOR_REVIEW — sonnet/batch-29

Checked against `BRIEFS.md` (cards committed in `7c39b38b`, before any idea edit; the 7-file prelude migration is its own commit `1774aa7d`). Structural only; no real-GPU visual QA.

| id | Idea (as on the card) | Idea | Rescue | Formula row | Verdict |
|---|---|---|---|---|---|
| static-reveal | 3 head-switching noise | 4 tape dropout bursts | – | Dropout bursts (B) | pass |
| selective-color | 3 chroma-plane hue+sat window | 4 mono-stock grain (removed field only) | – | Density-weighted grain (A) | pass (window tightened after viewing: red key admitted the orange horizon) |
| aero-chromatics | 1 edge-tangent flow | 2 spiral outflow (40 %) | R1 glide in A(0,0) + exact bilinear; R2 audio index / bands | none | pass (rescue-only build = HEAD to 4 digits; swirl trimmed 55→40 % after an orbit test) |
| chroma-depth-tunnel-prismatic | 1 ring-joint dispersive rim | 2 chromatic flight lag · 3 depth-integrated Beer–Lambert | R1 glide; R-phase (time × audio) | Beer–Lambert (F) | pass (rims need real resolution or a sparse tunnel to read) |
| fractal-kaleidoscope | 4 seam-weighted dispersion | 5 per-bounce defocus | – | none | pass, with a caveat: invisible on smooth content, clear on high-frequency content |
| gen-apollonian-gasket | 7 conformal hairlines | 8 generation-delayed pulse | R1 glide | none | pass (hairline width / fade tuned after viewing: first pass turned the centre white) |
| luminescent-glass-tiles | 4 Cauchy lens dispersion | 5 hammered decentring | – | Cauchy (F) | pass, same caveat as the kaleidoscope |
| divine-light-iridescence | 1 sun corona (Airy) | 2 Henyey–Greenstein lobe · 3 stratified march | – | Airy (F), HG (F) | pass (stratified march visibly removes HEAD's stepped ghost copies) |
| gen-belousov-zhabotinsky | 5 isotropic 9-point Laplacian | 6 Schlieren front relief | – | Isotropic 9-pt Laplacian (D) | pass (raw A view: HEAD's staircase fronts are smooth) |
| interactive-kuwahara | 4 structure-tensor sector alignment | 5 stroke-edge pigment pooling | – | Structure tensor (A) | pass (pooling gated by sector spread after viewing: noise specks produced dark squares) |

## Checklist (§9 + §12.7)
- [x] Idea Cards written before the diff; mechanism interrogation answers are in `BRIEFS.md` (T1/T2/T3/T5/T6/T7 per file)
- [x] Each numbered idea pointable: `grep -n "Idea [0-9]"` finds every number on every card (numbering continues each file's own; gasket 7–8, BZ 5–6)
- [x] KEEP VERBATIM holds: modes, kernels and param roles are untouched; aero keeps HEAD's sample-position convention on purpose
- [x] Diff composition (added/removed vs the migration commit): static-reveal 32/3, selective-color 33/4, aero-chromatics 96/67, tunnel 50/39, kaleidoscope 29/4, gasket 50/16, glass-tiles 41/2, divine-light 68/6, BZ 23/4, kuwahara 71/4. None of it is header / ACES / spring / ripple boilerplate. aero-chromatics and the tunnel carry the largest *rescue* share (glide state, exact bilinear, audio-index and `time × audio` fixes) — reported as rescues, not counted as ideas.
- [x] No generic overlay: no spring, ripple or IQ-palette stamp was added to any file. The only springs touched are the three that were dead (`extraBuffer[133..138]` never persisted: the host re-uploads the buffer every frame — `audioDepth.ts::writeExtraBuffer`), replaced by a first-order glide in A(0,0) (the `cyber-magnifier` scheme).
- [x] A packing matches how C is read; saved `params` byte-exact (only `divine-light-iridescence.json` `features` gained `upgraded-rgba`: ACES and the ideas are real)
- [x] Each formula consumes a quantity the file already had; no new binding / solver / param
- [x] No `fwidth` / `dpdx`; every `pow` base is clamped or in [0,1]; every ACES input is clamped non-negative
- [x] Naga 10/10, precommit gate 10/10, extraBuffer audit PASS, dead sliders 0 new
- [x] Row de-dup: 8 distinct §12.2 rows, none repeated within the batch

## Open items for real-GPU QA
Apollonian centre is ~5 % brighter and busier than HEAD; aero spiral strength and the new audio response (HEAD's audio was dead); kuwahara pooling on real noisy photos (the gate is tuned on a synthetic image); kaleidoscope defocus and glass-tile dispersion on real photos; tunnel ring rims at real resolution; BZ Schlieren gain. Thumbnails for all ten are marked stale in the ledger.

## Flag for whoever owns the contract
`SHADER_UPGRADE_BATCH.md` §12.3 F1 `airy()` is wrong beyond x ≈ 3 (returns −56.5 at x = 8; true J1(8) = 0.2346): it uses a truncated Maclaurin series. `divine-light-iridescence.wgsl` carries a verified replacement (`besselJ1` + `airy`, f32 error ≤ 9e-7 on 0.01…1000) that can be lifted into the doc.

## MEMORY / USER closeout (§9 shape — not written to `docs/agents/USER.md`, a shared file concurrent batches conflict on)
```
## 2026-11-09 — sonnet/batch-29 glass / iridescence / kaleidoscope optical ten (10 shaders)

- IDs: static-reveal, selective-color, aero-chromatics, chroma-depth-tunnel-prismatic, fractal-kaleidoscope, gen-apollonian-gasket, luminescent-glass-tiles, divine-light-iridescence, gen-belousov-zhabotinsky, interactive-kuwahara.
- Per shader, the ideas actually added:
  - static-reveal: head-switching noise; tape dropout bursts. Mask-in-alpha packing and the roll/ghost kept.
  - selective-color: chroma-plane hue + saturation window; mono-stock grain in the removed-colour field. Six mask generators kept.
  - aero-chromatics: edge-tangent flow; spiral outflow. Chromatic advection and HEAD's sampling convention kept.
  - chroma-depth-tunnel-prismatic: ring-joint dispersive rim; chromatic flight lag; depth-integrated Beer–Lambert. Four-band Cauchy sum kept.
  - fractal-kaleidoscope: seam-weighted dispersion; per-bounce defocus. Folds, crossfade, reflection loss kept.
  - gen-apollonian-gasket: conformal hairlines; generation-delayed pulse. Seed circles and inversion loop kept.
  - luminescent-glass-tiles: Cauchy lens dispersion; hammered decentring. Fresnel / luminescence / Beer–Lambert kept.
  - divine-light-iridescence: Airy sun corona; Henyey–Greenstein lobe; stratified march. Thin-film and 14-step march kept.
  - gen-belousov-zhabotinsky: isotropic 9-point Laplacian; Schlieren front relief. Kinetics and A/B packing kept.
  - interactive-kuwahara: structure-tensor sector alignment; stroke-edge pigment pooling. Sector weights, impasto, weave kept.
- Rescues (not ideas): three dead extraBuffer springs → A(0,0) glide (aero, tunnel, gasket); aero audio read from plasmaBuffer[1..] → [0].xyz; tunnel `time × audio` phase jumps → audio into amplitude.
- Floor: prelude include on all ten (seven migrated, own commit); 16×16; exact C loads; A packing as documented; saved params exact.
- Gates: Naga 10/10, precommit 10/10, extraBuffer 0 new, dead sliders 0 new, catalogs regenerated, Vitest 203 files / 1822 passed (1 skipped), `npm run build` ok.
- Real-GPU visual QA: external.
```
