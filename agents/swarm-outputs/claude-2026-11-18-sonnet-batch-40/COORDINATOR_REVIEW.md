# COORDINATOR_REVIEW — sonnet/batch-40 (second-pass generative ten)

Branch `sonnet/batch-40` from origin/main `0761b6b9`. Five forks (A–E), two files each; cards in `BRIEFS-fork<X>.md` (written before WGSL by each fork), measurements in `NOTES-fork<X>.md`. **No unanchored reviewer pass was run on this batch** and nothing was looked at on a real GPU, so the PR is a draft. The coordinator checks below are structural.

## Structural checks (coordinator, whole batch)
- Saved `params` byte-identical to HEAD in all 8 edited definitions; metropolis and pulsar JSON untouched. Definition diffs are `description` (+42…+68 chars) and, for 4 files, extra `features` tags only.
- Header `Upgraded:` appended (not replaced) and `Ideas:` appended (not replaced) in all 10; every new idea/rescue has a `// ── Idea n` / `// ── Rescue n` marker (counts 2–5 per file).
- All 10 include `_prelude.wgsl` (hyperbolic, newton, kimi were migrated by their forks; infra, no `Upgraded:` bump for the migration itself).
- Gates: `verify:shaders:fix` 11/11, `verify:toolchain-foundation` 13/13, `test:ci` 212 files / 1944 tests pass, `npm run build` ok, `upgrades:record` scoped with `--ids` (10 entries). `verify:shaders:fix` also dropped 11 *unrelated* already-migrated ids from `prelude_migration.json` `pending` (the gate requires it; they are not this batch's files).
- Row budget: no §12.2 row on more than one file (SDF curvature → neuro-lattice, Cauchy → dyson, blackbody → sono, DE/orbit → newton, …). Per-fork row lists are in the NOTES.

## Per file
| id | HEAD defect (rescue) | New ideas (visibility at saved defaults) | Cost (coordinator, idle, 192 px, median of 5 interleaved min-of-drained, **load 9–14 from other sessions**) |
|---|---|---|---|
| gen-newton-fractal | traps measured the converged tail → every pixel saturated (meanL 0.883 / stdL 0.011); constant nearest-root index (one colour per basin) and wrong roots at degree 4.35; banded "smooth" count; accents +1.2 pre-ACES; constant halo | DE filament 36.5 % / 21.6 % (192/576); Riemann-sheet tint 11.2 % / 11.7 % | 1.26× (4 of 5 rounds 1.2–1.29, 1 outlier at 0.68) — just under the 1.3× cap; look: meanL/stdL 0.883/0.011 → 0.713/0.143 |
| gen-bismuth-singularity-loom-engine | hard vertical tear at screen centre (adjacent-column luma jump 7.5× the frame mean) from the wedge repeat + twist; wedges now mirrored | terrace oxide bands 82 %/78 %; hopper growth lines 23.5 %/16.5 %; frame-dragged lensing 9.4 %/10.0 % | 0.87× |
| gen-cybernetic-crystalline-neuro-lattice | none (header listed 2 of 5 ideas; fixed) | action-potential wavefront 14/21/49/0.1/29 % over T0 0–16 s (gyroid pixels only); SDF curvature edge wear 14–44 % | 1.03× |
| gen-hyperbolic-crystal-symbiosis | click ring centred in the wrong space (centroid (0.96, 0.21) for a click at (0.8, 0.3) → now (0.82, 0.31)); ring ~0.09 peak → visible | hourglass sector zoning 87 %/89.5 %; cleavage hypercycles 37.5 %/34 % | 1.11× |
| gen-liquid-neon-cyber-metropolis | camera inside a tower for 23 % of the orbit (flat walls); `pow(negative, 2.0)` ×2 in traffic lanes | sign columns 3–12 %; roof panel seams 16–26 %; roof beacons 0.2–5.6 % | 0.93× (noisy 0.68–1.87) |
| gen-cyber-organic-liquid-neon-pulsar | pointer dent / lighting / beam axis mixed object and screen frames (dent mirrored away from the cursor at T0 = 40) | polar-cap spark carousel 1.3–6.3 %; dipole L-shell rings 7–41 % | 1.17× (noisy 0.70–1.33) |
| gen-sonoluminescent-chrono-geode-matrix | `flashRate` included `bass·0.6` so any bass change re-phased the whole flash (99.8 % of pixels changed at bass 0→0.05); `pow(negative)` hardening | Rayleigh–Plesset afterbounce up to 100 % at φ ≥ 0.2 (7.7 % at φ = 0.05); blackbody ember afterglow 7.7–15.8 % | 0.75× (noisy 0.41–1.22) |
| gen-crystalline-chrono-dyson | none (HEAD renders a readable lattice); header gained the 3 ideas already in the body | Cauchy-dispersed plate transmission **2.6 %** (below the several-percent target; widening it would light plates that cannot see the quasar); lume sweep hand 3.6/11.7/4.8 % | 1.19× |
| gen-neuro-kinetic-liquid-gold-lotus | camera looked horizontally with y flipped (lotus upside-down, cropped) and petal domain repetition collapsed 8 petals into a blob | mirror-gold reflection 10.8 %/10.4 %; Kajiya-Kay vein highlight 4.4 %/4.3 % | 1.41× vs HEAD, but variant timing (5 rounds): rescue-only vs HEAD ≈ 1.35–1.4×, shipped vs rescue-only ≈ 1.0× — **the cost is the rescue drawing the actual lotus, not the ideas** |
| kimi-nebula-depth | Sobel magnitude `\|gx+gy\|` is 0 on a diagonal family; paper grain was one global value; vignette spring never persisted | dot gain + minimum printable dot 22.3 %/23.0 %; off-register colour plate 43.8 %/18.7 %; ink pooling 13.2 %/7.1 % | 1.10× |

## Not verified / open (read these before marking ready)
1. **Real-GPU look.** Default-look changes: newton (meanL 0.88 → 0.71), lotus (0.046 → 0.078, now in frame), sono idle brighter (0.166 → 0.202), metropolis aerial camera + roof grid, pulsar L-shell rings on a near-black body, bismuth mirrored wedges (alternate cubes now twist in opposite handedness — does it still read as "six cubes"?), neuro-lattice wavefront legibility (halos/dimming, not a crisp ring).
2. **Dyson Cauchy idea is 2.6 % of the frame** — kept, below target; owner's call whether it earns its place. `dysonClock()` scrubs when Flux Speed moves, so the lume hand jumps with it.
3. **Pulsar exposure** (`mix(bg, col, t/10)` inverted; body keeps ~24 % colour) and the pulsar `palette` adding the hue slider twice were left alone — fixing them changes the default look (idle meanL 0.12 → 0.44).
4. **Metropolis / sonoluminescent have `params: []`** in JSON: the host shows no sliders for them although the WGSL consumes four `zoom_params`; the dead-slider audit scans 0 definitions for them. Out of scope for an upgrade pass; flagged.
5. Newton's distance estimate is heuristic under the default noise perturbation (a perturbation floor was added after the first version under-estimated by ~100×).
6. Lotus JSON param ids (`rotationSpeed`, …) don't match their WGSL roles; kept byte-exact.
7. Timings: another session shared the machine (load 9–14); treat ±15 % as noise. Neuro-lattice's wavefront only costs on gyroid pixels.
8. Unanchored reviewer pass not run (batch-37 reviewers found 14 real defects after the forks had self-measured; this batch should get one before it is marked ready).
