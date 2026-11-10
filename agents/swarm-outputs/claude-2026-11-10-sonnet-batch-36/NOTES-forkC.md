# NOTES — fork C (blueprint-reveal-guided, data-scanner-gabor)

HEAD = 75dbf877. Harness: SwiftShader via a scratch copy of `agents/mr.mjs` (GPU-synced `frameMs`, `DEPTHFLAT`, `SRCRAW`/`DEPTHRAW`). Test sources: `public/fixtures/thumbnail-scene.png` (+ a hand-built depth: sky far, mountains/land/water bands, spheres near) for blueprint; the Rock031 1K colour texture for the scanner (the procedural `SRC=img` is too smooth to exercise either edge or Gabor ideas). Default sliders (all 0.5), held cursor (0.4,0.6,1). "% > 0.02" = pixels whose max-channel |Δ| exceeds 0.02. Real-GPU look is unverified.

## 1. blueprint-reveal-guided

**KEEP VERBATIM held:** 4 params and roles (Edge Strength = line gain, Grid Opacity, Radius, Softness); depth-guided filter code (7×7, ε 0.001, a·G+b) unchanged; Sobel kernel (0.333 luma weights) unchanged; sin grid; reveal mask; alpha formula (confidence), now clamped to [0,1]; A = (filteredColor, confidence), display-space, nothing reads C; depth passthrough; background lands on HEAD's navy (0.05, 0.105, 0.40) (bare-background pixel renders 0.050 / 0.1048 / 0.4011); grid line colour (0.200, 0.255, 0.551) = HEAD's.

**A packing:** unchanged. ACES covers the blueprint background + hatch only. The grid and the pen lines are added AFTER the tone-map (fix round: ACES had lifted the grid to (0.31, 0.36, 0.56) and capped line peaks), lines blend to white (peak 1.0). The revealed photo stays LDR (guided result clamped ≥ 0) — ACES on the LDR photo would re-grade it.

| Idea | Where | Measured at defaults (cursor away, all blueprint) |
|---|---|---|
| 1 Pen hairlines: gradient-oriented non-max suppression + depth-step outline weight (native) | `sobelGrad`, `// ── Idea 1` | lines are 1–2 px ridges (HEAD: 3 px smear), heavier at depth steps; see the line table |
| 2 Tone hatching, dark = dense: 45° → cross → interleaved third set, from guided luma (native) | `// ── Idea 2` | vs a `HATCH_GAIN=0` copy, frame % with max-ch \|Δ\| > 0.02: scene 63.5 (192) / 69.0 (576), rock 47.5 / 51.9, synthetic 51.0 / 60.8 |

**Fix round (reviewer):**
- *Lines*: peaks reach 1.0 after ACES (p99 = 1.00; synthetic 576 0.96). Line pixel = \|full − lines-off\| > 0.15; share of line pixels with mean(rgb) > 0.7, HEAD → new (192 / 576): scene 44.7 → 48.2 / 37.9 → 43.1; rock 55.4 → 91.3 / 59.6 → 90.7; synthetic 16.5 → 45.4 / 3.8 → 2.0 (smooth image, weak gradients at 576 in both). Line pixels as % of frame (thinner by design): scene 39.8 → 26.2 / 20.8 → 10.2; rock 94.0 → 56.2 / 94.7 → 52.4. These do not reproduce the reviewer's 52–72 % HEAD figure (different line-pixel definition / frame); HEAD and new share one definition here.
- *meanL* (mean rgb, clamped, cursor away), HEAD → new (192 / 576): scene 0.433 → 0.463 / 0.330 → 0.404; rock 0.695 → 0.689 / 0.721 → 0.651; synthetic 0.500 → 0.531 / 0.316 → 0.419.
- *Hatch is dark = dense* (flat grey source, 384², coverage % of frame > 0.02): tone 0.95 → 0, 0.80 → 0, 0.65 → 32 (one 45° set), 0.50 → 58 (cross), 0.35 → 62, 0.20 → 90, 0.05 → 94 (three sets). Levels switch at tone ≈ 0.76 / 0.52 / 0.26. The test photos are dark (scene meanL 0.33, rock 0.18), so they hatch heavily; mid-tones hatch with 2 directions.
- *Alpha* clamped to [0,1]: range 0.85–1.0 with the cursor in the reveal and at slider extremes (0,0,0,0) / (1,1,1,1); nan 0.
- *Features line* now lists `upgraded-rgba`.
- *Depth-step outline* strengthened cheaply (±3 px probe, thresholds 0.008–0.06, weight 0.8). Fraction of frame with outline > 0.5, old → new probe: scene 3.7 → 5.5 % (576), 10.9 → 16.4 % (192); synthetic 2.2 → 4.3 % / 6.5 → 17.0 %. Honest limit: it still marks depth discontinuities only — gentle depth ramps stay weak, and depth from a flat or absent map gives no outline at all. (Definition differs from the reviewer's 0.9 %-of-frame figure; not directly comparable.)

**Remaining deviations from the card:**
- Hatch is blank above tone ≈ 0.8 (bright regions read as clean paper) — the card says dark = dense, not that every tone hatches.
- Level 3 is an interleaved second 45° set (half-period offset), not a new angle; at tone ≤ 0.2 coverage is 90 %+, so the darkest regions read as a lighter-blue tint with dashes rather than separate strokes.
- Hatch amplitude is deliberately low (+0.14…0.24 of the cyan ink before ACES) so lines/grid dominate; as a consequence dark photo regions render lighter blue than bright ones (ink density on navy paper).
- Hatch tone comes from the guided (smoothed) luma, not the raw photo.

**Rescues**
- R1 (Sobel on raw image vs header claim): header corrected (note added); depth step weights/loosens the ridge so outlines read heavier. The Sobel itself still reads the raw image — "lines follow true object contours" is only partly true.
- R2 (flat depth ⇒ box blur): **disclosed, no change.** The revealed image is HEAD's behaviour: an 80 % blend to a 7×7 guided mean (a·G+b, ε 0.001) that keeps roughly 23 % of the source's high-frequency energy (reviewer's measure). Our own check: Laplacian sharpness kept 0.24 with real depth, 0.19 with flat depth; with flat/absent depth the guided filter degenerates to a plain 7×7 box mean — by design, not guarded. Stated in the header too. No NaN either way.
- R3 ACES placement (see above). R4 pixel-centre uv: every tap lands on texel centres (HEAD read corners = a 2×2 bilinear box before each tap, so HEAD's edges were pre-blurred).

**Default-look change:** see meanL above; raw HEAD meanL/stdL 0.597/1.041 (192) are inflated by unbounded HDR line values. Idle = held (the pointer-down flag is not used). meanA 0.893 vs 0.894 (192), 0.888 vs 0.889 (576).
**frameMs HEAD → new (loaded VM, min of 2; noisy, other forks were rendering):** 192: 67 → 79 (1.18×); 576: 539 → 229 (individual runs 600 → 749 = 1.25×). Extra work vs HEAD: two more Sobel evaluations (NMS probes) and 4 depth taps.
**Gates (fix round):** precommit ✓, verify-naga-wasm --files ✓, dead-sliders 0, extrabuffer 0 (2 known baseline), no `_tmp*` files in `public/shaders/`. nan 0 at 192 with cursor in/out and slider extremes.
**Open:** real-GPU look unverified; the hatch period is a fixed 8 px (does not scale with resolution — at 1080p the hatch reads finer).

## 2. data-scanner-gabor

**KEEP VERBATIM held:** 4 params and roles (Gabor Response = gain); fp128 scan phase; the four orientations (0/45/90/135° + rot) and the four cosine palettes; green grid; bar border; vertical packet; click bursts (code unchanged — the harness cannot inject ripples); held widening; outside dim 0.4; C feedback at in_scan·0.1; ACES; alpha formula; A = display RGBA.

**A packing:** unchanged (ACES display RGBA, C read as colour).

| Idea | Where | Measured |
|---|---|---|
| 1 Gabor energy from the quadrature pair, DC-free even kernel, ONE shared tap loop (native) | `gaborBank`, `// ── Idea 1` | vs HEAD analysis, in-bar pixels > 0.02: 99.95 % (mean \|Δ\| 0.54 scene / 0.31 rock at 576). HEAD analysis was rainbow confetti (hue from the signed even response, brightness divided out); new = orientation hue, brightness = energy, photo faintly underneath, grid now visible |
| 2 Orientation needles from the four energies (native) | `// ── Idea 2` | vs NEEDLE_GAIN=0 at 576: rock 6.9 % of the bar (2.8 % of frame) > 0.02, scene 2.8 % of the bar (1.1 % of frame; the scene is mostly flat so needles exist only on edges); at 192: 13–21 % of the bar |

**Deviations / additions beyond the card (all inside idea 1):** HEAD's four palette offsets coincide at a fixed index (0° and 135° are both cyan), so each orientation gets its own index offset (cyan / orange / violet / lime); the `/ (Σ|r| + 0.001) · 1.3` normalisation (which discarded response magnitude) became `· 1.3 / (1 + 0.6ΣE)` plus an 18 % photo underlay. The look inside the bar changes from uniform pastel to dark-with-structure.

**Rescues**
- R1 seam: real but small. In a dark band at 576, with HEAD's dim ordering the two columns after the border measured 0.14 / 0.08 vs 0.09 / 0.06 with the continuous dim; border peak 0.41 vs 0.30. Fixed with `mix(0.4, 1.0, in_scan)`.
- R2 `plasmaBuffer[band+1]` OOB: replaced by per-band bass/mids/treble. Magnitude ≤ 0.014, so not visible — no visibility claim.
- R3 pixel-centre uv (taps are exact `textureLoad`). R4 cost: **fewer** taps — 169 luma fetches per bar pixel instead of 676.

**Default-look change (rock, 192/576):** held meanL/stdL 0.303/0.276 → 0.239/0.206 (192), 0.305/0.276 → 0.244/0.210 (576); idle (no button) 0.244/0.258 → 0.195/0.190 (192). meanA unchanged.
**frameMs HEAD → new (loaded VM, min of 2):** 192: 96 → 51; 576: 799 → 364 (≈0.5×).
**Gates:** precommit ✓, verify-naga-wasm --files ✓, dead-sliders 0, extrabuffer 0. Sliders 0→1: Frequency 40 %, Sigma 40 %, Gabor Response 41 %, Scan Width 56 % of pixels > 0.02. nan 0 at 192/576, audio 0.8/0.5/0.9, A16=1, 60 frames (stats identical to 20), and slider extremes (0,0,1,0) / (1,1,1,1).
**JSON:** both gain `upgraded-rgba` (ACES + cards implemented); scanner gains `audio-reactive` (bass/mids drive the scan wobble and speed, treble the border) and a real description (100 chars, was a 37-char stub); blueprint's false "lines respect true boundaries via guided Sobel" description replaced (188 chars, was 205); both get `x-meta.upgrade.params` aligned to the saved params. `params` byte-exact.
**Open:** needles on a high-frequency texture (rock) are dense and only loosely aligned per pixel (orientation is read per pixel, not per cell); on a real GPU, check needle weight at 1080p (cell 27 px).
**§12.2 rows:** none used from the table; both ideas are native (kernel deepening; promote an intermediate; direction).
