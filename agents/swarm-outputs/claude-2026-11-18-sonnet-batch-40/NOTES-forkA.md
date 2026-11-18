# NOTES — fork A (gen-newton-fractal, gen-bismuth-singularity-loom-engine)

Files touched: `public/shaders/gen-newton-fractal.wgsl`, `public/shaders/gen-bismuth-singularity-loom-engine.wgsl`, `shader_definitions/generative/gen-newton-fractal.json`, `shader_definitions/generative/gen-bismuth-singularity-loom-engine.json`, and (by `scripts/migrate_to_prelude.py`, infra, no `Upgraded:` bump for it) `src/contracts/prelude_migration.json` (the `gen-newton-fractal` id left `pending` — coordinator-owned; check the diff, the file also carries other forks' removals). No commits.

Code numbering vs card numbering: Newton's file already used `Idea 1/2` + `Native idea 1/2` for its four existing ideas, so the card's ideas 1/2 are **Idea 5 / Idea 6** in the WGSL. Bismuth's card ideas 1/2/3 are **Idea 6 / 7 / 8** in the WGSL (existing Ideas 1–5 keep their numbers).

Visibility numbers: scratch copy with the idea's contribution multiplied by 0 (string-replace on one expression), saved-default sliders, idle, no audio; % of pixels with max-channel |Δ| > 0.02 and mean |Δ| on the raw RGB panel.

---
## gen-newton-fractal

**KEEP VERBATIM — held.** 4 params and roles; cpower/cdiv Newton step with `relax` (click waves, held mouse) and complexNoise perturbation; four-shape orbit-trap set (ring / axis / diagonal / spiral) and orbitMin/orbitSecond; multi-root colour accumulation; SDF smooth-union halo; convergence-order sheen; striations; wander dust; RD accent in the sub-1/256 fraction of A.a (unpack/sampleState untouched); 3 % temporal colour mix; chroma shift; ACES on display colour (clamp ≥ 0 is guaranteed — every term is additive and non-negative); semantic alpha + depth. **A packing unchanged:** ACES display RGBA, A.a = floor(convAlpha·255)/256 + rdState·(0.999/256). New terms go into rgb only.

**Infra:** pasted 13 bindings + `struct Uniforms` → `#include "_prelude.wgsl"` (migrate script, header-only).

### HEAD render vs the card's premise (card premise: "washed-out wall" — confirmed, and much worse than a gain problem)
| case (saved defaults 0.5,0.45,0.55,0.5; 192 px, 60 frames) | HEAD meanL / stdL | NEW meanL / stdL | note |
|---|---|---|---|
| idle | 0.883 / 0.011 | 0.713 / 0.143 | 5 distinct coloured basins, nested fractal boundary, gold filament |
| held cursor (0.4,0.6,1) | 0.882 / 0.012 | 0.705 / 0.123 | cursor also pans the view (zoomCenter, HEAD behaviour) |
| audio 0.8/0.5/0.9 | 0.911 / 0.009 | 0.760 / 0.124 | |
`nan` = 0 in all, also with `A16=1`. Slider sweep (zoom 0/1, degree 0/1, precision 0/1, boundary 0/1): all eight pictures change (meanL 0.61–0.75), no dead slider.

### Rescues (not ideas; all confirmed at HEAD by reading AND by render/ablation)
- **R1 orbit traps saturate (confirmed).** Traps took the min over ALL iterations including the converged tail, where z ≡ root ∈ {|z|=1} ∪ (root 0 ⊂ real axis) → `trapGlow ≈ trapIrid ≈ 1` everywhere. Fix: traps only see steps with `|dz| > TRAP_GATE (0.35)` (L17, L239-251; the converged tail now also skips the trap's atan2/log). Gate sweep 0 / 0.1 / 0.25 / 0.5 compared at 192 px; 0.35 chosen. Ablating the gate (back to 0) changes **88.5 % (192) / 90.1 % (576)** of pixels, mean |Δ| 0.13–0.14.
- **R2 `nearestIdx` constant (confirmed).** `fract(theta/rootStep+0.5)·degree+0.5` = 0.5·degree+0.5 for every converged z → one blue for all basins in 47 % of the colour. Fix: argmin over the live root list inside the existing loop (L270+).
- **R2b root list ≠ roots at non-integer degree (confirmed).** Default degree = 4.35: principal-branch roots are m·TAU/n for |m| ≤ n/2 (5 roots: 0, ±83°, ±166°); HEAD listed k·rootStep, k=0..3 (a fake root at −112°). Verified in a clean render (p4=0): five basin discs exactly at those angles. New helpers `rootMult` / `rootAlive` (L69-81), same MAX_ROOTS = 6.
- **R3 smooth iteration count dead for converged pixels (confirmed by reading).** `tol/max(|dz|,tol)` ≡ 1 when |dz| < tol → integer bands in `iterRatio` and in the isochrones. Fix: `iters − log2(max(log|dz|/log tol, 1))` (L261-264).
- **R4 energy budget (confirmed by ablation).** With every accent term removed meanL is 0.451; the always-on accents (trap, iridescent trap, SDF halo, RD) added ≈ +1.2 pre-ACES → clip to white. Sharper trap falloff (7+10b+4t → 20+25b+8t; 3+6b → 8+14b) and gains (trap 2.0→1.2, irid 0.7→0.5, halo 0.85→0.5, RD ×0.5) at L294-300, L329. Relative roles unchanged.
- **R5 SDF root halo was a constant (confirmed by reading).** It measured `length(z − root)` at the converged z (sdf ≡ −rootRadius → flat 0.55). Now measured from the start point `p` (L310) → glowing halos around the roots, visible as the lighter disc in each basin centre.
- Not touched: the horizontal seam on the negative real axis at fractional degree is the branch cut of `cpower` (identity of the fractional-degree morph) — now used by Idea 6.

### Ideas (new, native) — card + §12.1 interrogation in `BRIEFS-forkA.md`
- **Idea 5 — basin-boundary distance-estimate filament** (L215-222 accumulation, L338-360 shading). Green's-function DE of the superattracting basin, d = 2·L·e_n·sinhc(G)/|z_n′| evaluated in logs (the 2ⁿ cancels), with N′(z) = (zⁿ−1)(n−1)/(n·zⁿ) from the zn the loop already computes; width in pixels of the warped plane so the line keeps its thickness at any zoom. **Visibility: 36.5 % of pixels at 192 / 21.6 % at 576 (mean |Δ| 0.039 / 0.022).** Verified the estimator numerically in a clean render (p4 = 0): median 17.7 px inside basins (basin discs ≈ 30–40 px at 192), → 0 at the boundary. **Honest caveat:** the default has noise perturbation (p4 = 0.5), which makes convergence linear, not quadratic; the pure theory then under-estimates d by ~100× (first attempt: median 0.16 px, filament everywhere). The shipped version adds the noise's linear contraction as a floor `rhoP = 0.9·perturbStrength` in quadrature (to both e_n and the per-step derivative). It is a heuristic in that regime (median 5 px at p4 = 0.5, 3 px at p4 = 1), Koebe-style bounded in the clean regime only. The line is a cream-gold outline 2–4 px wide on the fractal boundary at 576.
- **Idea 6 — Riemann-sheet hop tint** (L224-229 count, L362-367 tint). Orbit crossings of the `cpower` branch cut (negative real axis) are counted; basin colours of hopped orbits are hue-rotated (`color.brg`), amplitude |sin(π·n)| = the size of the jump of zⁿ across the cut (0 at integer degree, 0.89 at the default 4.35). **Visibility 11.2 % / 11.7 % (mean |Δ| 0.006 / 0.008)** — it paints the left-hand lobes the orbits reach by hopping (a structured set, 12.7 % of pixels have ≥ 1 hop at the default). It is quiet by design; at integer degrees it vanishes.
- §12.2 rows: none reused from the table (derivative distance estimate + branch-cut count are native to this file); batch de-dup unaffected.

### Cost (SwiftShader, min-of-drained-frames, interleaved HEAD/new; machine load 8–20 from sibling forks, so noisy)
Idle: median ratio **1.09** (10 rounds, 224 px), 1.19 (5 rounds, 192 px), 1.35 / 1.40 in two loaded runs. Audio: **1.28** (10 rounds), 1.56 in a loaded 6-round run. Net extras: one cdiv + one log per iteration and a short post-loop DE; the trap skip in the converged tail pays some of it back. The coordinator should re-time alone.

### Open items
- Default look is a large change (white wall → coloured basins); real-GPU eyeball needed.
- Filament is heavy at 192 (36 % of pixels) because the fractal boundary is dense there; if it reads too bright, lower the 1.1 gain at L359.
- DE under perturbation is heuristic (above). `x-meta`/params untouched. `features` gained `distance-estimate`, `riemann-sheet-tint`; description +57 chars.
- `hashf`, `smin` etc. unchanged; `TRAP_GATE` is a named const, not an exposed slider.

---
## gen-bismuth-singularity-loom-engine

**KEEP VERBATIM — held.** 4 params and roles; six-wedge ring with per-sector assembly stage (Idea 1) and proper-time dilation (Idea 2); boolean-subtraction carve loop incl. fractional carve and extrusion; step-wise lensing; glow/flux veins with FFT split; step-count AO; cosine iridescence on n·v with the slider frequency and dilated fringes; edge cathodoluminescence; shadow + photon arcs; click rings; memory trails; alpha / hit depth. **A packing unchanged:** HDR linear RGB (pre-ACES) + semantic alpha, C read back as HDR trail memory, ACES only on `writeTexture`. No spring added (the existing one stays inert, as noted in the header).

### HEAD render vs the card's premise
| case (saved defaults 0.5,5,2,1; 192 px, 60 frames) | HEAD meanL / stdL / meanA | NEW meanL / stdL / meanA |
|---|---|---|
| idle | 0.387 / 0.176 / 0.847 | 0.398 / 0.154 / 0.881 |
| held cursor (0.4,0.6,1) | 0.376 / 0.186 / 0.844 | 0.374 / 0.176 / 0.848 |
| audio 0.8/0.5/0.9 | 0.550 / 0.110 / 0.957 | 0.542 / 0.113 / 0.955 |
`nan` = 0 everywhere incl. `A16=1`; pointer corners (0,0,1) and (1,1,1) render (0.374 / 0.308 meanL, not inside a solid). Slider sweep: Mass, Iterations (1 → flat grey block, same as HEAD), Fringe frequency, Extrusion (0 → mostly empty, 0.107 vs HEAD 0.093; 3 → 0.476 vs HEAD 0.489) all change the picture; the Iterations = 1 and Extrusion = 0 extremes are inherited, not regressions.

### Rescue
- **R1 sector-boundary tear (confirmed by render).** The default camera sits in the x = 0 plane = a wedge boundary; at HEAD the 576 px render has a hard vertical tear at x = 288 (adjacent-column luma difference 0.189 = 7.5× the frame mean, half a horizon disc, small cubes left vs beams right). Cause: `a_mod` is a rotation repeat and the twist after it makes the content asymmetric in z, so position is discontinuous at all six boundaries even though the stage blend is continuous (the code comment claimed no tear). Fix (L98-109): reflect odd wedges (`a_mod = -a_loc` for odd `sectorId`; 6 is even so the ring closes), keep `side`/`edgeW` on the unmirrored `a_loc`. Result: max adjacent-column difference around the centre 0.038 (1.6× mean), the shadow disc is whole. Ablating the rescue changes **57.4 % (192) / 59.8 % (576)** of pixels.

### Ideas (new, native) — cards in `BRIEFS-forkA.md`
- **Idea 6 — terrace-depth oxide bands** (§12.2E "fold count as material"; L272-277 + `mapInfo` L80-). `mapInfo(.., wantInfo)` returns which carve level defined the surface; the palette phase is offset by 0.11 per level, so each stair step has its own interference order. **Visibility 82.4 % (192) / 78.1 % (576) of pixels, mean |Δ| 0.26 / 0.24** (every hit pixel changes colour).
- **Idea 7 — hopper growth lines** (L279-283). Contours of the median of |q| (in-plane offset) × `scale` in the winning carve's box frame = concentric rectangles on each tread, frequency scaled by resolution (3–10 per carve unit), −38 % brightness in the groove. **Visibility 23.5 % / 16.5 %, mean |Δ| 0.015 / 0.011.**
- **Idea 8 — frame-dragged lensing** (L216-225). Lense–Thirring tangential kick ∝ rs/r³ around +y, windowed to 1.5–4 rs. First version (no window) changed 68 % of pixels everywhere — a lattice this sensitive turns any ray perturbation into noise, which is NOT a swirl; the shipped window gives inner disc (r < 0.2 H) 46.5 % / outer 4.0 % at 192 and **9.4 % / 10.0 % of the frame overall (mean |Δ| 0.021 / 0.019)**, concentrated at the horizon.
- The info computation (level, growth coordinate) only runs once, at the hit; the march and the normal use `map()` = `mapInfo(.., false).x`, and the drag sits behind `if (dist < 4 rs)`. Verified the restructure is pixel-identical to the first version (0.00 % pixels differ).

### Cost
Idle median ratio **1.08** (8 rounds, 160 px; 1.39 in an earlier loaded 5-round run before the info/branch restructure); audio **0.99** (10 rounds). Load 8–20 from sibling forks, so noisy; the coordinator re-times alone.

### Open items
- Mirror wedges mean alternate cubes have opposite twist handedness; a real-GPU look should confirm it still reads as "six cubes".
- `sprung-pointer-twist` is still listed in `features` although the spring is inert at HEAD (engine zeroes extraBuffer[133..255] each frame): left as-is, not my change to prove/alter. FFT bins `extraBuffer[6,9,12]` are real engine FFT bins.
- Growth lines are faint (≈2 visible rings per face at 576); the −38 % groove can be raised at L283.

## Gates (both files)
`python3 scripts/wgsl_precommit_gate.py --files …` pass; `node scripts/verify-naga-wasm.mjs --files …` pass; `npm run audit:dead-sliders -- --files gen-newton-fractal gen-bismuth-singularity-loom-engine` 0 new; `npm run audit:extrabuffer` 0 new (the bismuth inert spring writes are the known baseline). Not run (coordinator): Vitest, build, ledger, lists.
