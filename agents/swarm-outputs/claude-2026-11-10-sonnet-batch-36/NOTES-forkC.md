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

**KEEP VERBATIM held:** 4 params and roles (Gabor Response = gain); fp128 scan phase; the four orientations (0/45/90/135° + rot) and the four cosine palettes; green grid; bar border; vertical packet; click bursts (code unchanged — the harness cannot inject ripples); held widening; outside dim 0.4; C feedback at in_scan·0.1; ACES; alpha formula; A = display RGBA. Weighting is HEAD's again: energy-weighted palette average divided by the energy sum, ×1.3 (fix round).

**A packing:** unchanged (ACES display RGBA, C read as colour). **Disclosed, not changed:** `prev.rgb*0.88` is post-ACES display colour fed back before the next ACES (ACES → C → ACES). HEAD does the same and the card says unchanged; noted in the header too.

| Idea | Where | Measured (default sliders, held cursor 0.4/0.6) |
|---|---|---|
| 1 Gabor energy from the quadrature pair, DC-free even kernel, ONE shared tap loop (native) | `gaborBank`, `// ── Idea 1` | phase-invariant energy; HEAD's rainbow confetti (hue from the signed even response) is gone; orientation = hue |
| 2 Orientation needles from the four energies (native) | `// ── Idea 2` | vs NEEDLE_GAIN=0 (frame % with max-ch \|Δ\| > 0.02, in-bar % in brackets): 576 scene 3.08 (7.7), rock 5.32 (13.0); 192 scene 9.1 (22.3), rock 11.3 (27.5); flat source 0 (no energy, no needle) |

**Fix round (reviewer): the default look inverted over smooth content.** Causes confirmed: the `color*0.18` floor and energy-weighted blend without HEAD's normalisation (brightness followed energy, so smooth content went dark).
- Bar = `Σ palette·E · 1.3 / (ΣE + ENERGY_KNEE) + photo·PHOTO_FLOOR + SCAN_WASH·KNEE/(ΣE + KNEE)`; KNEE 0.1, floor 0.6 (reviewer's value), wash (0.07, 0.15, 0.20). The knee keeps hue from blowing up where E ≈ 0 (HEAD's even-only response leaked flat areas into a full-strength random hue); the wash is a faint cyan base on no-energy pixels so smooth content reads as an active band (trial without the wash and with knee 0.3: flat bar 0.544, scene@576 0.407; with knee 0.1 + wash: 0.626 / 0.560).
- bar meanY / outside meanY (Rec.709 Y, clamped; bar = \|x−0.4\| < 0.18, outside = \|x−0.4\| > 0.23), HEAD → new (192 / 576):
  - flat 0.6: bar 0.698 → 0.626 / 0.698 → 0.626; outside 0.360 = 0.360
  - scene: bar 0.670 → 0.628 / 0.671 → 0.560; outside 0.181 / 0.180
  - rock: bar 0.641 → 0.709 / 0.637 → 0.699; outside 0.081 / 0.083
  - The bar is now brighter than its dimmed surround everywhere (before: flat 0.245 vs 0.36). Scene at 576 stays 0.11 under HEAD: HEAD's 0.67 on smooth content was the leak; we keep photo + wash instead. Rock is 0.06 over HEAD.
- Look on the rock texture is now HEAD-like pastel (four palettes averaged); the "dark with structure" look of the first pass is gone — that was the inversion.

**Fix round: needles on smooth content.** Gates relaxed `smoothstep(0.18,0.45,coh)·smoothstep(0.08,0.30,ΣE)` → `(0.08,0.25)·(0.02,0.10)`; tick `halfW max(0.8, 0.09·cell)` → `max(1.0, 0.11·cell)`, length 0.46 → 0.48·cell with coherence floor 0.45 → 0.5. Scene at 576: 0.76 % → 3.08 % of the frame (2.6 → 7.7 % of the bar); rock 2.6 → 5.3 %. At 192 the grid of ticks is dense (9–11 % of the frame; cell = 4.8 px) but regular. Flat areas still get no needle on purpose: with E = 0 there is no orientation to show. **Fix round: `atan2(V.y, V.x + 1e-6)`** — defined at E = 0 (flat source nan 0).

**Deviations / additions beyond the card (all inside idea 1):** HEAD's four palette offsets coincide at a fixed index (0° and 135° are both cyan), so each orientation gets its own index offset (cyan / orange / violet / lime); the energy knee and the cyan wash above.

**Rescues**
- R1 seam: real but small. In a dark band at 576, with HEAD's dim ordering the two columns after the border measured 0.14 / 0.08 vs 0.09 / 0.06 with the continuous dim; border peak 0.41 vs 0.30. Fixed with `mix(0.4, 1.0, in_scan)`.
- R2 `plasmaBuffer[band+1]` OOB: replaced by per-band bass/mids/treble. Magnitude ≤ 0.014, so not visible — no visibility claim.
- R3 pixel-centre uv (taps are exact `textureLoad`). R4 cost: **fewer** taps — 169 luma fetches per bar pixel instead of 676.

**frameMs HEAD → new (loaded VM, min of 2, rock):** 192: 126 → 48; 576: 901 → 456 (≈0.4–0.5×).
**Gates (fix round):** precommit ✓, dead-sliders 0, extrabuffer 0 new; naga validates the shader (`1 valid, 0 invalid`) but `verify-naga-wasm --files` exits 1 on `src/contracts/wgsl_validation.json` (knownFailures.ratchet 5 vs 4 ids; file touched 05:09 by someone else, not by fork C — not edited). Sliders 0→1 (192, rock/scene): Frequency 39 / 40 %, Sigma 38 / 38 %, Gabor Response 38 / 38 %, Scan Width 56 / 56 % of pixels > 0.02. nan 0: slider extremes (0,0,1,0) / (1,1,1,1) / (0,1,0,1) with audio 0.8/0.5/0.9, flat source (E = 0), A16=1.
**JSON:** both gain `upgraded-rgba` (ACES + cards implemented); scanner gains `audio-reactive` (bass/mids drive the scan wobble and speed, treble the border) and a real description (100 chars, was a 37-char stub); blueprint's false "lines respect true boundaries via guided Sobel" description replaced (188 chars, was 205); both get `x-meta.upgrade.params` aligned to the saved params. `params` byte-exact. No JSON change in the fix round.
**Open:** needles on a high-frequency texture (rock) are dense and only loosely aligned per pixel (orientation is read per pixel, not per cell); on a real GPU, check needle weight at 1080p (cell 27 px). Real-GPU look unverified.
**§12.2 rows:** none used from the table; both ideas are native (kernel deepening; promote an intermediate; direction).
