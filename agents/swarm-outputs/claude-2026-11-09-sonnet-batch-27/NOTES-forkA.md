# sonnet/batch-27 — fork A notes (ascii-lens, cross-mouse-spec-dispersion-lens, quantum-flux)

Files touched (only these): `public/shaders/{ascii-lens,cross-mouse-spec-dispersion-lens,quantum-flux}.wgsl`,
`shader_definitions/interactive-mouse/{ascii-lens,cross-mouse-spec-dispersion-lens,quantum-flux}.json` (`features`/`tags` only; `params` byte-exact), this file.
No git add/commit, no build/Vitest, no list generation. Render proof is SwiftShader structural proof only (no real-GPU visual QA claimed).

Harness paths (H = `.../scratchpad/harness`, F = `.../scratchpad/forkA`, S = `.../scratchpad`; full prefix `/tmp/claude-0/-home-user-image-video-effects/d42ad8f0-8e0e-5ffd-959e-50bf3ecd73aa/scratchpad`):
- `F/render_seq.mjs` is a **scratch copy** of `H/render.mjs` (harness untouched) that adds `--mouse-path "x,y,down;x,y,down;..."` (mouse interpolated across the run), `--keep i,j,k --seq-prefix p` (dump those frames) and prints `GLIDELOG` (A texel (0,0) after every frame). Everything else is identical to render.mjs.
- `F/rr.sh <id> <tag> <args>` renders HEAD and NEW with identical args; `F/crop.py`, `F/table.sh` are small helpers. PNGs are in `F/out/`.

Common to all three (R1 glide, see COMMON.md): first-order glide in A texel (0,0) = `(glide.x, glide.y, 7, fract(time))`, replaces a dead critically-damped spring.
At rest the lens/cloud sits exactly on the cursor (f16-emulated check: converges and snaps to the raw cursor for four cursor positions); moving, it trails by ~1/rate s (verified in the harness: A(0,0) follows 0.2 → 0.8 with the expected 1 − exp(−rate·dt) steps; `GLIDELOG`).
One deviation from the COMMON snippet: `st.w <= 1.0` instead of `< 1.0` — in f16, `fract(time)` > 0.9997 rounds to exactly 1.0, which would make `ok` false for one frame about once a minute and teleport the lens to the raw cursor for that frame. **Suggest the other forks use `<= 1.0` too.**
`display pixel (0,0)` still goes to `writeTexture`; none of the three shaders reads C for anything else, so no masking is needed.

---
## 1. ascii-lens

**Kept verbatim:** 4 params and roles; 5 tiers + thresholds 0.8/0.6/0.4/0.25/0.1 and glyph shapes (`#`, `@`, `+`, `-`, `.`); cell-centre colour × charVal; click scramble jitter + RGB split outside; luma-alpha/depth-mix alpha; depth passthrough; "mouse < 0 → centre"; HEAD's literal 0.8·charVal and −0.05 luma bias at zero audio. No ACES (by design), no IQ palette/CRT/scanlines/new params.

**A packing:** display RGBA (unchanged); texel (0,0) = (glide.x, glide.y, 7, fract(time)).

**Ideas** (line numbers = current file):
- Idea 1, cell-mean luma + Bayer-ordered tier dither (L137–L169): 5 taps (centre + 4 at ±0.3 cell) → `cellLuma` replaces the single centre tap in the tier decision; `bayer4(cellIdx) * 0.12` (±0.06) shifts the tiers (helper `bayer4` L60). Colour stays the cell-centre tap.
- Idea 2, edge-directed strokes (structure-tensor orientation, §12.2A) (L180–L209): gradient `g = (lumaR−lumaL, lumaD−lumaU)` from the same 4 taps; where `|g| > 0.08` the `+ - .` tiers (0.1 < luma ≤ 0.6) become one stroke along the edge tangent, width = the existing line-width slider; `#` and `@` unchanged.
  - Deviation (detail): the tangent is **snapped to the four ASCII stroke angles** (`- | / \`) rather than free angle, so strokes read as glyphs and join across neighbouring cells. The tensor is the single-cell rank-1 `∇L∇Lᵀ` (orientation = gradient direction, `|g|` is the confidence; no smoothing over neighbours, so no separate coherence term).
**Rescues:** R1 glide rate 8 (L28–L43 `glideStep`, L83–L85, store L249–L255). R2 dead audio: `bass = plasmaBuffer[0].x` (L87); per-cell flicker `plasmaBuffer[1..8]` → `fftVoice(cell-hash voice)` = `extraBuffer[5+bin]`, bins {0,1,2,4,7,11,19,32} (L45–L58, L152–L155). Zero audio → flicker 0 → HEAD's idle look. Small guard: alpha `clamp(…, 0, 1)` (L227) — the now-live shimmer (0.8 + flicker up to 0.4) could push `lumaFinal` > 1 and alpha > 1; identical at idle. Colours > 1 under loud audio are left as HEAD designed (no ACES/clamp on the photo-through effect).

**Default-look change:** yes, local, global stats unchanged. Harness defaults (`--params 0.3,0.5,0.5,0.5 --mouse 0.5,0.5,0 --src photo --depth flat`, 12 frames): meanL/stdL 192 px HEAD 0.3558/0.2367 → NEW 0.3554/0.2369; 576 px HEAD 0.3576/0.2398 → NEW 0.3569/0.2400. What changes: hard contour bands between tiers become a fine ordered pattern; edge cells (mountain slopes, sun rim, object outlines) get directional strokes. Identity (cursor lens of coloured glyph cells, photo untouched outside) unchanged. Note: at density 0.5 and 192 px a cell is 1.5 px, so glyph detail is only legible at ≥ 576 px (look at `ascii-lens_d1_576_*.png`, `c1.png`).
**Formula names:** structure-tensor orientation (§12.2A); (cell-mean + Bayer dither is aalib/libcaca practice, not a §12.2 row).
**Gates:** Naga valid; precommit gate pass (naga skipped there, run via verify-naga-wasm); `audit_dead_sliders` 0 new (all four `zoom_params` consumed and visible); `audit_extrabuffer` pass (no extraBuffer writes). Renders: 192 and 576, default/idle, held+moved cursor + audio (`--audio 0.5,0.4,0.3`), click ripples, density 0 and 1, extreme-slider NaN sweep (nan 0), 240-frame moving-cursor run (glide settles exactly, nan 0), idle stability (frames 1/5/11 pixel-identical, A(0,0) = (0.5,0.5,7,w)).
**Open items:** `isEdge` threshold 0.08 is a fixed luma-per-cell contrast (dense grids → fewer strokes by construction); tune on a real GPU. In the harness all per-bin FFT values are equal within a band, so per-cell different voices were not distinguishable.

---
## 6. cross-mouse-spec-dispersion-lens

**Kept verbatim:** 4 params; Cauchy constants (n0 1.4, B 3000, λ 650/530/460) and `cauchyIOR`; parabolic thickness profile; `angle = t·rot·0.2 + profile·π` rotating normal; held ×2 dispersion; glow; bass rim; click bursts + spectral ring; alpha; depth passthrough; aspect-correct lens; treble shimmer on the R/B ends. No ACES, no IQ palette, no new params, no extra ripple stamps.

**A packing:** display RGBA (no ACES: the photo passes through; glow/rim are additive); texel (0,0) = (glide.x, glide.y, 7, fract(time)).

**Ideas:**
- Idea 1, continuous spectral integration (Cauchy dispersion, §12.2F) (L171–L198): 6 wavelengths evenly spaced in 1/λ² (650, 594, 550, 514, 485, 460 nm — evenly spaced Cauchy displacement; tap 0 = HEAD's red extreme exactly, tap 5 = HEAD's blue extreme exactly), each with its own `cauchyIOR(λ)` displacement relative to the 530 nm green reference; accumulated with Gaussian R/G/B response lobes normalised **per channel** (sum = 1, so white/flat stays unchanged; at zero amplitude the result is exactly the source).
- Idea 2, axis-regularised refraction (L156–L162, used L169): `axisReg = smoothstep(0, 0.3·lensRadius, r)` multiplies the displacement amplitude — none on the optic axis, full in the annulus; the rotating normal is unchanged (now `rotDir / max(|rotDir|, 1e-5)` instead of `normalize(rotDir + 1e-4)`, a NaN-safe equivalent).
**Rescues:** R1 glide rate 8 (L48–L61 `glideStep`, L96–L99, store L217–L223). R2 dead treble `plasmaBuffer[6].x/[8].x` → `trebleLo = fftBand4(10)`, `trebleHi = fftBand4(30)` (means of 4 adjacent engine bins; L63–L73, L86–L88). R3 **dispersion unit gain** (L41–L42 const `PRISM_GAIN = 80`, L163–L169) — see "card deviation" below. Hygiene: two `pow(negative, 2.0)` (click ring, bass rim) → `d*d` (L125–L126, L205–L206), numerically identical (max 1/255 rounding vs the pow render), removes undefined `pow` of a negative base.

**Card deviation (important, please read):** the card says "R and B extremes keep HEAD's maximum fringe extent". HEAD's extent is invisible: `(iorR − iorG) ≈ −3.6e-3`, so the R/B offset was ~4e-5 uv at the default sliders and ≤ ~4e-4 uv (a quarter of a pixel at 576 px) with every slider at maximum and the pointer held. Measured on HEAD at 576 px (`--params 0.8,D,1.0,0.5 --mouse 0.5,0.5,1`, D = 0 vs 1.0): mean pixel difference 0.075/255, max 31/255 at a few barcode edge pixels — i.e. the prism showed no fringes at all, only the additive glow. Spectral integration of sub-pixel offsets would have been invisible, so I added R3, a unit gain `PRISM_GAIN = 80` that converts the Cauchy IOR difference into a visible uv displacement. At default sliders the extreme taps are now ~2.8e-3 uv at the annulus peak (≈ 1.6 px at 576 px; mean R–B centroid separation about half that of the extremes), at the slider maximum + held ≈ 3e-2 uv. Slider ranges and roles unchanged. It is one constant (`PRISM_GAIN`), tune up/down on a real GPU; set it to 1.0 to see HEAD's (invisible) amplitude.

**Default-look change:** yes, but luma-neutral (chromatic): harness defaults (`--params 0.3,0.3,0.5,0.5 --mouse 0.5,0.5,0`) meanL/stdL 192 px HEAD 0.4338/0.2331 → NEW 0.4338/0.2331; 576 px HEAD 0.4368/0.2328 → NEW 0.4369/0.2328 (mean |Δ| 0.0004 — the default lens radius slider 0.3 → R = 0.125 uv is a small lens, fringes are confined to its annulus). Visible in `c3.png` (default: red/orange fringe on the mountain edge, blue on the top, pink/cyan split on the white streak) and `c4.png` (`--params 0.9,0.7,0.8,0.5 --mouse 0.45,0.45,1`: continuous rainbow bands, the white streak splits into spectral lines).
**Formula names:** Cauchy dispersion (§12.2F) — this file only in fork A (heat-haze-mirage is the other allowed file).
**Gates:** Naga valid; precommit gate pass; dead sliders 0 new (all four consumed); extraBuffer audit pass (no writes). Renders: 192/576 default, strong-slider held cursor, audio + click ripple, depth none/ramp, extreme-slider NaN sweep (`0,0,0,0`, `1,1,1,1`, `1,1,1,0`, `0,1,1,1`, `0.5,0,0.5,0.5`; nan 0), 240-frame run (nan 0), idle stability (frames pixel-identical), glide sequence (A(0,0) trails 0.2 → 0.8).
**Open items:** `PRISM_GAIN` value (80) and the response-lobe widths (σ red/blue 0.35, green 0.22) are tuned by eye on SwiftShader only. HEAD has no "mouse < 0 → centre" fallback in this file and I did not add one.

---
## 10. quantum-flux

**Kept verbatim:** 4 params + audio rides (`jitterBase/freq/driftSpeed/radiusParam`); hash jitter `rand(seed)`; RGB split; radial `wave` (numerically identical: `sin(phi)·0.02·influence`, `phi` = HEAD's expression); HSV hue drift + `driftMask` + saturation lift; interference scanlines; click decoherence bursts; alpha formula; depth passthrough. No drawn orbits/particles, no IQ palette, no new params.

**A packing:** display RGBA (unchanged); texel (0,0) = (glide.x, glide.y, 7, fract(time)).

**Ideas:**
- Idea 1, radial probability shells (T2/T3; jitter × ψ²) (L131–L142; applied in `jitterAmount` L144–L148): `phi` (the existing wave phase) is shared; `shell = 0.35 + 1.3·sin²(phi)` (mean 1.0, default strength kept) multiplies the slider-driven jitter amplitude (`jitterBase·(1+sectorVoice)·shell + clickBurst`; click bursts stay unweighted because they sit at the click point, not on the shells). Small addition: the weight fades to 1 below Wave Freq ≈ 0.08 (`smoothstep(0, 0.08, freq)`) so that at freq 0 there are no spatial shells and no whole-cloud 1.6 Hz strobe of the jitter amplitude.
- Idea 2, quantum-jump hue (L170–L178): the drifted hue is quantised to 6 energy levels, `(floor(h·6) + smoothstep(0.78,1,fract(h·6)))/6`, i.e. plateau-then-jump hue steps over time and (via the existing `dist·2` term) concentric hue shells. Drift Speed keeps its role (speed + mask; slider 0 → mask 0 → no hue change, no quantisation).
**Rescues:** R1 glide rate 9 (L35–L48 `glideStep`, L85–L92, store L195–L201). R2 dead per-sector FFT `plasmaBuffer[1..8]` → `fftVoice(sector)` = `extraBuffer[5+bin]`, bins {0,1,2,4,7,11,19,32} (L50–L63, L110–L111); zero audio → 0, as HEAD.

**Default-look change:** yes, clear but same effect (rainbow flux cloud, speckle jitter, scanlines). Harness defaults (`--params 0.5,0.4,0.3,0.6 --mouse 0.5,0.5,0`, 12 frames, t 2..3): meanL/stdL 192 px HEAD 0.4119/0.2124 → NEW 0.4046/0.2230; 576 px HEAD 0.4139/0.2117 → NEW 0.4074/0.2238 (mean |Δ| 5.6 %, 55 % of pixels differ by > 8/255). Look: continuous hue gradient → stepped concentric hue rings (photo luminance/structure still reads through); jitter now clusters in travelling shells and is crisp at the nodes (clearest with Color Drift 0: `m_qf_shell.png`).
**Formula names:** none (§12.2 row budget untouched); ideas are T2/T3 per BRIEFS.
**Gates:** Naga valid; precommit gate pass; dead sliders 0 new; extraBuffer audit pass. Renders: 192/576 default, moved + held cursor, audio (`--audio 0.5,0.4,0.3`) + click ripple, checker source, extreme-slider NaN sweep (`0,0,0,0`, `1,1,1,1`, `1,0,1,1`, `0,1,0.5,0`, `0.5,0.04,1,0.6`; nan 0), 240-frame run, idle (time frozen) frames pixel-identical, glide sequence.
**Open items:** the hue quantisation is bold (6 levels, flat bands inside the whole influence zone); if it reads as too posterised on a real GPU, dial the plateau (0.78) or blend toward the continuous hue by `influence`. Not verified: per-sector FFT differences (harness FFT is constant per band).

---
## Process notes for the coordinator
- `python3 scripts/wgsl_precommit_gate.py` (any run, mine included) rewrites the shared `reports/wgsl_precommit_report.json`; it was already modified before my first run and is not part of this fork — restore/regenerate it at integration.
- No `x-meta.upgrade` changes were needed: the three JSONs' `x-meta.upgrade.params` already agree with the saved `params`. `upgraded-rgba` removed from cross-mouse and quantum-flux JSON `features` and from all three banners (no ACES on display RGB by design). `fast-motion` n/a here.
- JSON tags: ascii-lens + `ascii`, `lens`; quantum-flux + `quantum`, `chromatic` (no idea-named tags).
