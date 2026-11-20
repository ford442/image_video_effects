# BRIEFS — fork A (sonnet/batch-46): gravitational-lensing-nlm, distortion-gravitational-prismatic

Written BEFORE any WGSL edit. HEAD = origin/main 673d780a (+ coordinator's header-only `_prelude.wgsl` migration).
Reserved rows honoured: **NLM kernel deepening → nlm only**, **Cauchy dispersion → prismatic only**.

---------------------------------------------------------------------
## 1. gravitational-lensing-nlm   (first pass — no `Ideas:` line)

### HEAD read (what the file really does)
- Schwarzschild-ish geodesic march (96 steps, `accel = -M/r²`, step `DT*r*0.5`) from an orbiting camera at r=20; escape → panorama lookup of `readTexture` (`atan2` azimuth, `rd.y` elevation); horizon hit → black + depth 0.
- Flat accretion disk (`renderAccretionDisk`) intersected with the **un-bent** ray `(ro, rd)` and added after the march. Doppler beaming `pow(1+doppler,3)`, 3-tier temperature colour, `smoothstep` rim.
- Einstein-ring glow `ringScreenR` (broad soft annulus), gravitational redshift tint, cursor point-mass (spring cursor; extraBuffer[133..138] is zeroed per frame so the spring is a no-op and `mouse = rawMouse`, harmless).
- NLM: 24 neighbours in a 5×5 window, 3×3 patch SSD of `readTexture` around **screen uv** (the UN-lensed source), `exp(-pd/0.015)`, lensed colour joins as weight 1, then `mix(nlm, lensed, 0.65+held*0.25)`, 7 % exact-C persistence, ACES, alpha = importance (1 − avgSimilarity + ring + held).
- A = ACES display RGBA, C read as colour (exact `textureLoad`) → consistent; no packing lie.

### HEAD defects → rescues
- **R1 upside-down world.** `up * uvRaw.y` with `uvRaw.y` growing downward puts world-down at the screen top; the flat disk "floor" renders as a ceiling (verified: top half of the 384² render is the saturated disk, sky below). The panorama lookup cancels the flip (`bgUV.y = rd.y*0.5+0.5`), so the photo is upright while the disk is inverted. Fix: `up * -uvRaw.y`, `bgUV.y = 0.5 - rd.y*0.5` (photo stays upright), and `cursorPos3D.y` negated so the cursor lens stays under the pointer. Shadow position / panorama / sliders unchanged; only the disk goes floor-side down.
- No dead sliders (x,y,z,w all read), audio from `plasmaBuffer[0].xyz` ✓, no `pow` negative base, no negative into ACES (colour ≥ 0).
- Not touched (documented only): disk annulus (2.8–14 rs) contains the camera at r=20 so half the frame is near-saturated disk at default mass — HEAD look, kept.

### Idea Card
```
SHADER: gravitational-lensing-nlm
IDENTITY: a black hole seen through a Schwarzschild-style geodesic march, blended with a non-local-means patch filter of the source photo.
KEEP VERBATIM: 4 params + roles (mass, disk brightness, camera orbit, redshift); geodesic march, DT, MAX_STEPS; renderAccretionDisk (flat primary disk, beaming); gravitationalRedshift; Einstein ring glow; cursor mass; 5×5 search window with 3×3 patch SSD and h=0.015; lensed colour as weight-1 sample; mix(nlm, lensed, 0.65+held*0.25); 7% exact C persistence; ACES display; A = display RGBA.
ADD:
  1. Buades-form NLM weights (§12.2 "non-local-means / patch-similarity kernel deepening", this file only): Gaussian-weighted patch distance (centre pixels count more, weights sum to 9 so h keeps its scale), noise-bias subtraction `max(pd − 2σ²·N, 0)` so near-identical patches reach weight 1, and the centre patch cached once (HEAD re-sampled it 24×) — 456 → 225 texture loads, which pays for everything else.
  2. Lensed second image of the accretion disk (tactic 2, physics one step further): during the march, detect the bent ray crossing the disk plane and add `renderAccretionDisk` emission there — the arch of the far side of the disk over/under the shadow. Strictly additive: first crossing only where HEAD's straight-ray disk was empty; later crossings (higher-order images) attenuated 0.55^n.
  3. Photon ring from the closest approach (tactic 3, promote `r` the march already computes — the "step-count AO" analogue): track min r; escaped rays that grazed the horizon get a thin hot ring `exp(-(rMin/horizon − 1)/0.18)`, so the shadow has a crisp lit rim.
FORBID: spring/ripple overlays beyond what exists, IQ palette, any change to the NLM window size, new params, Cauchy dispersion (reserved to prismatic), Einstein-ring magnification formula (fork B).
A PACKING: display RGBA (ACES), unchanged.
```
### §12.1 mechanism interrogation
- Tactic 1 (kernel): NLM approximates "average over patches that look alike". Next-better form of the *same* operator = Buades' weights: Gaussian patch kernel + noise-variance subtraction. Not a different filter.
- Tactic 2 (physics one step further): a lensed disk's first-order side effect is the secondary image of the far side arching over the shadow; a Schwarzschild march that draws the disk with an un-bent ray is missing precisely that.
- Tactic 3 (promoted intermediate): `r` is computed every step and thrown away — its minimum is the periapsis → photon ring; the bent `rayPos`/`rayDir` already exist → plane crossing.
- Tactic 6 (history): C is read as colour at 7 %; keep. (No extra continuity needed.)
### §12.4 admission
- Idea 1: NLM family row (reserved). Consumes taps the kernel already fetches (cached). Deletion test both ways ✓ (still NLM; NLM alone is still not a black hole).
- Idea 2: consumes `rayPos/rayDir` + the file's own `renderAccretionDisk`; no new state; family = raymarched SDF/optical (a black-hole disk **is** an emitter seen through the metric). Delete it → HEAD. Keep only it → not this effect (no NLM, no lens).
- Idea 3: consumes `r` (§12.1 tactic 3, §12.2E step-count-AO analogue). No new state.

---------------------------------------------------------------------
## 2. distortion-gravitational-prismatic   (first pass — no `Ideas:` line)

### HEAD read
- Up to 5 point masses (primary = pointer, others orbit it), deflection `mass·radius/dist` toward the mass, 50 ripple deflection waves from `u.ripples` (`.z` = birth time ✓, not `.w`), 4 bands (450/520/600/680 nm) with `cauchyIOR(λ,1.5,B)`, per-band `deflectScale = 1+(n−1.5)·2`, `sourcePos = uv − defl·0.5·scale`, band intensity `dot(sample, wl2rgb(λ))`, accumulate `wl2rgb·bandIntensity`.
- 2-D accretion disk annulus around the primary (4-tier colour, swirl `sin(atan2·20+t·2)`), "Einstein ring" glow, redshift tint, 8 % exact-C persistence, ACES, alpha semantic. A = ACES display RGBA, consistent.

### HEAD defects → rescues
- **R1 red cast / energy.** The 4-band accumulation is not normalised: a neutral source comes out ≈(3.0,1.16,1.05)× — measured with a flat 0.6 grey source: sRGB (229,182,178). White is not preserved. Fix: divide by the same per-channel basis sum accumulated in the loop (`Σ wl·dot(wl,1)`), so a neutral pixel stays neutral at any dispersion.
- **R2 Einstein "ring" is a dot.** `einsteinRadius(mass, distPrimary)` multiplies by the *pixel's own* distance, so `|dist − 0.14·dist| < 0.02` holds only for dist < ~0.025: a glow blob at the mass, not a ring. The intended lens-plane scale is constant; `sqrt(mass)·0.1·sqrt(lensStrength)` equals θE of the file's own deflection law (θE² = ½·mass·radius = 0.01·mass·lens). Fix: pass `sqrt(lensStrength)` instead of `distPrimary`.
- Dead sliders none (x,y,z,w all read); audio indexed ✓; no `pow` negative base (`innerRadius/radius` with radius>inner inside branch); no negative into ACES.
- **Not touched, flagged for the user:** deflection sign is *diverging* (`source = pos + n̂·|α|/2`, a negative-mass lens: no inversion/ring caustic). Flipping it would be a different look; left as is.

### Idea Card
```
SHADER: distortion-gravitational-prismatic
IDENTITY: point-mass gravitational lens (+ orbiting masses, click ripples) whose background is split into a Cauchy rainbow, with an accretion-disk annulus and ring glow at the pointer.
KEEP VERBATIM: 4 params + roles (lens strength, mass count, disk intensity, Cauchy dispersion); deflectionAngle law; mass layout; ripple deflection; cauchyIOR(λ,1.5,B) with B from the dispersion slider; wavelengthToRGB tint basis and projection `wl·dot(sample,wl)`; the original 4 wavelengths 450/520/600/680; deflectScale formula; accretionDiskColor tiers + swirl; redshift tint; 8% C persistence; ACES; A = display RGBA.
ADD:
  1. Dense, energy-normalised Cauchy spectrum (§12.2F "Cauchy dispersion", this file only): the 4 bands become 7 (450, 485, 520, 560, 600, 640, 680 — HEAD's four plus three interleaved) so a strong dispersion setting smears into a continuous spectrum instead of 4 coloured ghost copies; accumulated basis sum normalises the result (the R1 rescue lives here).
  2. Spectral Einstein ring (same row, applied to the ring): θE² ∝ deflectScale, so each band's ring sits at `θE·sqrt(deflectScale_λ)` — blue ring outside, red inside, a rainbow annulus (this replaces the single time-cycled ring colour; a per-band phase shimmer keeps the time-cycling). Ring radius itself is the R2 rescue.
FORBID: NLM / patch filters (nlm file), Einstein magnification μ / convergence-shear (fork B), new params, spring/ripple overlays beyond the HEAD ripples, IQ palette.
A PACKING: display RGBA (ACES), unchanged.
```
### §12.1 mechanism interrogation
- Tactic 1: 4 point samples of a continuous spectrum → 7 (same operator, finer Riemann sum) + normalisation.
- Tactic 2: gravity bends all colours equally but this file's lens is a prismatic one (n(λ)); the first-order side effect of chromatic deflection on a *ring* is that the ring radius is wavelength-dependent (θE ∝ √deflection).
- Tactic 3: `deflectScale` per band is computed and used only for the sample offset → reuse for the ring radius; `ringGlow` already drives alpha.
- Tactic 6: C is colour history at 8 %; nothing to add.
### §12.4 admission
- Both ideas are the Cauchy row (reserved to this file) consuming `cauchyIOR`/`deflectScale`/`wavelengthToRGB` that exist; no new state/binding/spring. Deletion test: removing either leaves this effect (HEAD); keeping only them (no lens) is not this effect.
- Batch de-dup: the same row twice inside one file is allowed (the row is this file's theme); cross-file the row appears nowhere else.


---------------------------------------------------------------------
## 3. Addendum — cards revised AFTER first renders (card edits are recorded, not silent)

**gravitational-lensing-nlm — Idea 2 replaced.** Ablation render (flat 0.35 source, orbit 0.3): the "lensed second image of the disk" changed **0 pixels**. Cause: the file's own force law integrates to α = π·M/b² (accel `M/r²`, step `DT·r·0.5` → dDir/ds = 2M/r³), so bending is only strong for b ≲ 8 while the flat disk starts at 2.8·rs = 11.2 and the camera sits at r = 20: the bent ray never reaches the annulus. Dropped (code removed). Replaced by:
  2'. **Disk g-factor** (tactic 2, physics one step further; `gravitationalRedshift()` already existed but was only applied to the far background at r = 45, so the Redshift slider did almost nothing): inside `renderAccretionDisk`, emission is dimmed ∝ g³ and tinted by `gravitationalRedshift(r)` with g = sqrt(1 − rs/r), blended by the Redshift slider (slider 0 → HEAD disk exactly). Beaming was only the Doppler half of the g-factor. Admission: consumes `distFromCenter`, `mass`, the existing helper, and the existing slider; no state. Ablation: 38 % of pixels change (max 24/255), disk warmer/dimmer toward the inner edge.
  3. Photon ring: e-fold narrowed to 0.05·horizon (first value 0.18 produced a broad halo covering 25 % of pixels).

**distortion-gravitational-prismatic — projection changed.** HEAD's `wl·dot(sample, wl)` projection cross-mixes channels (a pure-red source leaves as orange: (0.85,0.36,0.04) even with the red cast divided out), so normalising only the white point is not enough. Per-channel form `Σ wl·sample / Σ wl` is identity at zero dispersion and keeps `wavelengthToRGB`, `cauchyIOR`, the four original wavelengths and `deflectScale` verbatim. Flat 0.6 grey now (172,172,172) at every probed pixel (HEAD 229,182,178).
