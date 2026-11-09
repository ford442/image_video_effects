# NOTES — Fork B (sonnet/batch-24): spectral-bleed-confine · chroma-kinetic · magnetic-chroma

Files touched: public/shaders/{spectral-bleed-confine,chroma-kinetic,magnetic-chroma}.wgsl, shader_definitions/advanced-hybrid/spectral-bleed-confine.json, BRIEFS-forkB.md, NOTES-forkB.md. Nothing committed/staged by this fork. Renders/ablations: scratchpad/forkB/ (m_sbc_time.png, sbc_zoom_v2.png, m_ck.png, mc_new_view.png, cmp/m_before_after.png). Real-GPU visual QA: not done (SwiftShader only).

## Gates (all three)
- `wgsl_precommit_gate.py --files …`: 3/3 pass (naga OK, bindgroup compatible, 0 pasted headers, 0 extraBuffer violations).
- `npm run audit:extrabuffer`: PASS, 0 new violations. `npm run audit:dead-sliders -- --files …`: PASS, 0 dead (and by hand: every zoom_params.x/y/z/w is consumed and visible in all three).
- minirender_img grid, 21 cases (192 + 576 px; idle / held cursor / audio 0.4,0.3,0.2 / audio 0.9 high params / all-zero params; T0 = 0, 2, 10, 30): **nan 0, verr null in all**.
- Timing back-to-back vs HEAD (192 px, machine load avg ~12): spectral-bleed-confine 84→79 and 94→86 ms (0.92×, budget 1.25×); chroma-kinetic 8/7, 7/8, 6/7 ms (≈1.0×, noise); magnetic-chroma ≈1.0× (38→26 under noise). The cost of the new work is paid for by hoisting (sbc: 327 → 273 texture fetches/px).

---

## spectral-bleed-confine (1st pass) — formulas: Structure-tensor orientation (§12.2A), Energy-conserving bloom (§12.2F)

**Kept verbatim:** 4 params + roles (Diffusion Radius → tap spacing, Field Intensity → glow/ripple gain, Channel Bias → biasR/G/B, Pulse Speed → radius pulse + glow phase); per-channel Sobel; per-channel 9×9 sparse-tap diffusion with `radius`-texel spacing and depth-scaled radius; edgeMask smoothstep(0.02,0.15); `fresnelGlow` gate + 120° phase offsets + 1.0/0.8/1.2 tints; click-ripple hue bursts; 0.3 history mix; zoom_config.w hold → confinement 0.5 ↔ 3.5.
**A packing:** display RGBA (ACES) + semantic alpha. HEAD wrote unclamped HDR colour with alpha 1.0 into A and C-mixed it pre-tonemap; now ACES first, then `mix(display, history, 0.3)` in display space, C read by exact `textureLoad`. Header says so.

**RESCUES (default look changes):**
- **R1** `bleedRate = zoom_config.x*0.6+0.1` is TIME (zoom_config.x = time) → HEAD's bleed passes 1.0 after ~1.5 s: stdL 0.18 @t=0 → 0.26 @t=10 → **0.74 @t=30** (posterised black/white/neon mosaic). Now `BLEED_RATE = 0.4` (L27, the author's mapping at its midpoint). New: stdL 0.157 @t=0, 0.157 @t=30. (m_sbc_time.png)
- **R2** confinement was a no-op: `confFactor = exp(-localConf*5)` is loop-invariant, so `sum/weight` cancelled it; `confinementStr` (and the zoom_config.w hold) changed nothing. Now a real per-tap cross-channel wall `exp(-confinement·6·Σ|s_other − centre_other|)` using the rgb each tap already fetched (L61-90). Holding the pointer now genuinely tightens the bottle (idle value 0.5 unchanged from HEAD). Wall ablation: 11,495 px >8/255 changed.
- **R3** the "Gaussian" envelope had uv² over radius²-in-texels and was ≈1 everywhere (flat box); replaced with a tap-space Gaussian σ = 3.5 taps (`SIG_TAPS`). Footprint is still `radius` texels, i.e. resolution-dependent (21 % of frame at 192 px vs 7 % at 576 px) — HEAD's behaviour, NOT changed (open item).
- **R4** floor: redundant per-call Sobels removed (3 channels from one shared 9-tap fetch `sobelAll`, L33), filtering-sampler history → `textureLoad` (L260), ACES (L261), alpha `mix(0.8,1.0, edge/glow presence)` (L265) instead of hard 1.0.

**Ideas in the diff:**
1. **Tangent-aligned bleed tensor (§12.2A, Di Zenzo)** — L172-190 (tensor/θ/coherence/`strR,G,B`) + L57-90 (rotated, tangent-stretched lattice in `diffuseChannel`). Measured: 1,178 px >8/255 (3.2 %), 9,743 px >2/255 at default; soft ribbons along the diamond edges (sbc_zoom_v2.png). Revised from "pinch across" to "stretch along" after the first version was invisible (BRIEFS, revisions).
2. **Energy-moving reflection halo (§12.2F)** — L231-240: ρ (rejected kernel mass from R2's weights) scales `fresnelGlow` by (0.4+1.2ρ); bled colour pays `res·(1−0.6g)+g`. Ablation (no ρ scaling, no depletion): 18,821 px >8/255.

**Default-look change (192 px, T0=2, idle): YES, large.** HEAD meanL 0.486 / stdL 0.169 / meanA 1.0 → new 0.548 / 0.159 / 0.942 (held: 0.473/0.180/1.0 → 0.567/0.161/0.944). Against HEAD-with-bleedRate-fixed, mean|Δ| 21.5; of that ACES alone is ~18 (no-ACES ablation: mean|Δ| 7.4; mean saturation 0.319 headfix → 0.292 no-ACES → **0.197 with ACES**) — the catalog's per-channel ACES fit lifts mids (+0.09 meanL) and desaturates pastels. That is the §3 floor, applied as written; if the coordinator prefers vivid halos the one-line alternative is `let display = clamp(result, 0.0, 1.0)` (ablation file: scratchpad/forkB/hd/sbc_noaces.wgsl).

**Open items:** resolution-dependent footprint (R3 note); first frame mixes 0.3 of an empty/inherited C (HEAD too); ACES saturation trade (above); 576 px look differs from 192 px for the same reason as the footprint.

---

## chroma-kinetic (1st pass; hygiene-only before) — formula: Cauchy dispersion (§12.2F)

**Kept verbatim:** 4 params + roles (Distortion Str ×0.1·bass_env·depth; Effect Radius smoothstep falloff; Luma Influence modFactor; Direction Rot rotates the radial field); radial `velocity` field; bass lead / mids lag amounts; 3-tap smear with (1−t) weights; click kinetic bursts; flick-strength bonus (`1+min(speed*3,0.4)`); bass_env; bass/mids/treble smear mix; the RRT/ODT ACES fit; A = RGBA before ACES.
**A packing:** RGBA before ACES (HEAD) everywhere except texels (0,0) = (sprung centre.xy, centre velocity.xy) and (1,0) = (fract(lastTime), 0, 0, 0.7371) — STATE, not pixels (top-left corner; C is not read as colour). Header says so.

**RESCUES:**
- **R5** dead spring: HEAD's extraBuffer[133..138] spring never persisted (buffer re-uploaded zeroed every frame) → `springVel` always 0, flick bonus dead, centre = raw cursor. Now a real critically-damped ω=10 follower in two A texels (L94-105, L192-195; `fract(time)` for rgba16float; sentinel guards first frame / inherited C). Idle cursor ⇒ centre = cursor, velocity 0 ⇒ HEAD's idle centre. The flick bonus is alive.
- **R6** dead per-sector FFT voices (spectrum bins above index 0 are never uploaded ⇒ always 0) removed; the bass/mids/treble mixes are unchanged.

**Ideas in the diff:**
1. **Motion-aligned lead/lag** — L130-137: `velocity += clamp(centerVel·(0.03+0.1·Distortion Str), 0.12)·falloff·modFactor`: R leads along the cursor's travel, B lags, the smear trails behind (the JSON description's "based on motion direction", which HEAD never did). Direction Rot turns only the radial part. Measured with a sweeping cursor (0.2→0.8, ~1 uv/s): 9,996 px >8/255 (mean|Δ| 4.3) at default params, 25,933 px (11.3) at Strength 1 / Radius 0.8; zero at an idle cursor.
2. **Cauchy spectral fringe (§12.2F)** — L44-72 `spectralFringe`: five wavelength taps (660/600/550/500/450 nm) at Cauchy fractions −0.190/0.037/0.286/0.613/1.055 of the lead→lag segment, calibrated so R and B channel centroids sit on HEAD's −lead/+lag; G moves from −0.5 to its Cauchy position (−0.35). Per-channel spectral weights sum to 1; zero velocity returns the image unchanged. Idle: 804 px >8/255 (2.2 %), mean|Δ| 0.41 — a continuous rainbow fringe instead of three discrete ghost copies (subtle by design; m_ck.png).

**Default-look change:** none beyond the fringe shape. Idle 192 px: meanL/stdL/meanA 0.291/0.130/0.284 → identical (0.291/0.130/0.284); held cursor identical (0.275/0.127/0.253). Cost ≈ HEAD (5 fringe taps replace 3 channel taps).
**Open items:** minirender stores A as rgba32float, so verify the A-texel spring on a real rgba16float tier (fract(time) + sentinel tolerance were chosen for it, not measured); motion magnitude constants (0.03/0.1/0.12 clamp) are tuned by eye on a 1 uv/s sweep; `mousePos` is now clamped to 0..1 (HEAD used it raw).

---

## magnetic-chroma (2nd pass) — no §12.2 rows (tactic-derived ideas)

**Kept verbatim:** 4 params + roles; per-channel RK2 field-line smear (4 sub-steps, per-channel dt divergence); N/S pole pair + slowly turning axis; compass hue; hue warp / saturation boost; neon + bloom; ACES; depth relief; A = raw field record (fieldStrength, influence, chromaticSep, alpha); existing three ideas and their comments. Ideas line appended, `Upgraded: 2026-10-05, 2026-11-09`.
**A packing:** unchanged (raw field record; C not read). A.w alpha now includes the filing coverage term.

**Rescues:** none needed (HEAD healthy at idle/held, 192/576).

**Ideas in the diff:**
4. **Lorentz gyration of the R/B streamlines** — L98-111 (`lorentz_field` rotates the field vector by cs=(cos θ, sin θ) in aspect space inside each RK2 stage) + L145-146, L160-161 (θ = Chromatic × 1.2 rad; R +θ, G 0, B −θ). cs=(1,0) is HEAD. Opposite charges curl opposite ways, so the channels fan out into spirals around the poles instead of only an x-offset. Ablation (θ=0): 1,832 px >8/255 at default params (Chromatic 0.3 → 0.36 rad), ~16k at Chromatic 0.8.
5. **Iron filings** — L190-215: one jittered needle per cell (cell 0.028 aspect, ≥7 px), oriented along the same `magnetic_field()` evaluated at the needle centre (agrees with the RK2 smear by construction), ±10° / length / presence jitter, dark metallic needles faded in with `influence`/`highField`; sits under the neon. Ablation: 530 px >8/255 at default (sparse sprinkle in the field region), 1,078 at hi params; reads as filings at 576 px (mc_new_view.png).

**Default-look change:** small. Idle 192 px 0.511/0.171/0.820 → 0.510/0.171/0.820 (held 0.517/0.150/0.821 → same); head-vs-new 2,025 px >8/255 (5.5 %), mean|Δ| 1.2 (idle); 3,096 px (8.4 %), 1.8 (held).
**Open items:** at 192 px the filings are a sparse sprinkle (a 7 px cell); needle opacity/darkness (0.75 × 0.18) is tuned by eye; Lorentz angle at Chromatic ≥ 0.8 (≥ 55°) is very strong — acceptable because it is slider-driven, but worth a real-GPU look.

---

## §12.2 row ledger (Fork B)
Structure-tensor orientation: spectral-bleed-confine (+ fabric-step-gabor, Fork A) · Energy-conserving bloom: spectral-bleed-confine (+ vaporwave, Fork D) · Cauchy dispersion: chroma-kinetic (+ data-stream-spectral, Fork D). Non-row ideas: cross-channel confinement wall (restoration), motion-aligned lead/lag, Lorentz gyration, iron filings.
