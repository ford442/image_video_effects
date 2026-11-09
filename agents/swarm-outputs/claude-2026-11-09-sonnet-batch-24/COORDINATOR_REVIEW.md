# COORDINATOR_REVIEW — sonnet/batch-24 (spectral colour fields, fabric textures, cyber ripples; 10 shaders)

Base: origin/main c37e2fb0. Commit 1 = prelude migration (9 files, header-only, no `Upgraded:` bump; `fabric-zipper` needed `comparisonSampler` → `comparison_sampler` by hand). Commit 2 = ideas/rescues/JSON/lists/ledger/notes. Cards: BRIEFS-fork{A,B,C,D}.md (written before any WGSL edit). Per-shader claims: NOTES-fork{A,B,C,D}.md. All evidence is SwiftShader (f32 unless stated) with a synthetic photo; **no real-GPU visual QA was done.**

## Formula-row de-dup (§12.4: a §12.2 row on at most two files)
| §12.2 row | Files | Count |
|---|---|---|
| Structure-tensor orientation (A) | fabric-step-gabor (Cauchy–Green of the cloth), spectral-bleed-confine (Di Zenzo colour tensor) | 2 ✓ |
| Fresnel–Schlick / HG / Beer–Lambert (F) | fabric-zipper (Fresnel rim on teeth), digital-haze (chromatic Beer–Lambert + HG glare) | 2 ✓ |
| Energy-conserving bloom (F) | spectral-bleed-confine (rim halo paid by bled colour), vaporwave-horizon-prismatic (phosphor bloom) | 2 ✓ |
| Cauchy dispersion (F) | chroma-kinetic | 1 ✓ |
| Isotropic 9-point Laplacian (D) | fabric-step-gabor | 1 ✓ |
| Deep-water dispersion (D) | cyber-ripples-coupled | 1 ✓ |
| Schmitt-trigger lock + Dropout bursts (B) | data-stream-spectral | 1 file ✓ |
| none (tactic-derived only) | magnetic-chroma, audio-voronoi-gabor | – |

No two files share both formulae; no spring+ripple+IQ-palette overlay was stamped anywhere.

## Per file
| File | Pass | Ideas in diff (all findable at a `// … Idea n` comment) | Rescues | Default look vs HEAD (192 px, idle) |
|---|---|---|---|---|
| fabric-zipper (2nd) | ✅ | interlocking half-pitch tooth chain; lit brass/steel hardware (Fresnel–Schlick); twin lockstitch rows; tape bunching at the slider | – (HEAD healthy); `6.28` vs 2π scallop drift fixed | meanL .225→.227 (idle); visibly richer at ≥384 px |
| fabric-step-gabor (1st) | ✅ | principal-strain orientation (§12.2A) rotates the Gabor bank; plain-weave thread lattice the bank can detect; compression buckling shade (det J) | cloth was per-pixel oscillators that tore permanently → coupled displacement field (tether + 9-pt Laplacian §12.2D), healing tears, offsets stored (f16-safe), texel-centre loads, ~2.3–3.6× faster | **large**: full-frame psychedelic wash → calm cloth + lattice, Gabor colour where the sheet is strained (cursor) |
| spectral-bleed-confine (1st) | ✅ | Di Zenzo tensor stretches each channel's tap lattice along the edge tangent (§12.2A); reflection halo scaled by rejected kernel mass (§12.2F) | `bleedRate` was `zoom_config.x` = TIME (overshoot, posterised by t=30 s); confinement was a no-op (cancelled in sum/weight); filtering-sampler history; hard alpha | **large**: ACES floor desaturates (mean sat .32→.20 vs HEAD-with-bleed-fixed); see Open items |
| chroma-kinetic (1st) | ✅ | motion-aligned lead/lag from the sprung centre's real velocity; 5-tap Cauchy spectral fringe (§12.2F) | dead extraBuffer spring → A-texel spring; dead per-sector FFT removed | **none** at idle (.291/.130/.284 identical) |
| magnetic-chroma (2nd) | ✅ | Lorentz gyration (R/B streamlines rotated ±θ, Chromatic = 0 reduces to HEAD); iron-filing needles oriented by the same `magnetic_field()` | – | small: 5.5 % px >8/255, stats identical |
| cyber-ripples-coupled (2nd) | ✅ | refractive density lens (click-only); dispersive deep-water ring train (§12.2D) | dead spring → A-texel pointer spring (cursor now stirs the fluid); stored "vorticity" is a true curl; vorticity confinement CUT (amplified grid speckle, see BRIEFS-forkC amendment) | **none** at idle cursor (bit-identical) |
| digital-haze (1st) | ✅ | re-fogging wipe memory in C.r; chromatic Beer–Lambert (§12.2F); HG forward-scatter glare (§12.2F) | haze was invisible (`STEP_SIZE` 0.03 = whole ray, τ≈0.045: every slider visually dead) → `HAZE_PATH` 0.55; dead spring → A-texel spring; dead per-cell FFT → live treble | **large**: .507/.172/.119 → .611/.153/.458; all four sliders now move the picture |
| data-stream-spectral (1st) | ✅ | Schmitt-trigger stall lock per strip (latch in A.a ← exact C.a); dropout bursts with leading edge + exp tail | dead spring removed (bit-identical to what HEAD really did); dead FFT bins → plasmaBuffer[0] tilt (brightness/alpha only after review fix) | small: .307→.280 meanL (≈20 % of strips locked at silence) |
| vaporwave-horizon-prismatic (1st) | ✅ | perspective-filtered neon grid (analytic footprint); sun reflection with glitter rows/path on the mirror floor; energy-conserving phosphor bloom (§12.2F) | held scroll-phase teleport (`time*gridSpeed*heldBoost`) → integrated phase in A texels; idle phase equals HEAD exactly | moderate: .489→.536 (horizon speckle gone, sun reflection) |
| audio-voronoi-gabor (1st) | ✅ | grain-lit cell membranes (F2−F1 wall embossed along the Gabor orientation); rigid cell translation (orientation at the cell's own seed) | strobing fake audio (always-on `sin` beat + `extraBuffer` as audio) → plasmaBuffer[0] + quiet breathing floor; 4×81 → 1×81 shared taps (≈5e-6 vs HEAD); ACES; stable per-cell hash; bounded Gabor shift | **large**: stable faceted mosaic at silence (HEAD swung .425↔.354) |

## Independent review (two fresh read-only agents; findings verified before acting)
Fixed by the coordinator after review (re-gated, re-rendered, spot-verified numerically):
1. fabric-zipper stitch phase was slider-relative (`dy`) → stitches crawled against teeth/twill when dragging; now `uv.y`-anchored (best-fit roll 0 px after fix, was 5 px).
2. fabric-step-gabor had no state sentinel: inherited C (previous shader's display RGBA) was read as displacement → ~3 s wobble on switch. Sentinel `(0,0,0.7371,0.7371)` now lives in the pinned top rows' unused `.zw`; seeded-C run is bit-identical to a clean start.
3. chroma-kinetic motion term had a constant 0.03 base → fringe + saturating alpha at Distortion Str 0. Now `0.16·Str` (identical to the old `0.03+0.1·Str` at the 0.5 default); Str 0 matches HEAD exactly.
4. spectral-bleed-confine `atan2(0,0)` on exactly flat input → `+1e-6`.
5. fabric-step-gabor bank rotation was not π-periodic (jump at the atan2 wrap) → `sin(2θ)·c·s` (same slope at small angles).
6. data-stream-spectral: audio inside the time-multiplied scroll phase teleported strips by `time·Δ` (HEAD for bass; the live-FFT rescue widened it) → audio removed from phase (kept on brightness/alpha/lock/dropout/packet glow); mids change at T=60 s now moves the strips by exactly 0; audio-0 look bit-identical.
7. cyber-ripples-coupled (and chroma-kinetic): spring stored in rgba16float stalls ~2e-3 short with a ~0.01 residual velocity that never decays (numpy f16 reproduction: |vel| .009/.014/.017 at 60/120/144 fps → exactly 0 with a rest-snap at |err|<0.004 & |vel|<0.06). Snap added to both.
8. cyber-ripples-coupled JSON lacked `upgraded-rgba` (ACES + card present) → added.
9. audio-voronoi-gabor seed-shift cap was a hard `min` (slider dead above Gabor Influence ≈ 0.28 for geometry) → soft `0.35·tanh(x/0.35)` (slope 0.3 at 0, same saturation).

Rejected / accepted as documented:
- "Tear Threshold dead range" (fabric-step-gabor): measured with a cursor pushing the cloth, 0 vs 0.5 differs on 28.6 % of pixels and 0.5 vs 1 on 8.4 % — the slider is live under interaction. At an idle cursor the sheet never stretches past the threshold, which is inherent to a *threshold*. The proposed `mix(1.1, 2.2)` remap changed 98.5 % of pixels at the low end — rejected.
- digital-haze slider lag (re-fog front ≈0.08 uv/s): intended by Idea 1; a Clear Radius drop takes ~4 s to show fully.
- data-stream latch is per pixel, not per strip: changing Density mid-run can show a half-locked strip until its drive leaves the 0.52–0.74 hysteresis band; self-heals.
- Shared sentinel 0.7371 across digital-haze / cyber-ripples-coupled / vaporwave: switching straight from one to another without a clear adopts the other's (0,0) state for ~1 s; self-heals (HEAD had the same inheritance for fluid/fog state).
- Residual tape-bunching tail in fabric-zipper (Gaussian e-fold ≈0.17 canvas heights; ~12 % at 0.25 below the slider) moves with the slider by design; comment corrected.
- fabric-step-gabor focal patch is pixel-scale palette confetti (HEAD's bank uses only the even Gabor phase; an even+odd pair would fix it properly); pinned top edge shows a band of elevated strain.

## Gates
`wgsl_precommit_gate.py` 10/10 (naga + bind-group + 0 extraBuffer violations + 0 pasted headers); `audit:extrabuffer` PASS; `audit:dead-sliders` 0 new; saved JSON `params` byte-identical in all 10 (only features/description/feedbackPacking/x-meta differ); NaN 0 across 192/576 px idle+held+audio grids and the reviewers' 120-case sweeps. Vitest / build / verify:toolchain-foundation: see the closeout message.

## Open items (need a real GPU and/or a maintainer decision)
- **spectral-bleed-confine ACES saturation:** the catalog ACES floor lifts mids and desaturates the pastel flat regions (mean sat .292 no-ACES → .197). Kept for consistency with the batch/catalog; the one-line alternative is `let display = clamp(result, vec3(0.0), vec3(1.0))` (ablation: scratchpad forkB/hd/sbc_noaces.wgsl).
- **fabric-step-gabor default look** is now calm cloth, not a full-frame wash; if more psychedelia at rest is wanted, raise `STRAIN_GAIN` (2.0) — a taste call, not a bug.
- **digital-haze default look** is a visible veil now (`HAZE_PATH` 0.55); drop to ≈0.25 for gentler.
- rgba16float A-state schemes (vaporwave phase, chroma-kinetic/cyber/haze springs, fabric-step offsets) are verified by emulation only, not on a real half-float tier.
- Thumbnails for all 10 are stale (ledger marks them); refresh on a GPU machine.
- audio-voronoi-gabor: on real photos the seed-shift soft cap may still bind often — tune `SEED_SHIFT_CAP`/`STRENGTH_CAP` by eye.
- vaporwave-horizon-prismatic: the fog law is transmittance-shaped (foggy near, clear at the horizon) — HEAD identity, kept; maintainers may want it flipped.
