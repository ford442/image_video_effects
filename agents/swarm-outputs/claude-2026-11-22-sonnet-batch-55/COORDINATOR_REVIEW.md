# COORDINATOR_REVIEW — sonnet/batch-55 (ink, fabric, lattice, interactive optical distortion — 10 shaders)

Worktree `/root/iv-sonnet-batch-55`, branch `sonnet/batch-55` from origin/main 9b2eeba8. Five forks (A ink pair, B knitted+lenticular, C hyperbolic+kaleidoscope, D lattice generators, E radial-rgb+focal-pixelate). All ten were already 2nd+ pass (every file had `Ideas:`). Briefs: `BRIEFS-fork{A..E}.md`; per-shader notes `NOTES-fork{A..E}.md`. **Uncommitted at the time of writing.**

## The user's failure list vs what was true

"Most lack the dataTextureC load / missing ACES / writes to dataTextureB / missing plasmaBuffer, including two that claim audio-reactive."

- **dataTextureC load:** true of all ten at HEAD, but only ONE file got one: `ink_dispersion_alpha` (capillary wick + dye fringe — ink creeping through paper over time is native). The other nine are stateless mappings of the source frame; a C read there would be the checklist overlay (§3/§4.1), and the briefs say why per file.
- **B writes:** real on five. `gen-aetheric` (zeros), `radial-rgb` (never read: host copies B→C then A→C) and `focal-pixelate` (unread metadata) lost them; `knitted-fabric` and `lenticular` keep their documented material/mask quads.
- **Audio claims:** the two were `mouse-hyperbolic-navigator` (no audio read at all) and `breathing-kaleidoscope-morph` (read `zoom_config.x`, which is TIME, as audio). Both now read `plasmaBuffer[0].xyz`.
- **ACES:** not the problem: seven already had it; the three without (ink pair, kaleidoscope) are photo-passthrough and keep the batch-52 P-ACES policy (no ACES on the photo path).
- **Real defects the list did not name** (found by varying inputs on HEAD): lenticular's view spring lived in zeroed `extraBuffer[133..134]` (mouse X never steered the print); kaleidoscope `Segments` slider pinned at 1 by `max(1.0, slider)` (never a kaleidoscope); focal-pixelate `domainWarp` returned an absolute position (the "purple lens disc"); radial-rgb Dispersion dead at the saved default (k1=k2=0); origami KIFS "rotation" was a shear (plaid collapse at several times, constant hopper inset); hyperbolic-navigator Möbius point escaped the disk (|a| up to 1.9); ink_dispersion_alpha JSON claimed fluid-sim/advection/mouse-spawn for a stateless halftone; ink-dispersion-guided `paper_tex` was a time-scaled hash.

## Per shader (pass against the cards)

| id | ADD (idea → where) | §12.2 row | A packing | default look vs HEAD | timing (paired median, loaded box) |
|---|---|---|---|---|---|
| ink_dispersion_alpha | fibre-guided capillary wick (exact C); dye chromatography fringe (C ring) | none | display RGBA, C read back as the same colour+coverage | 38.2 % px, meanL 0.312→0.289 | 1.27–1.37× (**over cap**: 8 exact C loads) |
| ink-dispersion-guided | perspective screen pitch (depth → pitch); depth-silhouette ink contour | none | display RGBA (ink colour, coverage) — unchanged | 34.9 % px, meanL 0.347→0.343 | 1.02× |
| knitted-fabric | round-yarn tube shading + Fresnel sheen; loop-over-loop cast shadow | Fresnel–Schlick (F) | ACES display RGBA; B masks kept | 23.5 % px, meanL 0.296→0.303 | 1.13× |
| lenticular-holographic-shift | cylinder-lens magnification; adjacent-view crosstalk ghost | none | display RGBA; B quad kept | **77 % px** (rescue), meanL 0.486→0.486 | 1.03× |
| mouse-hyperbolic-navigator | conformal gutter (constant hyperbolic width); Circle-Limit two-colouring | none | ACES display RGBA | 64.6 % px, meanL 0.306→0.305 | 1.05× |
| breathing-kaleidoscope-morph | reflection loss per mirror bounce; Kramer–Bruckner toggle mapping | Fold count as material (E) | display RGB + top-hat luma alpha, now also stored to A | **99.3 % px** (rescue: Segments), meanL 0.389→0.442 | 1.13–1.25× |
| gen-aetheric-tachyon-lattice | axial tachyon packets; soft inverse-square halo | Soft inverse-square (F) | ACES display RGBA | meanL 0.084→0.152, meanA 0.15→0.24 | 0.90× |
| gen-ethereal-neon-bismuth-origami | hopper stair-step rings; step-count AO | Step-count AO (E) | ACES display RGBA | **95.2 % px** (rescue: KIFS rotation), meanL 0.822→0.791 | 1.02–1.26× (noisy; forks measured 0.79–0.88) |
| radial-rgb | Cauchy lateral colour; radial coma tails | Cauchy dispersion (F) | ACES display RGBA | 10.6 % px; bit-identical at Dispersion 0 | 1.02× |
| focal-pixelate | CFA zipper in the fringe; highlight-weighted hex defocus | CFA zipper (A) | **changed**: raw metadata → ACES display RGBA (nothing read the metadata) | **64 % px** (rescue: domainWarp), meanL 0.233→0.200 | 0.98× |

§12.4 de-dup: no §12.2 row appears on more than two files (Fold count: aetheric at HEAD + breathing; Cauchy: hyperbolic at HEAD + radial-rgb). No spring, ripple overlay, IQ palette, `fwidth`, or `extraBuffer` write was added; every `// ── Idea n` is findable in the diff. Saved `params` are byte-exact in all ten JSONs (only `description`, tags/features that became true or false, and additive `x-meta.upgrade.params` on focal-pixelate changed).

Timing was taken at box load 5–10 (other sessions); `mr_ab` interleaved, 256 px, SwiftShader. Re-time on a quiet box before trusting the two borderline files.

## Gates (final tree)

precommit 10/10 (0 extraBuffer violations, 0 pasted headers) · naga-wasm 10/10 · dead sliders 0 new · extraBuffer audit pass · `upgrades:record` scoped with `--ids=` → 9 changed + 1 new (origami's first ledger entry) · `generate_shader_lists` · `verify:shaders:fix` **11/11** · `npm run build` ok · Vitest 2039 passed / 1 failed / 1 skipped (227 files). **The one failure is NOT this batch:** `src/renderer/webgpu/physicsLabSet2.test.ts:236` expects `physarum-agents-step` to store `min(c.r + dep, TRAIL_CAP)`; main's `597b0448` (grok batch-58, #1732) added `* satiation` to the shader without updating the test. Both files are identical to origin/main in this tree.

Mistake caught: the first `upgrades:record` ran WITHOUT `--ids=` and recorded the whole catalog (+921 ledger lines). I restored `reports/shader-upgrade-ledger.json` from git and re-ran it scoped; the final ledger diff is 93+/9−. Always pass `--ids=` (see sonnet/batch-38/39 notes).

Post-gate cleanup: `git restore` the regenerated `reports/*` (except the ledger) and `public/shader-search-index.json`; keep the six `public/shader-lists/*.json` (the JSON edits changed them) and the ledger.

## Open calls for the user

1. **Default looks change loudly on five files** (lenticular 77 %, hyperbolic 65 %, focal-pixelate 64 %, kaleidoscope 99 %, origami 95 %) — all caused by rescues of verified HEAD defects, not by the ideas. Lenticular: HEAD's baked −0.8 view offset is gone at rest (raise the `sin(time*0.3)*0.1` idle sway for a resting colour shift). Origami: reverting the KIFS rotation fix would make both new ideas invisible.
2. **focal-pixelate A repacked** raw metadata → ACES display RGBA (nobody read the old packing). Depth-fog direction ambiguous (normalizeDepthMap near=0 vs harness near=high); fog dims even the in-focus disc ×0.22–0.47 — left as HEAD.
3. **ink_dispersion_alpha** is 1.27–1.37× HEAD (8 exact C loads). Lower the wick strength `0.40+0.35·inkDensity` or drop a ring tap if the cap matters; stale search `tags` (fluid, curl, water) in its JSON left alone. `mouse-driven` is true only via a pointer vignette.
4. **breathing-kaleidoscope-morph** output alpha is the top-hat luma (meanA ≈ 0.05, the documented packing): a downstream slot treating alpha as opacity sees it nearly transparent. Tile Count (navigator) and Segments (kaleidoscope) are now stepped (10 positions).
5. **ink-dispersion-guided** silhouette contour needs a real depth map to judge (harness discs differ from the photo discs); pitch range / `1.6·depth_influence` are the knobs.
6. **gen-aetheric** halo lifts the near-strut void off pure black (`haloAmt` 0.002; 0 restores it). **origami** bass breath `0.06` changes 91 % of pixels loud vs silent — lower if it reads as jitter; still pastel by default because every ray hits.
7. Real-GPU visual QA and thumbnails refresh are external (Shader Scanner → stale thumbnails).
