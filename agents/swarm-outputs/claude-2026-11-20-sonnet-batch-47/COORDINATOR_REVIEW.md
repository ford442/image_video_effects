# COORDINATOR_REVIEW — sonnet/batch-47 (2026-11-20, Sonnet 5.5)

Branch `sonnet/batch-47` in `/root/iv-sonnet-batch-47`, from origin/main 62680da7. Five 2-shader forks (A–E) per `COMMON.md`; briefs/notes per fork in this directory. The coordinator migrated the 7 pasted-binding files to `_prelude.wgsl` before the forks started (header-only, no `Upgraded:` bump).

First pass: `spec-temporal-path-tracer`, `gen-chrono-erosion-feedback-melting`. Second pass (existing `Ideas:` kept verbatim): the other eight.

## Per-file verdict vs the Idea Cards (§9 + §12.7 checklist)

| id | new ideas (formula row) | rescues | A packing | pass |
|---|---|---|---|---|
| interactive-rgb-split | Brown–Conrady radial growth (§12.2B); per-channel 3-tap spectral band smear (kernel deepening) | none | ACES display RGBA (unchanged) | ✅ — 1.27× HEAD, at the cap |
| chromatic-swirl | Cauchy radial lateral colour (§12.2F); Rayleigh in-scatter of absorbed light (§12.2F) | none | telemetry (unchanged) | ✅ — see decision 1 |
| gen-strange-field-flow | fold count as material (§12.2E); orbit-trap hit time tints stalks (§12.2E) | none | ACES display RGBA (unchanged) | ✅ — 1.22× |
| gen-topological-acoustic-knots | Frank splay/bend tint (tactics 3/7); Landau–de Gennes order-parameter core melt | R1 wrap Δθ ±π/2; R2 defectGlow polarity; R3 defect x × aspect; R4 core gain 2.0 → 0.7 | ACES display RGBA (unchanged) | ✅ — see decision 2 |
| spec-temporal-path-tracer | stratified march lattice; hit-distance falloff (§12.2F soft inverse-square); source-fingerprint history rejection (TAA) | none | raw accumulation; `A.a = n + 0.9·fp` | ✅ — 1.14× |
| gen-chrono-erosion-feedback-melting | flow-lane persistence (tactic 4); macroblock motion carry (§12.2B) | half-texel bias; exact C loads; dead spring pinned to cursor; dead `plasmaBuffer[1..8]` → FFT bins | display-colour history, ACES on writeTexture only | ✅ — see decision 3; 1.235× |
| chronos-brush | wet-edge pooling (§12.2C); dwell pressure (§12.2C) | none | raw feedback RGBA, `.a` freshness (unchanged); rim display-only | ✅ — 1.25× |
| voronoi-zoom-turbulence | exact bisector wall distance → chamfer bevel (tactic 1); turbulent lattice warp (§12.2E domain twist) | none | ACES display RGBA (unchanged) | ✅ — 1.11–1.35×, see decision 5 |
| hyb-chromatic-circuit | via pads with annular ring + drill; copper-ridge bevel under solder mask (§12.2E SDF normal) | `pow(negative, 2.0)` → squares | ACES display RGBA; small depth relief added | ✅ — 1.15× |
| gen-rgb-diffraction | chromatic Airy rings (§12.2F Airy); order-dependent dispersion of grating lobes | two negative-base `pow`s | ACES display RGBA, exact C | ✅ — 1.05–1.1× |

## Checklist

- [x] Idea Cards + mechanism interrogation written before WGSL (BRIEFS-fork{A..E}.md).
- [x] Each numbered idea findable: `// Idea n —` comments in all ten files (the two brush/voronoi files use `// Idea n —` without the box dash).
- [x] KEEP VERBATIM holds; all nine changed definitions have `params` byte-identical to HEAD (checked by script). `chromatic-swirl` JSON untouched (no `description` key).
- [x] No generic overlay: no spring/ripple/IQ-palette stamp anywhere. The only pointer ideas are on `chronos-brush` (owns the pointer).
- [x] §12.2 row de-dup — no row on more than two files, none shared inside a fork: Brown–Conrady (rgb-split); Cauchy + Rayleigh (swirl); fold count + orbit trap (strange-field); soft inverse-square (path tracer); macroblock carry (chrono-erosion); §12.2C wet-edge + dwell (brush); additive domain twist (voronoi); SDF normal (circuit); Airy (diffraction). Acoustic-knots uses tactics, not a row.
- [x] Each formula consumes a quantity the file already had; no new solver/state/binding/spring.
- [x] No `fwidth`/`dpdx`; every `pow` guarded.
- [x] Springs/ripples: none added.

## Gates (final tree, coordinator re-run)

| gate | result |
|---|---|
| `wgsl_precommit_gate.py --files` (10) | 10/10 |
| `verify-naga-wasm.mjs --files` (10) | 10/10 valid, 0 new |
| `audit_dead_sliders.py --files` (10) | 0 new |
| `audit_extrabuffer.py` | PASS |
| `npm run upgrades:record -- --ids=…` | 10 upgraded, 0 new |
| `npm run verify:shaders:fix` | all 11 gates pass |
| `npm run test:ci` | 212 files, 1944 passed / 1 skipped |
| `npm run build` | ok |
| coordinator sanity render (SwiftShader, 192 px, 12 frames, `SRC=img`) | 10/10: 0 NaN, no validation error, none blank/saturated |

Generated churn discarded: `reports/*` (except `shader-upgrade-ledger.json`) and `public/shader-search-index.json`. Kept: ledger, `public/shader-lists/*`, `src/contracts/prelude_migration.json`.

## Open decisions for the user (none is a gate failure)

1. **chromatic-swirl in-scatter changes every pixel** (95.7% differ > 2/255; mean luma 0.155 → 0.188) and turns the dead-black core into a navy haze. Lower or drop the Rayleigh ω = 0.18 if the black core is identity.
2. **gen-topological-acoustic-knots: four rescues change the default look** (98.7% of pixels). R2 (inverted `defectGlow` polarity) removes a flat warm veil (meanL 0.66 → 0.37). R3 multiplies defect x by aspect — **not rendered at 16:9** (`mr.mjs` is square); the most debatable one. R4 `CORE_GAIN = 0.7` (HEAD 2.0 whited out about half the frame); set `CORE_GAIN = 2.0` to restore HEAD. Unfixed, also at HEAD: thin horizontal atan2 stripe-phase seams left of defects.
3. **gen-chrono-erosion-feedback-melting: ACES added** (plumbing floor) — pales the picture (meanL 0.425 → 0.525); one line to remove. The half-texel and exact-load rescues change the long-run look too. Dead FFT path only verified with synthetic bins. Unfixed, also at HEAD: sustained loud audio (bass+mid+treble > 0.7) inverts the loop every frame and collapses to flat grey.
4. **hyb-chromatic-circuit / gen-rgb-diffraction:** the circuit now writes a small depth relief (±0.02) — new data for downstream; one-line revert. Diffraction's HEAD fringe frequency is `freq·λ` (red tightest, physically inverted); it was left because six existing ideas depend on it, so the new Airy/order layers (red outermost) disagree with it about which wavelength is larger. Hex grid in the circuit has no aspect correction (about 1.78× stretch at 16:9) — left as the saved look.
5. **Timing is noisy** (box load 5–30 during forks). interactive-rgb-split (1.27×) and voronoi (1.11–1.35×, min-of-mins ≈ 1.26×) are at the ~1.3× cap; chrono-erosion 1.235×. Re-time on a real GPU.
6. **chronos-brush:** output has been history-only (black outside strokes) since 2026-05-30 — treated as identity. Loud bass pins freshness near 1 (`alpha += bass*0.05`), so a held brush blooms to 1.6× without dwelling and the wet-edge flattens.
7. **Cleanup candidate, untouched:** voronoi-zoom-turbulence still carries an inert HEAD `extraBuffer[133..138]` spring (zeroed every frame by `audioDepth.ts`).
8. **Path tracer:** history rejection verified only with a stale-history proxy, not a real changing video; the 1-scalar fingerprint has false negatives where local luma coincides.

Real-GPU visual QA, pointer feel (brush dwell), and thumbnails remain external; Shader Scanner → *Stale thumbnails only* will pick up all ten.
