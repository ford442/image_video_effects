# NOTES — fork E (kaleido-scope, neon-edge-glow) — sonnet/batch-38

Both files: 2nd pass. `Upgraded:` and `Ideas:` lines were appended to, never replaced. No git commits. SwiftShader + naga proof only — **no real-GPU visual claim**.
Harness: `agents/mr.mjs` (unmodified). Scratch copies in `…/scratchpad/forkE/`: `mr_scene.mjs` (loads `public/fixtures/thumbnail-scene.png` as the source — the synthetic `SRC=img` has only two strong edges, which is useless for an edge filter) and `mr_perf.mjs` (min-of-drained-frames). Saved-default sliders passed explicitly (kaleido 0.3,0.5,0.5,0 · neon 0.85,0.6,0.4,0.9). Visibility = % of pixels with max-channel |Δ| > 0.02 vs a scratch copy with that one contribution zeroed, same time, same sliders.

---

## 1. kaleido-scope

**KEEP VERBATIM held:** `poincareMap` fold + `hypR`, segments morph (tessA/tessB), `lensDistort`, mouse-shifted `center`, depth CA split, `boundary`/`metal`/`vertex`, hypR crease (old Idea 1), opposite-wedge mix 0.28 (old Idea 2), 4 params and roles, ACES, A = writeTexture RGBA. **A packing: ACES display RGBA (unchanged).** JSON params byte-exact; features unchanged; description +50 chars; `x-meta.upgrade.params` already present.

**Labels:** the file's earlier comments already used "Idea 1 / Idea 2" for the previous pass, so this pass is labelled **Idea 3 = card idea 1** and **Idea 4 = card idea 2** in the WGSL.

| What | Where (`kaleido-scope.wgsl`) | §12.2 row |
|---|---|---|
| Idea 3 — mirror loss per bounce | `poincareMap` L52-56 (`bounces`), `main` L122-128 | fold count as material (E) |
| Idea 4 — tumbling object cell | `main` L96-101, `+ tumble` on `sampleUV`/`oppUV`/`caR`/`caB` | native |
| Rescue 1 — atan2-cut seam | `poincareMap` L44-51, `main` L132-133 | — |

**Rescue 1 — CONFIRMED.** Analytic jump of the folded angle across θ = ±π with the HEAD formula: 0 only at t = 0 (rot = 0 makes the fold symmetric); 0.14 rad (t = 5), 0.39 (t = 3.14), 0.63 (t = 9.4), 1.02 (t = 0.62), 1.11 (t = 1), **1.85 rad (t = 2)**. Visible in a 4× crop as a hard streak from the left edge to the centre (`kal_seam_crop_3.14159.png`). Fix (≈ 12 lines): `poincareMap` returns the cut distance and the analytic jump; `main` ORs `smoothstep(0.012,0,cutDist)·smoothstep(0.02,0.12,cutJump)` into `boundary`, so the seam reads as one more metal mirror junction (and vertex ring / alpha / depth react like every other seam). The content on the two sides still disagrees; it is hidden, not solved (a non-integer segment count cannot close the circle). When segments is an integer the jump is 0 and no line is drawn.

**Idea 3 — mirror loss per bounce.** Wedge index k = floor(θ'/2π·n) wrapped mod n, nearer way round, bounces = floor(min(kw, n − kw)); colour × exp(−bounces·(0.080, 0.072, 0.064)) × a faint cool tint on odd counts. Primary wedge unchanged; far wedges ≈ 0.75×.
*My first version used `abs(floor(u))` directly — `u` contains `rotation`, which grows with time, so the frame would have faded to black over minutes. Caught by reading, fixed by the wrap, and verified:* meanL (idle, default) t = 3 s **0.429**, t = 400 s **0.451**, t = 3600 s **0.451** (HEAD 0.476 / 0.475 / 0.474) — bounded.

**Idea 4 — tumbling object cell.** `0.10·zoom·(0.4+morphSpeed)·(sin(0.37t+1.3), cos(0.29t))` added to the SAMPLE uv only; mirrors stay put.

**Visibility (default sliders, idle, synthetic source; % px >0.02 / mean|Δ|):**

| size · t | Idea 3 | Idea 4 | Rescue 1 | total vs HEAD |
|---|---|---|---|---|
| 192 · 1.5 | 87.1 % / .053 | 31.2 % / .027 | 0.26 % / .0007 | 90.4 % / .068 |
| 192 · 3.14 | 88.9 % / .056 | 28.7 % / .020 | 0.26 % / .0006 | 91.3 % / .065 |
| 192 · 7.0 | 82.6 % / .039 | 26.9 % / .020 | 0.26 % / .0006 | 85.3 % / .051 |
| 576 · 1.5 | 87.0 % / .053 | 31.4 % / .027 | 0.26 % / .0005 | 90.3 % / .068 |

Rescue 1 is a one-pixel-wide line by design (0.26 % = ~1 px × half a diameter). Idea 4 changes ~30 % of the frame instantaneously; it is a drift, so the effect is in the motion.

**Default-look change:** meanL 0.476 → 0.429–0.451 idle (−5…−10 %), 0.432 held, 0.431 with audio 0.8/0.5/0.9, 0.434 after a 60-frame run. nan = 0 everywhere. Sliders (min→max, % px > 0.02): segments 90.8 %, rotation 79.2 %, zoom 85.4 %, **ring offset 0.1 %** — HEAD's ring only lights where `boundary` is already lit; not changed here, but it is a near-dead slider in practice (audit reports it as used).

**Cost:** frameMs min-of-drained-frames, interleaved, 256 px, 3 rounds: **new/HEAD = 1.09×** (per-round 1.09, 1.03, 1.10). No extra texture taps (the added work is ALU). 

**Gates:** precommit PASS, `verify-naga-wasm --files` PASS, dead-sliders 0 new, extrabuffer 0 new (the gates regenerated `reports/*` as a side effect — I did not revert them; coordinator discards).

**Open / not done (HEAD, outside the card):**
- At default zoom only the inner disc r ≲ 0.17 (≈ 9 % of a square frame) samples real photo content; `hypR = r/(1 − 0.94r)` pushes everything beyond it past the sample-uv clamp, so **~90 % of the frame is the border-clamped edge colour in flat wedges** (visible in every render; zoom = 1 → ~36 % content). It reads as the HEAD "look" and the previous pass built on it, so I left it; the owner may want it as a card of its own.
- Rescue 1 hides the seam, it does not remove it.
- Idea 3's brightness change is large in area (87 % of px). If that is too much for a default, the knob is the three exponents in the `exp(-bounces * vec3(...))` line.

---

## 2. neon-edge-glow

**KEEP VERBATIM held:** 4-tap `edgeMag`, `neonSpectrum`/`mercurySpectrum` line shapes, mains/flicker, tube core + dark sheath (old ideas), `bendUV` hue clock, electrodes, chroma end-shift, haze, depth-driven alpha, ACES, 4 params and roles. **A packing: ACES display RGBA (unchanged; A = display).** JSON params byte-exact; features unchanged; description +62 chars; `x-meta.upgrade.params` added (additive; the file had none).

| What | Where (`neon-edge-glow.wgsl`) | §12.2 row |
|---|---|---|
| Rescue 1 — squares, not `pow(neg, 2.0)` | `sq()` L29, `neonSpectrum`/`mercurySpectrum` | — |
| Idea 1 — ring-gather spill glow | L139-166; `spill` added to `finalColor`, `+ spillAmt*0.3` in `tubeExcitation` (alpha) | native (no §12.2 row — see below) |
| Idea 2 — positive-column striations | L109-132; multiplies `(neonLine + glowBloom + tubeCore)` | native |

**Rescue 1 — NOT VISIBLE on SwiftShader (expected).** Six `pow((t − c)/w, 2.0)` → `sq()`. Render diff HEAD-vs-squares: 0.00 % of px, mean|Δ| 0.0000, at 192 and 576, scene and synthetic. SwiftShader's `pow` evaluates a negative base as a square; whether a real GPU returned NaN there is **not verifiable here**. The only remaining `pow` is `pow(abs(sin(..)), 2.0)` (non-negative base).

**Idea 1 — ring-gather spill glow (native).** *(Trimmed after the coordinator's idle re-time: the first 8-tap / two-ring version measured 1.34–1.41× HEAD at load ≈2, over the 1.3× cap.)* One ring of 4 integer `textureLoad` taps on the axes at r = 0.6·R (R = `glowRadius`·40 px·res.y/1080 → 7.7 px at 576 px, saved default), `|luma(tap) − luma(here)|·edgeStrength` through a knee (0.10→0.40) so texture does not haze the frame, `spillAmt` = mean of the four knee'd values (0..1), result × the pixel's `neonColor` × intensity × 0.9 × (1 − 0.6·edgeMask) (kept off the tube itself). **glowRadius = 0 gives exactly 0 spill** (re-verified: 0.0000 % of px, mean|Δ| 0.000000); glowRadius keeps its role, in real pixels. **The §12.2F "soft inverse-square" claim is dropped.** A single ring has one radius, so there is no 1/(d²+r0²) profile; I found no way to keep a soft radial profile in 4 axis taps without noise (rotating/jittering the ring per pixel gives a checkerboard; filtered or extra taps are the cost I just removed). Header `Ideas:` line, the in-file Idea 1 comment and this table now say "ring-gather spill glow (native)"; the JSON description never named the row (its text is only "Light spills onto the wall; bands travel along the tube.") and is unchanged. `neon-edge-glow` therefore has no §12.2 row; the soft-inverse-square row is free again for the coordinator's de-dup table (COMMON.md budget line).
Build history worth knowing: the first gather used `textureSampleLevel` ×12 with `cos`/`sin` per tap; then integer loads in a 2×4 loop; then unrolled + vectorised 2×4 (the shipped-in-draft version, 1.34–1.41× idle per the coordinator); now 1×4. A half-texel bug was found by the glowRadius = 0 test: HEAD's `luma` is a bilinear sample at the texel corner (uv = gid/dims), the taps are at texel centres, so the reference is `lumaC`, loaded the same way as the taps. Mean spill level was kept close to the 8-tap version: signed RGB lift (spill on − off) 4-tap vs 8-tap = +0.00114 vs +0.00097 (scene 192), +0.00160 vs +0.00164 (scene 576), so no re-scaling constant was needed.

**Idea 2 — striations.** Tangent = perp(gradient of the existing 4 taps), sign-fixed, **snapped to 8 directions without trig** (`round(2·t)`), phase measured from a tile-local origin (tile = 3 bands, 14 px/band at 1080p), speed 1.4 bands/s, amplitude 0.45·(0.6+0.4·flicker) faded by `smoothstep(0.02,0.08,edgeMag)`; modulates the whole tube emission. The first version (`dot(pixelPos, tangent)`, raw tangent) looked like speckle on the curved sphere edge in the 3× crop — jitter in the tangent × distance from the origin; the snap + local origin turned it into a regular dashed pattern (`n2_sphere.png`). Axis-aligned tubes are continuous across tile edges; diagonal ones can jump up to half a band at a tile boundary.

**Visibility (default sliders, idle; % px >0.02 / mean|Δ|):**

| source · size · t | Idea 1 | Idea 2 | Rescue 1 | total vs HEAD |
|---|---|---|---|---|
| scene · 192 · 1.5 | 4.81 % / .0029 (8-tap: 3.92 % / .0024) | 3.43 % / .0019 | 0.00 % | 6.76 % / .0038 |
| scene · 192 · 4.0 | 5.06 % / .0033 (8-tap: 4.29 % / .0027) | 3.47 % / .0019 | 0.00 % | 6.19 % / .0037 (8-tap build) |
| scene · 576 · 1.5 | 6.22 % / .0040 (8-tap: 6.61 % / .0041) | 1.55 % / .0009 | 0.00 % | 6.67 % / .0043 |
| synthetic discs · 192 · 1.5 | 1.09 % / .0007 (8-tap: 0.81 % / .0006) | 0.80 % / .0012 | 0.00 % | 1.21 % / .0016 (8-tap build) |

These are edge-local ideas: in the scene only 8.8 % of the frame has edgeMag > 0.04; Idea 2 lands > 0.02 on ~14 % of those edge px (mean |Δ| there 0.008). The striation is a ± modulation of an emission line that ACES already compresses, so it is **subtle by nature**; the pool (Idea 1) is the clearly visible one (`fin_neon_cmp.png`: coloured pools round the red bars and above the ridge line). Held cursor 5.9 %, audio 5.9 %, 60-frame run 7.5 % (no history is read, so no drift).

**4-axis bias and profile shape of the single ring** (synthetic bars at 576 px, colour-neutral spill so the hue clock does not confound; scripts `bias.py`, `bias3.py`, crops `bias_crop_w4.png`, `bias_crop_w24.png`, `bias_w4.png`, `bias_w24.png` in the scratchpad):
- **There is a bias, and it is the opposite sign to what one would expect:** diagonal edges get *more* integrated spill than axis-aligned ones, over a *shorter* reach. A step edge on an axis is reached by 1 of 4 taps out to d = r (strength 0.25); a 45° edge by 2 of 4 taps out to d = 0.71·r (strength 0.5). Integrated spill per unit length, 4-tap: axis 409 (horizontal) / 410 (vertical) vs 45° 573 vs 22.5° 521 (24-px bars) → **45° ≈ 1.4× axis**, 22.5° ≈ 1.27×; 4-px bars 270 / 220 vs 382 / 358 (≈ 1.4×). The 8-tap version was within ±10 % across angles (448/449/477/491), so the trim cost angular uniformity. Horizontal and vertical are equal within rounding on the wide bar (the first, colour-confounded measure had shown a 10× H/V difference, which was `neonColor`'s position hue, not geometry).
- **Visible?** In the 5× crops the diagonal pool is a brighter, narrower band than the axis one on the same bar; it reads as a slightly "hotter" diagonal, at lift amplitudes ≈ 0.01–0.05 linear. It is not a checkerboard and not a dropout; I judge it minor but I would not call it invisible.
- **Profile shape:** a box, not a soft pool. On a wide edge it is a uniform tinted band with a hard outer edge (≈ 8 px at 576, 0.6·R + 1); on a thin (4-px) line the ring misses the line and gives **two detached parallel stripes** with a gap beside the tube (the 8-tap version had the same ghost stripes, two of them, a little softer). Natural photo edges are mostly step-like, so this is mostly the wide-edge case, but thin bright lines will show the stripes.
- Possible follow-up if the owner wants it softer: a second, outer 4-tap ring *only where the inner ring already fires* (branch cost is data-dependent, so not free on SwiftShader), or rotating the ring 22.5° (does not remove the bias).

**Default-look change:** scene meanL 0.498 → 0.499 (192), 0.492 → 0.494 (576); nan 0. All four sliders live (min→max, % px > 0.02): edgeStrength 49.1 %, glowRadius 16.7 %, neonTint 67.1 %, intensity 65.9 %.

**Cost (final, 4-tap):** min-of-drained-frames, interleaved HEAD/new, 256 px, saved defaults, load avg 1–3 (idle). Run A, 6 rounds, three-way: HEAD 7.4 ms, **new 9.0 ms = 1.22×**, 8-tap draft 9.9 ms = 1.34× (matches the coordinator's 1.35–1.41×). Run B, 8 rounds, HEAD vs new: HEAD 6.2 ms, **new 7.5 ms = 1.21×**; per-round ratios 1.26 1.01 1.05 1.17 1.21 1.24 1.62 0.90 (median 1.19). Both are under the 1.25× target, but per-round spread is ±0.3 on this machine, so treat 1.2× as ±0.05. Coordinator's bisect of the 8-tap file: spill removed = 1.03×, striations removed = 1.32× (striations are free), inner-ring-only = 1.21× — the 8-tap gather carried all the cost. The earlier "1.14–1.16×" and "1.9–3.1×" figures in older drafts of these notes were load-contaminated or pre-trim; ignore them.

**Gates (re-run on the 4-tap file):** precommit PASS (naga OK, bindgroup compatible), `verify-naga-wasm --files` PASS (1 valid, 0 invalid), `audit:dead-sliders -- --files neon-edge-glow` 0 new, `audit:extrabuffer` 0 new (2 known baseline). The audit scripts rewrote `reports/*` again; coordinator discards.

**Open / not done:**
- Rescue 1's benefit on real hardware is unverified (see above).
- Spill is a hard-edged box band (see above); with a large `glowRadius` the ring is far from the edge it came from and thin lines show detached stripes. Not inspected at glowRadius 1.5 on the photo. 45° edges get ~1.4× the integrated spill of axis edges.
- Striations on strongly curved or very short edges are band-segmented (tile-local phase); they are a texture on the tube, not an arc-length coordinate.
- `neon-edge-glow` reads the mouse (tube hue bend) but the JSON has no `mouse-driven` tag — pre-existing, left alone (not this pass's claim).
