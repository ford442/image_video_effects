# BRIEFS — Fork B (sonnet/batch-24): spectral-bleed-confine · chroma-kinetic · magnetic-chroma

Written BEFORE any WGSL edit. HEAD renders: scratchpad/forkB/ (sbc_head_T{0,2,10,30}.png, sbc_fix_T*.png, ck_head_hi.png, mc_head_hi.png, *_576_*.png) + parent's base/*_head_{a,b}.png.

## HEAD findings I verified myself (not just the coordinator's hypotheses)

| # | Shader | Finding | Evidence |
|---|---|---|---|
| H1 | spectral-bleed-confine | `bleedRate = zoom_config.x*0.6+0.1` and `zoom_config.x` is TIME → `mix(src, bled, edgeMask*bleedRate)` extrapolates past 1 after ~1.5 s. By t=10 s stdL 0.26, by t=30 s stdL 0.74 and the frame is a posterised black/white/neon mosaic. Same shader with `bleedRate = 0.4`: stdL 0.175 at t=0 and at t=30. | m_sbc_time.png (head0/2/10/30 vs fix0/fix30) |
| H2 | spectral-bleed-confine | `diffuseChannel`: `w = gWeight*confFactor` where `confFactor = exp(-localConf*5)` is **loop-invariant**, so `sum/weight` cancels it exactly. The "confinement" (other channels' edges block diffusion) is a **no-op**; `confinementStr` (= `zoom_config.w*3+0.5`, i.e. a hidden mouse-held switch 0.5↔3.5) therefore changes nothing visible. | code reading; `confField` also computed and unused |
| H3 | spectral-bleed-confine | Gaussian envelope `exp(-dist2/(radius²·0.3))` has `dist2` in uv² (~(d·radius/192)²) over `radius²` → ≈ exp(-d²/11000) ≈ 1: the kernel is a **flat sparse box** of 9×9 taps spaced `radius` texels, so the footprint is resolution-dependent (21 % of frame at 192 px, 7 % at 576 px) and ghosts into a lattice. | code reading; 576 px render is nearly a smooth blur vs 192 px diamonds |
| H4 | spectral-bleed-confine | `diffuseChannel` re-runs 2 Sobels (18 taps) per call although `main` already has all three Sobels → 54 redundant taps of ~327. History read uses the filtering `u_sampler` on `dataTextureC`; alpha hard 1.0; HDR glow written unclamped to A (feedback of HDR, no ACES). Banner promises "anisotropic diffusion with channel-dependent diffusion tensors" but the kernel is isotropic. | code reading |
| H5 | chroma-kinetic | Spring in `extraBuffer[133..138]` is dead (zeroed every frame): `springVel` is always 0 → the flick-strength bonus (`min(springSpeed*3,0.4)`) is dead; the centre is the raw cursor. `sectorVoice = plasmaBuffer[1..8].x*0.25` is always 0 (plasmaBuffer[1..] never uploaded). The "velocity" is radial-from-centre (`rotDir`), never the cursor's motion, so "R leads, B lags based on motion direction" is not implemented. | code reading; `ck_head_hi.png` is a pure radial fringe |
| H6 | magnetic-chroma | Healthy. N/S pair, RK2 per-channel smear and compass hue all behave; idle cursor (0.5,0.5) gives a stable look. The three existing ideas stay. Note the R/B chromatic offsets are fixed ±x shifts. | mc_head_hi.png |

---

## RESCUES (separate from ideas; default look changes — recorded with meanL/stdL in NOTES)

**spectral-bleed-confine**
- **R1** time-driven `bleedRate` → constant `0.4` (the value the author's own 0.1–0.7 mapping gives at the mid slider). Removes the unbounded time growth (H1).
- **R2** make confinement real (H2): per-tap joint-bilateral wall on the *other two channels* (`exp(-confinement·K·Δothers)`, taps already carry rgb → zero extra fetches). `zoom_config.w` (mouse held) keeps the HEAD mapping 0.5 → 3.5 and now actually tightens the bottle while held; idle value is unchanged from HEAD. Dead `confField`, redundant Sobels and the loop-invariant `confFactor` are removed (H4); the Sobel gradients from `main` are passed in.
- **R3** tap envelope restored as a tap-space Gaussian (H3), σ = 3.5 taps along the edge tangent. Tap spacing stays `radius` texels (resolution dependence of the footprint is HEAD's and is noted as an open item, not changed).
- **R4** floor: history via exact `textureLoad`; ACES on display RGB; A = display RGBA (so feedback decode is trivial: history is display-referred and the new frame is tone-mapped before the 0.3 mix); alpha semantic (photo coverage 0.8, edge/halo 1.0) instead of hard 1.0.

**chroma-kinetic**
- **R5** dead spring → real sprung centre in two A texels (scheme in COMMON): texel (0,0) = (pos.xy, vel.xy) of a critically-damped ω=10 follower, texel (1,0) = (fract(lastTime), 0, 0, 0.7371). At an idle cursor pos = cursor, vel = 0 → default look identical to HEAD's idle centre. HEAD's flick bonus now fires for real.
- **R6** dead per-sector FFT voices (`plasmaBuffer[1..8]`) removed (they were always 0, so the mixes lose nothing); the `bass/mids/treble` mixes stay.

(magnetic-chroma: no rescue needed.)

---

## Idea Cards

```
SHADER: spectral-bleed-confine
IDENTITY (one sentence): per-channel colour that leaks outward from edges and is held back by the other channels' edges — plasma in a magnetic bottle with a pulsing boundary glow.
KEEP VERBATIM: 4 params and roles (Diffusion Radius → tap spacing, Field Intensity → glow gain, Channel Bias → which channel bleeds widest [biasR/G/B], Pulse Speed → radius pulse + glow phase); per-channel Sobel; per-channel diffusion with 9×9 sparse taps; edgeMask smoothstep(0.02,0.15); depth-scaled radius; Fresnel-like boundary gate (`fresnelGlow` smoothsteps + 120° phase offsets + 1.0/0.8/1.2 tints); click ripple hue bursts; 0.3 history mix; zoom_config.w hold → confinement 0.5 ↔ 3.5.
ADD (2 native ideas + R2 restoration):
  1. Tangent-aligned bleed tensor — Di Zenzo colour structure tensor J = Σ_c g_c g_cᵀ from the three Sobel gradients `main` already computes (§12.2A structure-tensor orientation: θ = ½ atan2(2Jxy, Jxx−Jyy), coherence = (λ1−λ2)/(λ1+λ2)). Each channel's kernel is a 2-D Gaussian in the edge frame: wide along the tangent (σ_t) and narrowed across it (σ_n = σ_t·mix(1, 0.25, aniso·smoothstep(0.02,0.3,own edge))). Magnetised plasma diffuses along field lines ≫ across them; this is the "anisotropic diffusion with channel-dependent tensors" the banner already claims. Flat areas (aniso 0) stay isotropic.
  2. Reflection halo that moves energy (§12.2F energy-conserving bloom) — ρ_c = rejected fraction of channel c's kernel mass at the confinement wall (from R2's weights). The existing `fresnelGlow` is scaled by (0.4 + 1.2ρ) and the bled colour under it is depleted: `out = res·(1 − 0.6·g) + g`, so the rim glows because the interior gave energy to it instead of the glow being invented.
FORBID on this file: spring cursor, IQ palettes, hologram scanlines, a new audio layer, any change to the Fresnel phase offsets, changing params.
A PACKING: display RGBA (ACES) — HEAD stored unclamped HDR colour with alpha 1.0; says so.
```

```
SHADER: chroma-kinetic
IDENTITY (one sentence): cursor-centred velocity chromatic aberration — red leads, blue lags — with a directional smear and bass-driven split.
KEEP VERBATIM: 4 params and roles (Distortion Str → strength ×0.1·bass_env·depth; Effect Radius → smoothstep falloff; Luma Influence → modFactor; Direction Rot → rotation of the radial direction); radial `velocity` field; R/G/B lead/lag taps; 3-tap smear with (1−t) weights; click kinetic bursts (ripples); bass_env; bass/mids/treble mixes; ACES (the RRT/ODT fit it already has); A = RGBA before ACES (HEAD packing, C not read).
ADD (2 native ideas + R5/R6):
  1. Motion-aligned lead/lag — the A-texel sprung centre's real velocity (uv/s, hence "kinetic") is added to the field: `velocity += springVel·(0.03 + 0.1·strength)·falloff·modFactor`. R leads along the direction of travel, B lags, and the smear trails behind — as the JSON description already says. Smear length rides the same vector so a flick smears further. Zero at an idle cursor.
  2. Cauchy spectral fringe (§12.2F Cauchy dispersion) — replace the three discrete R/G/B taps with five wavelength taps (660/600/550/500/450 nm). Tap offsets sit at their Cauchy fractions `(B/λ²−B/λ_R²)/(B/λ_B²−B/λ_R²)`, calibrated so the R and B channel centroids land exactly on HEAD's −lead / +lag and G on its Cauchy position (−0.35 instead of the arbitrary −0.5). Three ghost copies become a continuous, non-linearly-spaced rainbow fringe.
FORBID on this file: IQ palette, ripple-ring overlays beyond the existing click bursts, a second distortion field, new params, springs left in extraBuffer.
A PACKING: RGBA before ACES (HEAD) in all pixels except texels (0,0)/(1,0), which carry the sprung-centre state (sentinel w = 0.7371); said in the header.
```

```
SHADER: magnetic-chroma
IDENTITY (one sentence): the photo bent along magnetic field lines around an N/S pole pair at the cursor — per-channel RK2 streak, compass hue, neon core.
KEEP VERBATIM: 4 params and roles; per-channel RK2 field-line smear (4 sub-steps, per-channel dt divergence); true N/S pole pair with slowly turning axis; compass hue (field angle → hue wheel); hue warp/saturation boost; neon + bloom terms; ACES; A = raw field record (fieldStrength, influence, chromaticSep, alpha); depth relief. Existing Ideas line kept, new ideas appended.
ADD (2 native ideas, no §12.2 row):
  4. Lorentz gyration of the R/B streamlines — opposite "charges" curve opposite ways: each RK2 step's field vector is rotated by ±θ (R +θ, B −θ, G 0), θ = Chromatic slider × 1.2 rad. The channels fan out into spirals around the poles instead of only being offset in x. Kernel-deepening (tactic 2: the first-order side effect of charged streaks in a B field).
  5. Iron filings — a jittered needle per 0.028 aspect-space cell, oriented along the *same* `magnetic_field()` evaluated at the needle's centre (so it is consistent with the RK2 smear by construction), dark metallic needles fading in with `influence`/`highField` (tactic 5: the device artefact every magnetism demo shows). They darken the compass-hue image; neon/bloom ride on top.
FORBID on this file: ripple shockwaves, springs, IQ palettes, a second pole pair, changing the sign convention of the field, reusing the iron needles as a generic grain.
A PACKING: raw field record (HEAD) — unchanged; C not read.
```

## Mechanism interrogation (§12.1)

**spectral-bleed-confine**
- Tactic 1 (deepen the kernel): Gaussian-in-name box → anisotropic edge-frame Gaussian × joint-bilateral wall. The wall needs the other channels' values *at the tap*, which the tap already fetched (`s.rgb`) — that is why confinement can be real at zero fetch cost.
- Tactic 2 (physics one step further): a confined plasma diffuses along B ≫ across B (D∥/D⊥ ≫ 1) and reflects at a magnetic wall → idea 1 and the reflection fraction of idea 2.
- Tactic 3 (promote an intermediate): the three Sobel *vectors* were collapsed to lengths. Their outer products give the Di Zenzo tensor; the rejected kernel mass Σ(g)−Σ(g·wall) was thrown away by the cancelling normalisation and becomes ρ.
- Tactic 6 (history it owns): C was read as colour (0.3 mix) but through a filtering sampler; A stored HDR. Now A = display RGBA and C is read exact, so the 0.3 mix is display-to-display.
- Same-noun test: "tensor", "field", "wall", "reflection", "bottle" — all in the banner already. Deletion test: remove either idea → still the bleed/confine effect; keep only the tensor without the bleed → just an edge-aligned blur, not this effect. ✔ Expert test: a plasma physicist would say anisotropic transport + reflection at a mirror boundary is right.

**chroma-kinetic**
- Tactic 1: three discrete taps → five-tap spectral integration of the same dispersion law.
- Tactic 2: lateral CA of a real lens is non-linear in wavelength (Cauchy) and, on a moving subject, the colour fringe leads/trails along the motion (rolling the exposure).
- Tactic 3: `springSpeed`/`springVel` were computed and always 0; `dispersion = |velocity|/strength` already exists for alpha and now also reports motion.
- Tactic 6: A is not read as colour (C unread), so two state texels cost nothing visible; the sentinel/`fract(time)` scheme keeps rgba16float honest.
- Same-noun: velocity, lead/lag, smear, dispersion, wavelength — all native. Deletion: remove motion term → exactly HEAD's radial effect; remove spectral → HEAD's 3-tap look. Neither replaces the mechanism. ✔

**magnetic-chroma**
- Tactic 2: charged particles in B gyrate with opposite sense for opposite charge (idea 4); the field is visualised by iron filings (idea 5).
- Tactic 3: `fHere = magnetic_field(...)` (compass hue) is already evaluated per pixel; filings reuse the same function at cell centres.
- Tactic 6: n/a (A raw field record, C unread).
- Same-noun: Lorentz, filings, field, pole — all magnetism. Deletion: remove either → still magnetic chroma; keep only filings (without the RK2 chroma smear) → a different (plain field-plot) effect. ✔

## §12.2 row ledger for Fork B
- Structure-tensor orientation (A): spectral-bleed-confine (+ fabric-step-gabor in Fork A) — 2 files.
- Energy-conserving bloom (F): spectral-bleed-confine (+ vaporwave in Fork D) — 2 files.
- Cauchy dispersion (F): chroma-kinetic (+ data-stream-spectral in Fork D) — 2 files.
- Not §12.2 rows: Lorentz gyration, iron filings, joint-bilateral confinement walls, motion-aligned lead/lag.

---

## Implementation revisions (made after measuring; the cards above are the pre-WGSL plan)

1. **spectral-bleed-confine idea 1 — pinch → stretch.** The card said "narrow σ_n across the edge". First implementation (σ_n = σ_t·mix(1, 0.25, aniso·edge)) changed 221 px >8/255 at default and 69 px at Diffusion Radius 1: invisible, because the cross-channel wall (R2) already stops bleed across a sharp edge, so narrowing across is redundant. Reworked to the other half of D∥ ≫ D⊥: the tap lattice is rotated into the edge frame and the tangent axis is stretched by `1 + STRETCH·aniso·smoothstep(0.01,0.15,own edge)` (STRETCH = 1.5), across-reach unchanged. Now 1,178 px >8/255 (3.2 %) at default, 9,743 px >2/255. Same row (§12.2A structure-tensor orientation), same Di Zenzo tensor.
2. **magnetic-chroma idea 5 — uniform dashes → jittered filings.** First version read as a regular quiver plot. Added per-cell angle jitter (±10°), length jitter, presence jitter (~70 % of cells) and thinner needles; cell size floored to 7 px so 192 px canvases do not turn into dots.
3. **chroma-kinetic**: no revision.
