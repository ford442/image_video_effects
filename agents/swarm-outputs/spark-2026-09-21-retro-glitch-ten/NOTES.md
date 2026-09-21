# Retro-Glitch Ten — Implementation Notes

**Agent:** spark · **Date:** 2026-09-21 · Cards: [`BRIEFS.md`](BRIEFS.md)

Per shader: what was kept verbatim, where each numbered idea lives in the diff, and the A packing.
Grep the `── Idea N:` banners in each WGSL to land on them.

---

### `crt-phosphor-decay` (+67 / −16)
- **Kept:** all four param roles; `max(fresh, decayed)` persistence rule; per-channel ratios G ×0.97 /
  B ×0.94; `halation()` 5-tap; scanline term; spring block; click-bloom loop; ACES; depth passthrough.
- **Idea 1 — two-rate phosphor knee:** `hot`/`fastRate`/`tailRate`/`rate`, replacing the single
  `decayBase` multiply. Excitation read from history luma, so no new channel is claimed.
  `tailRate` is capped at 0.994 so the tail can never run away.
- **Idea 2 — triad-aligned grain bleed:** `prevL`/`prevR`/`bled`/`persist`. Bleeds the *decayed*
  history only, and `max()` makes it a one-way spill from bright grains into dark neighbours.
- **Idea 3 — interlaced field parity:** `fieldParity`/`onField`/`refresh`, applied as
  `max(boosted * refresh, persist)`. Gated by the scanline slider — at 0 the frame is progressive
  exactly as before.
- **Fixed en route (stated, not silent):** HEAD's triad mask was `fract(uv.x * resX)`, which is
  identically 0.5 for every texel, so the "subpixel mask" was a flat magenta tint. Now `triadMask()`
  phases off `coord.x / 3.0`, which is what an aperture grille is. Same expression, real geometry.
- **A packing:** ACES display RGBA. Unchanged.

### `crt-magnet` (+38 / −3)
- **Kept:** param roles; `barrel()`; `field = magnetStrength · falloff · sdfMask · depthAtten`;
  hex bloom; degauss ring; beam sweep; both palette calls; echo mix; vignette; ACES.
- **Idea 1 — tangential convergence error:** `rot2()` helper + `gunSwing`; R and B are now rotated
  ±120° by field strength, green stays the reference gun. Replaces the 1.35 / 1.00 / 0.70 ladder.
- **Idea 2 — warped shadow-mask moiré:** `maskX` / `stripe` phased off the displaced screen
  position instead of `global_id.x % 3u`. Same grille colours, now able to beat.
- **Idea 3 — purity stain + degauss erase:** `echoLuma`/`stainChroma`/`stainHold`, retention
  multiplied by `(1 - degauss)`.
- **Note:** this was the most overlay-stacked file in the batch. All three ideas *replace* flat code
  paths; no new layer was added on top.
- **A packing:** ACES display RGBA. Unchanged.

### `vhs-tracking` (+35 / −7)
- **Kept:** param mapping; per-row random walk read from C at `(0, y)`; capstan sine; YIQ pair;
  azimuth chroma blur; head band; mouse tracking pull; ripple dropout; A's raw-state packing.
- **Idea 1 — head-switch skew (flagging):** `sinceSwitch`/`flagPhase`/`skew`, added into
  `totalOffset`. Anchored to the same two band positions the head-switch noise already uses.
- **Idea 2 — dropout-compensator line repeat:** `docUV`/`docLine`/`docResidue`/`concealed`.
  The white-noise hash survives only as residue leaking past concealment.
- **Idea 3 — line-alternate chroma phase:** `lineFlip` multiplying `phaseShift`.
- **A packing:** raw sim state — (row walk, dropout mask, chroma phase, head band). Unchanged;
  `phaseShift` still stores as `·0.5 + 0.5` and its magnitude is unchanged by the sign flip.

### `signal-noise` (+41 / −6)
- **Kept:** param roles; `rgbToYuv`/`yuvToRgb`; `vhsHeadSwitch()`; `dctBlockArtifact()`; fbm smear
  vectors; chroma-split sampling; C temporal decay; ACES.
- **Idea 1 — luma-shouldered noise:** `noiseShoulder` scaling both chroma injections.
- **Idea 2 — real quantisation staircase:** `blockUV`/`blockLuma`/`levels`/`stepped`, applied to
  `yuv.x`. The ring artifact is untouched; this is the banding it was only gesturing at.
- **Idea 3 — dot crawl:** `lumaL`/`lumaR`/`vEdge`/`crawlField`/`crawl`, pushed into `yuv.y`/`yuv.z`
  in opposite directions so it reads as subcarrier crosstalk, not as a tint.
- **A packing:** ACES display RGBA. Unchanged.

### `byte-mosh` (+58 / −8)
- **Kept:** param roles; `lfsr_step`/`lfsr_advance`/`galois_mult`; good↔bad Markov probabilities;
  `pack_rgb8`/`unpack_rgb8`; block state layout in A; boundary rainbow; regional FFT edge glow.
- **Structural:** the `leftBlock` / `upBlock` C reads were hoisted above the motion-vector block.
  Same two `textureLoad`s, same coords — just earlier, so the vectors can use them. `boundary` is
  computed from them unchanged.
- **Idea 1 — motion-vector inheritance:** `leftLfsr`/`upLfsr`/`leftOffset`/`upOffset`/`inherit`/
  `movedOffset`. Neighbour vectors decoded with the same bit layout, trusted only when that
  neighbour is itself corrupt (`step(0.16, block.a)`).
- **Idea 2 — keyframe recovery flash:** `recovered`/`keyframe`, mixing back to clean source and
  adding a bloom before ACES. Rides `prevAge`, already tracked.
- **Idea 3 — row desync trail:** `rowDesync`/`trailShift` from the left neighbour's age minus one,
  so the desync advances one block per frame and fades over the 63 steps the field holds.
- **A packing:** raw block state — (lfsr, burst mask, corruption age, mode). Unchanged.

### `xerox-degrade` (+50 / −6)
- **Kept:** param roles; `sigmoidContrast()`; `bayer4x4()`; `halftoneDot()`; paper/ink colours;
  smear UV displacement; `edgeVignette()`; scatter; spring; ripple smear.
- **Idea 1 — toner starvation bands:** `drumPhase`/`starveNoise`/`starveBand`/`coverage`, lifting
  ink coverage only where the machine is trying to lay ink down.
- **Idea 2 — Mach-band edge halo:** `haloStep`/`blurLuma`/`machAmt`/`mach`, fed into the existing
  sigmoid input so the threshold bites on the fringe. Scales with the Contrast slider.
- **Idea 3 — compounding generation loss:** `prevLuma`/`regen`/`generation`. The C history is
  re-thresholded through the same sigmoid before blending, at the same blend weights as HEAD.
- **A packing:** ACES display RGBA (C read as the previous generation). Unchanged.

### `ascii-flow` (+49 / −8)
- **Kept:** param roles; all eight `draw_glyph()` shapes and their indices; `grid_dims`; flow +
  repel + held-vortex field; `scanGlyph`; the cosine tint and its mix weight; click fronts; C smear.
- **Idea 1 — ink-coverage ramp:** `ramp_glyph()` with order `(0,4,5,1,2,6,3,7)` — dot < slash <
  backslash < bar < dash < X < plus < box. Same shapes, monotonic ramp.
- **Idea 2 — coverage-weighted glyph blend:** `ramp_pos`/`step_idx`/`sub`/`glyph_lo`/`glyph_hi`,
  mixed so a cell between rungs renders as a weighted pair instead of snapping to eight hard steps.
- **Idea 3 — typed-cell wake:** `cellRadius`/`typed`/`residue`/`wake`. The latch is *differential* —
  the wake is whatever the history holds above this frame's base render — so it decays on its own
  and cannot run away into a full-frame trail.
- **No spring added.** This file's pointer term is a flow-field repel and stays one.
- **A packing:** ACES display RGBA. Unchanged.

### `pixelation-drift` (+46 / −9)
- **Kept:** param roles; floor-quantised UV; `depthFactor`; `focusLens` and held focus; mouse swirl;
  R/B chroma split; colour-bleed branch; click pixel pulse; C persistence.
- **Idea 1 — block area average:** `blockAverage()` helper, four interior taps per channel, replacing
  the single corner point-sample that made tiles flicker as the grid drifted.
- **Idea 2 — block colour quantisation:** `quantLevels`, coarser palette as the block grows.
- **Idea 3 — drift-lit tile bevel:** `inBlock`/`driftDir`/`bevel`, replacing the flat
  `mix(color, color * 1.2, edgeGlow * 0.1)`.
- **A packing:** ACES display RGBA. Unchanged.

### `spectrum-bleed` (+47 / −6)
- **Kept:** param mapping; `rgb2hsv`/`hsv2rgb`; `blurSource()` (now called three times rather than
  rewritten); spring; velocity-advected `historyUv`; click ink saturation; fft hue push; ACES.
- **Idea 1 — wavelength-ordered bleed:** `spectralBleed()` — R ×0.55, G ×1.00, B ×1.70 radius.
- **Idea 2 — chromatographic advance front:** `satNow`/`satPrev`/`advance`/`frontGate`, gating the
  persistence weight on the saturation gradient.
- **Idea 3 — dry-edge rim:** `dryRim`/`rimHsv`/`rimmed` — more saturated and darker exactly where
  `advance` goes negative, so it needs no extra state.
- **JSON:** `upgraded-rgba` added to `features` (ACES was already in the WGSL; the tag was the only
  thing missing, and it is added now that the cards actually landed). `params` byte-exact.
- **A packing:** ACES display RGBA through an advected coord. Unchanged.

### `vinyl-scratch` (+66 / −10)
- **Kept:** all four saved params as HEAD mapped them (`.x`→rotationSpeed, `.y`→scratchAmount,
  `.z`→wobble, `.w`→noiseIntensity — the JSON names read scratch_density/dust/warping/sepia; that
  mismatch is HEAD's and was **not** rewired); rotation; `vinylDust`; `grooveReflection`;
  `grooveSparkle` + its C coherence; `temporalGrain`; `vignette`; `analogWarmth`;
  `saturationRolloff`; `lensDirt`; `radialChromatic`; spring; click pop.
- **Structural:** the `center`/`dir`/`dist`/`angle` block moved below `rot`, because the eccentric
  centre depends on the rotation angle. Same expressions, later.
- **Idea 1 — eccentric spindle wow:** `ecc`/`spindle`, orbiting the rotation centre at the rotation
  rate. HEAD's `wobbleOffset` (a fixed-rate angular ripple) is kept and still runs alongside.
- **Idea 2 — radius-dependent groove pitch + label:** `labelR`/`outerR`/`grooveBand`/`groovePitch`
  and the `labelMask` disc, replacing `sin(dist * 400.0)`.
- **Idea 3 — stylus scratch marks:** the `scratchMark` loop. The mark's angle advances by
  `age * rotationSpeed`, which keeps it fixed in *record* space as the platter turns, and it wears
  out over the ripple's own lifetime. No extra ripple state.
- **A packing:** ACES display RGBA. **Documented, not repacked:** HEAD reads `C.a` back as a
  sparkle-coherence proxy — that is the semantic alpha being reused. Left intact and called out in
  the file header rather than silently changed.

---

## Gates

| Gate | Result |
|---|---|
| `wgsl_precommit_gate.py --files` (all 10) | 10 passed, 0 failed, 0 workgroup errors, 0 extraBuffer violations |
| `verify-naga-wasm --files` (per file, as edited) | 10/10 valid |
| `verify-naga-wasm --all` | 1420 files, 1380 valid, 40 invalid — **40 known, 0 new** |
| `npm run audit:extrabuffer` | PASS — 0 new violations, 0 out-of-range |
| `npm run audit:dead-sliders -- --files …` | PASS — 10 defs scanned, 0 dead sliders |
| Manual slider check | all four `zoom_params` components read in all 10 files |
| `node scripts/generate_shader_lists.js` | regenerated; `verify:catalog-counts` passes (1370) |
| `npm run verify:wgsl-include` | green (prelude, hash library, 13/13 expander fixtures) |
| `npx react-scripts test --watchAll=false --ci` | 712 passed / 6 failed — **identical on a stashed clean tree**; all 6 are WASM-bridge `./bridge/api.js` ESM resolution, unrelated to shaders |
| `SKIP_WASM_BUILD=1 npm run build` | succeeded |

**Real-GPU visual QA: external, and still required.** This VM has no Vulkan ICD, so
`navigator.gpu.requestAdapter()` returns null and the app shows the WebGPU-required overlay. Nothing
in this batch has been looked at on a GPU. Structural green is not a claim about the picture.
