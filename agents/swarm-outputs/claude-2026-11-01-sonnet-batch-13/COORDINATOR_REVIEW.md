# Coordinator review — sonnet batch 13 (2026-11-01)

Self-review by the batch author against `BRIEFS.md` and the §9 + §12.7 checklists; no separate coordinator existed, so a
human reviewer should re-run the checklist. Verdicts are **structural** (naga, audits, a SwiftShader numeric harness). PASS never means "looks right".

## Per file

| File | Cards first | Ideas pointable | KEEP VERBATIM holds | A packing matches C read | Saved params exact | Verdict |
|---|---|---|---|---|---|---|
| fractal-boids-field | yes | `Idea 1`, `Idea 2` | yes | yes (A = boid layer, read as C) | yes | PASS (+ time-as-audio repair, leaves naga known-failures) |
| fractal-boids-field-coupled | yes | `Idea 1`, `Idea 2` | yes | yes (unchanged, A(0,0) mouse) | yes | PASS — idea 2 formula differs from card (see NOTES dev. 2) |
| kimi-flock-symphony-em | yes | `Idea 1`, `Idea 2` | yes (Reinhard kept) | yes (unchanged) | yes | PASS |
| particle-swarm | yes | `2026-11 Idea 1`, `2026-11 Idea 2` | yes | yes (raw A, B diag unchanged) | yes | PASS (+ FFT-band repair, not on card) |
| particle_dreams_alpha | yes | `2026-11 Idea 1–3` | yes | n/a (no A) | yes | PASS — 3 ideas (card had 2), saved param names do not match roles (flagged) |
| gen-trails | yes | `Idea 1–3` | yes | **changed on purpose** (fixes packing lie, stated on card) | yes | PASS — picture changes (flock now moves smoothly) |
| gen-magnetic-field-warp | yes | `2026-11 Idea 1`, `2026-11 Idea 2` | yes | yes (unchanged) | yes | PASS |
| magnetic-field | yes | `2026-11 Idea 1`, `2026-11 Idea 2` | yes (≥ threshold = HEAD) | yes | yes | PASS (+ FFT-band repair) |
| alpha-em-field-simulation | yes | `2026-11 Idea 1`, `2026-11 Idea 2` | yes | yes (raw unchanged) | yes | PASS — idea 2 replaced after the harness showed it inert (NOTES dev. 1); E now non-zero, big visual change |
| gravity-well-em | yes | `2026-11 Idea 1`, `2026-11 Idea 2` | yes | yes | yes | PASS |

## §9 checklist

- [x] Idea Card exists and was written before the diff (`BRIEFS.md`; the prelude migration came after it and is infrastructure).
- [x] Each numbered idea is pointable in the WGSL (labelled comments).
- [x] KEEP VERBATIM still holds. Exceptions are stated: `gen_trails` (A packing, boid motion), `particle_dreams_alpha` (dead layered colour now reaches the output).
- [x] Diff is not ≥ 70 % header / ACES / spring / ripple boilerplate: each file's net change is mostly idea code; the migration removes ~20 pasted binding/struct lines per file.
- [x] No generic overlay shared between files; no spring, ripple shockwave, IQ palette, holographic scan or oil-slick added. (`fractal-boids-field-coupled` idea 1 reacts to the ripples that file already had.)
- [x] A packing matches how C is read. `gen_trails` corrected; raw sim state stays raw in `particle-swarm` and `alpha-em`.
- [x] Saved `params` unchanged — parsed `params` identical to HEAD in all ten JSONs.
- [x] Springs/ripples only if native: none added.
- [x] naga + extraBuffer + dead sliders on each file; execution sanity on SwiftShader.

## §12.7 additions

- [x] BRIEFS has mechanism interrogation per file.
- [x] Formula rows named in NOTES and `Ideas:` headers; no row on more than one file (history in C: two files, different content).
- [x] Each idea consumes a quantity the file already had (neighbour velocity C.zw, `baseColor`, `emissivity`, pole positions, `crowd` from the neighbour loop, …); no new solver, state, binding or spring. `extraBuffer` writes untouched in all ten (reads of FFT bins added in two).
- [x] No `fwidth`/`dpdx`; every `pow` base is positive (`pow(beamD, 2.5)`, redshift `pow(1/(1+z), …)`); ACES inputs are clamped non-negative.

## Look at first on a GPU

1. `alpha-em-field-simulation`: E is now visible around every charge (HEAD showed none); check the saturation of the E-hue rings and the corona flash.
2. `gen_trails`: flock now drifts continuously and pheromone trails composite under the boids; HEAD's re-rolled sparkle is gone. The distance cull is exact only inside the stated bounds.
3. `particle-swarm` / `magnetic-field`: the FFT bands now actually move things (were constant zero at HEAD).
4. `particle_dreams_alpha`: ghost layers up to 40 % over the image; ACES now applied (HEAD had none).
5. `fractal-boids-field` ×2: trail memory in A; flow strength rides audio instead of time.
6. `kimi-flock-symphony-em`: per-pixel 2048-loop cost with stretched reach.

## Not done / left open

- `particle_dreams_alpha` saved param names vs real roles (needs a reviewed rename/re-map).
- Cost of `gen_trails` and `kimi-flock-symphony-em` at high resolution.
- Thumbnails for the ten ids are stale after this change.
