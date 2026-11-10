# NOTES — fork B (spectral): rgb-ripple-distortion, rgb-distance-split, spectral-vortex

HEAD = 75dbf877. All renders SwiftShader WebGPU via a copy of `agents/mr.mjs` (scratch `…/scratchpad/forkB/mrb.mjs`) extended with: injected click ripples (`RIPPLES`), a high-detail source (`DETAIL=1`, 48×48 random cells — a photo has far more edges than the harness's smooth default source), and **extraBuffer re-zeroed every frame like `audioDepth.ts` does** (the stock harness leaves extraBuffer persistent, which made HEAD's dead springs look alive). "Visibility" = % of pixels whose max-channel |Δ| > 0.02 versus the same file with only that idea switched off, default sliders. `pct>0.05` in brackets. Real-GPU QA is external.

Scenarios: **idle** (no input), **rip** (2 injected clicks at t=0.1/0.45, 60 frames over 1.0 s = real-time 60 fps), **held** (cursor dragged 0.3→0.6 held, 60 frames), **aud** (held + bass/mid/treb 0.8/0.5/0.9), **detail** = same on the DETAIL source. 576 runs use 40 frames.

---

## 1. rgb-ripple-distortion — first pass (2026-05-23 hygiene header only)

KEEP VERBATIM held: yes — 4 params (ids/names/defaults/mapping untouched; Frequency→ring k, Amplitude, Wave Speed, Color Separation→photoelastic `stressOptic`), displacement field ×0.94 feedback, pointer push+swirl, HEAD's first ring (`sin(r·freq−age·speed·4)·exp(−9r−0.9·age)`), stress-tensor chain, principal stresses/angle, per-channel retardation, fringePalette×spectral×isoclinic, B packing (HEAD-owned), depth proxy.
**A packing:** unchanged — A = (displacement.rg, fringe/10, stressMag), a raw FIELD read back as C; never tone-mapped. Output is LDR, **no ACES** (rest must be an exact pass-through; ACES would alter an undisturbed photo) — I dropped the false `upgraded-rgba` token from the WGSL header Features line; JSON never carried it.

| # | Idea | Where | Visibility (192 / 576), % px > 0.02 |
|---|---|---|---|
| 2 | Deep-water ripple dispersion (§12.2D): second wave k₂=1.8·freq, ω₂=√1.8·ω₁ (c ∝ 1/√k), 0.7 amplitude, faster decay, gated `behind` its own slower front ⇒ leading long wave + trailing finer train | `rgb-ripple-distortion.wgsl` ≈L105-115 | rip 5.3 [1.2] / 4.1 [0.9]; detail-rip 8.3 [2.3] / 7.9 [2.5]; held 0 (no clicks, by design) |
| 1 | Cauchy dispersion (§12.2F): n(λ)=1+B/λ² at 650/550/450 nm from green ⇒ R −0.29 : B +0.51 instead of ±0.4 (ratio 1.74 is fixed by the law; mean spread normalised to 0.4·chromaShift) | ≈L164-176 | held 7.0 [2.9] / 6.5 [2.2]; detail-held 17.3 [10.7]; **rip 0.6 / 0.4, detail-rip 4.9 [1.0] / 3.2 [0.9]** |

**Deviation from the card (rule 15):** the card said Color Separation ×gain with 0.5 = HEAD magnitude. At HEAD magnitude Cauchy was invisible (clicks 0.15 %, because HEAD's R/B split is < 1 px at default on ripples) so the slider now drives the split as `0.5 + 5·w` ⇒ **default = 3× HEAD's chromaShift** (0 ⇒ 0.5×, 1 ⇒ 5.5×). Its existing optic role (`stressOptic`) is unchanged. Even so, on the smooth harness source Cauchy on *clicks* is only 0.4–0.6 % (it is 3–5 % on a detailed source and 6.5–7 % near a held pointer) — the asymmetry is a second-order effect of an already small split.
Rescues: **R1** `fieldAt` filtering-sampler read of C → exact `textureLoad` at the pixel (+4 clamped neighbours for the stress derivatives) — identical at texel centres. **R2** Color Separation now also scales the split (see above). **R3 verified, fixed:** HEAD at rest = source ×0.77 (meanL 0.409→0.316) and alpha 0.82; `restGate = 1−exp(−40·stressMag)` scales the polariscope mix and alpha so rest is an exact pass-through (meanL 0.409, meanA 1.0; alpha mixes from the source alpha). **R4** LDR, no ACES (see packing).
Default-look change (192, meanL/stdL): idle 0.316/0.137 → 0.409/0.178 (= the source); rip 0.314/0.136 → 0.392/0.166 (meanA 0.857→0.978); held 0.314/0.133 → 0.388/0.166. HEAD's photoelastic fringes at default stress are ≈0 (δ≈0.017 rad), they only show near a held pointer (visible in `held` renders) — unchanged in character, they now sit on an undarkened picture.
Sliders: all 4 live (0↔1 vs default on detail-rip: 38/38/36/36/69/41/15/16 % of pixels). A16=1 vs float32: 0.00 % pixels differ. nan 0. Idea 2's `rippleCount` loop cost scales with active clicks only.
**Fix round (declare only, no behaviour change):** the WGSL header now states the deviations from HEAD — sepGain = 0.5 + 5·w makes the default (w = 0.5) R/B split 3× HEAD's (HEAD's was under 1 px) as a deliberate rescue; at rest the output is an exact pass-through (idle meanL ≈ +29 %, 0.316 → 0.409); a click's ripple train can raise stress into saturated green/magenta blobs around ~0.4 s.
frameMs HEAD→new: see "Timing" below. Open: the `behind` gate means the short train appears only after ≈age>r/c₂; at very low Wave Speed the train is nearly invisible (not measured).

## 2. rgb-distance-split — 2 ideas already shipped; +2 (file Idea 3 = card idea 2, file Idea 4 = card idea 1)

KEEP VERBATIM held: yes — 4 params, dir/effectFactor/rotSeparation, shipped Idea 1 (7 wavelength taps, per-channel spectral weights/normalisation, Blur trailing tap), shipped Idea 2 (±1st-order ghosts), Beer–Lambert alpha + 15 % tint, ACES, A = display RGBA (write-only), depth passthrough.
**A packing:** unchanged (ACES display RGBA).

| # | Idea | Where | Visibility (192 / 576) smooth: mid-cursor, angle 0.8 / detail |
|---|---|---|---|
| 3 | Secondary spectrum (§12.2F, Cauchy-family non-linear dispersion; second file of the row): offset = rotSep·(k + 0.3·k²) — green stays at 0, R 1.3×, B −0.7× — lopsided, on *opposite* sides of green (red's side longer); not a same-side "purple fringe" (wording corrected in the fix round) | `kOff` in the 7-tap loop | 20.8 [2.8] / 48.5 [12.8]; detail 64.9 [35.4]; 576: 12.1 [1.2] / 39.1 [7.0] / 64.2 [35.7] |
| 4 | Longitudinal CA (native lens physics): a perpendicular 2-tap *line* (not a disc) at the red centroid (k≈+1.3) and at the blue centroid (k≈−0.7), half-width **min(1.2·effectFactor·strength, 0.03 uv)** (fix round: was uncapped, up to ~0.06 uv ≈ 35 px at 576 where the two taps read as ghost copies), mix up to 0.9·effectFactor; green untouched. **4 extra loads total** | after the spectral sum | fix-round (cap 0.03): 2.3 [0.4] / 5.1 [0.0] ; detail 40.5 [14.5]; 576: 2.4 [0.4] / 5.3 [0.0] / 41.9 [15.8]. Before the cap: 5.3 / 19.9 / 40.2 (192), 5.4 / 20.3 / 41.5 (576) |

Fix-round trade-off (idea 4, whole-frame % > 0.02 at 192, mid / angled / detail): cap 0.025 → 1.2 / 3.4 / 40.8; **0.03 (kept) → 2.3 / 5.1 / 40.5**; 0.04 → 4.8 / 10.7 / 40.0; uncapped (~0.06) → 5.3 / 19.9 / 40.2. The default-slider smooth image is now at the low end of "several percent" (it is distance-gated: only the outer region moves); on detailed content it is unchanged (40 %). A real fix for the ghost-copy look would need ≥3 taps per plane (≈ +4 loads, > 1.3× HEAD), so the radius is capped instead.

(Idea 4's first version — a per-wavelength 2-tap defocus on |k|≥1, 8 extra loads — measured only 1.65 / 7.6 / 30.6 % at 192; the centroid form is both cheaper and more visible.)
First-version cost problem: Idea 4 as 8 per-wavelength extra loads measured ≈1.35–1.5× HEAD under load, so it was restructured to the centroid form (21 → 25 loads) and got *more* visible.
Rescues: R1 pixel-centre uv; R2 the shadowing `var c` in the loop renamed `tapCol` (the loop body was rewritten anyway). The numbering inside the file is HEAD's "Idea 1/2" + my "Idea 3/4".
Default-look change: meanL/stdL mid 0.498/0.171 → 0.499/0.170, ang 0.492/0.162 → 0.493/0.163; vs HEAD 27 % (mid) / 51 % (ang) of pixels > 0.02 (the fringe is re-shaped, not added to).
Sliders: Split Strength, Blur, Deadzone strongly live; **Angle Offset** 0↔1 is identical by construction (angle = p·2π, one full turn) — 0.25 changes 79 % of pixels. A is write-only; nan 0.

## 3. spectral-vortex — 3 ideas already shipped (2026-10-05); +2

KEEP VERBATIM held: yes — 4 params, shipped ideas 1-3, `loadStateBilinear` + C-state decode, image-gradient curl, held/click terms, ACES only on writeTexture, B unwritten, depth passthrough.
**A packing:** unchanged (raw sim state phase, curl.xy, energy). A16=1 vs float32: ≤0.34 % pixels (audio case), 0.01–0.03 % otherwise; 60-frame runs, nan 0.

| # | Idea | Where | Visibility (192 / 576) |
|---|---|---|---|
| 4 | Lamb–Oseen pointer vortex (native; this shader is a vortex field): swirl magnitude `(1−exp(−d²/rc²))·1.567·rc/d·exp(−2.5d)`, rc=0.12, peak 1 at ≈1.12·rc — calm eye instead of HEAD's unit-tangent×exp(−6d) with an undefined direction at d→0 | pointer swirl ≈L86-95 | held 10.6 [5.7] whole frame at 192 (16.5 % within 0.2 uv of the cursor) / 8.6 [6.1] at 576; **with audio 36.9 [16.7] / 33.4 [10.2]** |
| 5 | Luma-preserving hue spin: same turn count **and same direction** as HEAD's HSV `H += turns` (fix round: YIQ angle is negated — in the I/Q plane the hues run R→B→G, opposite to HSV's R→G→B), rotating (I,Q) of YIQ about luma (`spinChroma`) instead of HSV H at constant V | `turns` / `spinChroma` ≈L137 | 93 % / 90 % px differ (the hue *mapping* changes, so this is a large default-look change); **luma drift attributable to the spin (mean \|ΔY\| vs colorShift=0): HSV 0.0215 → YIQ 0.0012 at 192, 0.0135 → 0.0006 at 576 (18–22× less).** Fix-round re-measure, temporal std of the frame's mean Y over one full hue turn (colorShift 1.0, 10 steps of 0.1 turn, 8 frames each, 192): **HSV std 0.0040 (peak-to-peak 0.0127) → YIQ std 0.0003 (p2p 0.0009), ≈13× steadier.** Direction check: mean \|Δ\| of the YIQ result vs the HSV result of the same turn count: old sign 0.129 (192) / 0.083 (576) → negated 0.049 / 0.030 (the residue is the legitimate luma/saturation difference between the two spaces) |

**Deviation from the card (declared in the WGSL header):** first Lamb–Oseen constants (rc 0.09, exp(−3.2d)) gave only 2.1 % of the frame (held) — pointer-local and weak — so rc=0.12 (card said 0.06–0.08), exp(−2.5d). **Footprint vs HEAD's exp(−6d) unit tangent:** peak 0.74× HEAD's; far field 1.8× at d = 0.2–0.3, 2.2× at 0.5, 6× at 1.0 (absolute 0.40 vs 0.22 at d = 0.25; 0.11 vs 0.05 at 0.5; 0.015 vs 0.0025 at 1.0). Fix round tried a steeper envelope: exp(−3.5d) (far field ≈1.3–1.45× HEAD at d 0.2–0.5, 2.3× at 1.0) → held 3.5 % / aud 14.0 % at 192; exp(−4.0d) (≈1.0–1.3×) → 2.0 % / 7.1 %; the kept exp(−2.5d) gives 10.9 % / 35.0 % (192; held 9.3 % at 576). The visible gain lives in the far field, so the wider footprint is **kept and declared**, not trimmed.
**R1 verified:** HEAD's `extraBuffer` spring is dead in the app (harness with extraBuffer zeroed per frame: spring-removed HEAD vs HEAD = 0.00 % pixels in idle/held/aud), so the dead state path was deleted and the pointer is the raw cursor; header note added. No A-texel scheme (A is a per-pixel sim).
Default-look change (192 meanL/stdL, final file after the sign flip): idle 0.528/0.177 → 0.527/0.179; held 0.529/0.179 → 0.532/0.180; aud 0.562/0.179 → 0.564/0.180. The picture's hues are re-mapped (YIQ vs HSV chroma rotation, same direction) — compare on a real GPU. Sliders: all 4 live; Twist Scale/Distortion Step move ≈1 % of pixels in `held`, **the same as HEAD** (their effect is a small offset by design). rgb2hsv/hsv2rgb removed (unused). nan 0.

---

## Gates (final files)
Fix round re-run (all three final files): precommit 3/3 pass · `verify-naga-wasm --files` 3 valid / 0 invalid · dead-sliders 0 new · extrabuffer 0 new. (`verify-naga-wasm` also prints `wgsl_validation.json knownFailures.ratchet is 5 but ids lists 4` — a registry-consistency complaint about a file outside fork B's scope, not touched here.)
First-round gates:
`wgsl_precommit_gate.py --files` 3/3 pass · `verify-naga-wasm.mjs --files` 3/3 valid · `audit:dead-sliders -- --files` 0 new · `audit:extrabuffer` 0 new (the spring removal in spectral-vortex reduces extraBuffer use).
JSON: description ≤ +65 chars (rgb-ripple) / ≈ +79 chars (rgb-distance-split after the fix-round rewording: "purple fringe" dropped, "Lopsided secondary spectrum (red +1.3 : blue −0.7), axial defocus."); `validate_shader_definitions` 1430 valid, spectral-vortex "sprung pointer"→"Lamb–Oseen pointer vortex"; rgb-ripple features + audio-reactive/click-reactive/depth-aware; `x-meta.upgrade.params` added to rgb-ripple and rgb-distance-split.
§12.2 rows: rgb-ripple = Cauchy (F), deep-water dispersion (D); rgb-distance-split = Cauchy-family (secondary spectrum) + native longitudinal CA; spectral-vortex = native ×2 (no dispersion row, per the budget).

## Timing (SwiftShader, shared machine at load ≈5-8 from other forks — indicative only; coordinator re-times)
frameMs medians of 5 (ms/frame; HEAD → new; two interleaved pairs each), same load:
- rgb-ripple-distortion (2 clicks): 192: 11→11, 11→15; 576: 97→92, 88→86 (≈1.0–1.1×; ripple cost scales with live clicks).
- rgb-distance-split, **final 4-load version**: 192: 12→16, 15→15; 576: 115→150, 123→126 (≈1.0–1.3×). The first per-wavelength version measured 16→24, 14→19 at 192 (1.4–1.5×) and was restructured — see above.
- rgb-distance-split, **fix-round re-time** (cap 0.03 changes arithmetic only, same 4 extra loads; machine load ≈7): 192: 13→13, 12→14; 576: 132→153, 103→179 (the second 576 pair is load noise — HEAD itself swung 103↔132; the clean pairs are 1.0–1.2×). Not a reliable ≤1.3× proof at 576: coordinator re-times alone.
- spectral-vortex (held): 192: 17→12, 16→17; 576: 90→81, 107→69 (≤1.0×; the spring write and HSV helpers are gone).
