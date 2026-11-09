# BRIEFS — Fork A (sonnet/batch-25): glass-bead-curtain (1st, non-compiling), glass-bead-curtain-iridescence (1st), chroma-lens-iridescence (1st)

Written 2026-11-09 BEFORE any WGSL edit. HEAD renders: scratchpad/forkA/{gbc,gbi,cli}_head_{192,576}_{idle,held}.png (gbc = scratch copy with `target`→`tgt` ONLY, to see the intent; in minirender extraBuffer persists so its spring looks alive — judged by reading).
Shared A-texel state scheme (all three): texel (0,0) = state, texel (1,0) = (fract(lastTime), …, 0.7371 sentinel); C reads masked on those two texels; dt = clamp(fract(time − st1.x), 0.001, 0.05); f16 rest-snap on every cursor spring. A = final ACES display RGBA everywhere else (HEAD packing unchanged; C is read as colour ghost).

---------------------------------------------------------------------------------------------------
## 1. glass-bead-curtain  (does not compile at HEAD: `let target` reserved)

### HEAD observation (compile-fixed scratch copy, 192/576, idle/held)
Every bead is a half-dark "bowl": `viewDir = vec2(0,1)` and `normal` are 2-D, so `cosTheta = max(0, normal.y)` is 0 on the whole upper half of every bead → Fresnel ≡ 1 there (×0.5 darkening, no spec) and ≈ 0.04 below. The picture is dark (meanL 0.30, meanA 0.28 vs ≈0.5 for the sibling glass shaders). No bead has a Fresnel rim. Swayed beads (|sway| up to 0.22 cell with bass) are clipped by their own cell border (the bead is drawn from the pixel's own cell only). Click ripples are dead (`if (r.w > 0.0)`, ripples[i].w is always 0), `rippleNormal*1.5*beadCount` would be ~28× too strong if revived. `mouseDelta = beadCenter/beadCount − mouse` mixes aspect-scaled curtain units with plain uv. The (0,0) "spring" (target = any ripple alive) is zeroed every frame: `springState` ≈ 0 → `mousePull` (the "held-pointer pull") is dead, and the comment lies (never reads zoom_config.w).

### Idea Card
```
SHADER: glass-bead-curtain
IDENTITY: a hanging curtain of glass beads over the photo — swaying with bass, parted/tilted by the cursor, each bead a little ball lens with Fresnel rim, caustic focus, tinted SSS glow, sparkle
KEEP VERBATIM: 4 params + roles (size → bead count, refraction → offset strength, tension → pull/tilt toward cursor, glass_density → absorption/SSS/alpha density); depth-scaled bead count; bass wind sway + neighbour collision + vertical coupling; per-channel (1.0/.97/.94) + treble refraction offsets; caustic focus/pattern/ring; SSS colour pair; envReflect; sparkle; semantic alpha; ACES; A = display RGBA with 2 % C ghost; depth out.
MECHANISM INTERROGATION (§12.1):
  tactic 2 (physics one step further): a glass ball lens throws its focus on the side AWAY from the light and focuses blue nearer than red (longitudinal chromatic aberration); the beads are STRUNG — a technician sees the thread through the bore and between beads; a walker pushes beads in the direction of travel and they swing back.
  tactic 3 (promote an intermediate): `beadLocal` and the light dir already exist (the caustic uses beadLocal centred on the bead) — shifting the focus centre and giving it per-channel radii is two multiplies; `beadLocal.x` is the string axis (bead centre) — the thread is `|beadLocal.x| < w`; the cursor spring (rescue) already yields a real velocity for the wake.
  tactic 6 (history): C stays the 2 % colour ghost; the new A-texel state carries only the cursor spring + held-pull spring.
ADD (3 native ideas):
  1. String through the bore — a thin smoky thread runs vertically through every bead centre column, visible through the glass (wider, refracted-looking inside beads) and as a hanging line in the gaps between beads. Follows each bead's sway because it lives in `beadLocal`.
  2. Off-axis chromatic focal spot — the caustic focus moves to the far side of the bead from the light (−L.xy) and each channel gets its own focal radius (R widest … B tightest) → a rainbow-edged hot spot, as a real ball lens shows (JSON promises "chromatic caustics"; HEAD only has a white-blue spot).
  3. Swing wake — the (rescued) cursor spring's velocity drags the beads near the cursor along the direction of travel; the lagging spring lets them swing back (pendulum feel), strength rides the existing `tension` slider.
FORMULA ADMISSION: no §12.2 table row needed — all three are tactic-derived and consume `beadLocal`, the light vector, and the rescued spring velocity that the file already owns/intends. (No HG / Fresnel row used; Fresnel already present.) Deletion test: remove any → still a lit glass-bead curtain; thread alone is not.
FORBID on this file: IQ palette, ripple shockwave stamp beyond the bead-normal ripples it already has, springs beyond cursor + held-pull, holographic scan, any new param, replacing the lattice.
A PACKING: ACES display RGBA (unchanged); texels (0,0),(1,0) = spring state.
```
### RESCUE list
- R1 compile: `target` → removed with the old spring block.
- R2 2-D normal / 2-D view vector → real 3-D sphere normal `(2·beadLocal + tilt, sqrt(1−|2·beadLocal|²))`, Fresnel from `n.z`, Blinn glint without the stray `*fresnel`, ball-lens refraction offset `−n.xy`. Default look change: expected and large (meanL/stdL/meanA reported in NOTES).
- R3 dead ripples (`r.w`) → `age = time − r.z`, bounded; ripple normal weight recalibrated to bead units (0.35 instead of 1.5·beadCount).
- R4 dead pull spring → held/ripple-alive target spring in A texel (ω≈10, ζ 0.6 = HEAD's 100/12).
- R5 `mouseDelta` aspect/unit mismatch → distances in aspect-corrected uv, pull converted to bead units with aspect.
- R6 sway clipping at cell borders → nearest displaced bead over the 3 horizontal neighbour cells.

---------------------------------------------------------------------------------------------------
## 2. glass-bead-curtain-iridescence

### HEAD observation
Healthy picture: pixel-lattice beads (`beadSize` 15–80 px) parted radially by the cursor (`curtainPart`), thin-film colour only in a rim ring (film weight = Schlick fresnel × iridescence × 0.65, fresnel ≈ 0.045 at the bead centre → ~0.03; the body is plain grey glass). At the exact cursor pixel `normalize(distVec+1e-4)` is singular: a flower/star fold in the middle of the parting (visible in the 192/576 idle render at (0.5,0.5)). The "critically damped spring" in extraBuffer[133..138] is zeroed per frame: on the first-frame branch it collapses to the raw mouse (`sPos = rawMouse`), so the app behaves as raw cursor — benign but the spring is a lie; click ripples are alive (use `ripple.z`).

### Idea Card
```
SHADER: glass-bead-curtain-iridescence
IDENTITY: a lattice of glass beads over the photo, each bead a spherical lens with Beer–Lambert transmission and a thin-film (soap-bubble) rainbow rim, parted by the cursor
KEEP VERBATIM: 4 params + roles (bead_size → lattice pitch px, refraction → offset, iridescence → film amount, film_thickness → thickness base); thinFilmColor 13-wavelength loop, filmIOR 1.48, per-bead filmNoise; Beer–Lambert glassColor transmission; Schlick fresnel; dome spec; rim shadow; gap backdrop shadow; click ripple dispersion; bass/mids/treble modulators; C ghost 15 % in beads + 6 % persistence; ACES; alpha semantics; A = display RGBA.
MECHANISM INTERROGATION (§12.1):
  tactic 2: a real film drains — thicker at the bottom, thinner at the top — so a bubble/bead shows horizontal interference BANDS, not one flat colour per bead; the film also creeps (Marangoni).
  tactic 3: `cellUV` (bead-local, y down) is already computed and unused by the film (which uses only rCell) — the gradient is `cellUV.y`; `thinFilmColor` + `cellIndex` thickness hash already exist, so the gap rim reuses them at a grazing angle.
  tactic 5 (artifact of the real object): adjacent coated beads show each other's film at the contact rim; a curtain dragged by a hand swings and lags.
  tactic 6: A/C display history unchanged; only the cursor spring state is added (texels).
ADD (3 native ideas):
  1. Drained film wedge (thin-film phase, §12.2F extension of the existing film) — thickness × (1 + 0.8·cellUV.y) with a slow per-bead creep → 2–3 interference bands down every bead; film mix gets a small floor so the body is visibly iridescent (HEAD: only the rim ring).
  2. Inter-bead contact fringe — in the gap branch, a grazing-angle film colour of the nearest bead (`thinFilmColor(thick, 0.18, 1.48)`) hugs the bead rim and fades with `gapDist`, replacing the plain dark gap shadow's flatness.
  3. Swing wake — the restored cursor spring's velocity adds a drag along the direction of travel to `curtainPart` (clamped), the critically-damped lag lets the parted beads swing back.
FORMULA ADMISSION: Thin-film phase row (extension only, on this file and chroma-lens-iridescence — within the ≤2 budget). 2 and 3 are tactic-derived. Row not used: bloom (optional, skipped).
FORBID on this file: Cauchy, Snell, Airy, ghosts, IQ palette, shockwave stamp, new params, a second film sampler for the beads.
A PACKING: ACES display RGBA (unchanged); texels (0,0),(1,0) = cursor spring state.
```
### RESCUE list
- R1 spring: extraBuffer spring (zeroed per frame, = raw mouse in practice) → A-texel critically damped spring (ω 6, HEAD's 36/12), f16 rest-snap; idle cursor at rest ⇒ identical centre to HEAD.
- R2 singular parting: `normalize(0)` fold at the cursor → displacement ramps in with `smoothstep(0, 0.25, r)` (monotone map, no fold). Default look changes in the cursor core only; measured in NOTES.

---------------------------------------------------------------------------------------------------
## 3. chroma-lens-iridescence

### HEAD observation
In minirender the lens orbits a Lissajous (target = orbit unless the button is held; held ⇒ follows the cursor) — persistent extraBuffer. In the app extraBuffer[133..138] is re-uploaded zero every frame and written by one thread: other threads read (0,0) / nondeterministic → lens parked in the corner. `clickImpulse` (extraBuffer[138]) is likewise dead. The iridescence is INVISIBLE: film weight `fresnel·0.65·(1−0.8·ndist)` with `cosTheta = sqrt(1 − |uv−0.5|²·0.5)` (SCREEN-centred angle, ∈[0.87,1]) gives fresnel ≤ 0.0066 → mix ≤ 0.4 %. Thickness noise is `hash12(uv*12 + time*0.1)` = per-pixel white noise that re-randomises every frame (boiling grain once the film is visible). Aberration is a symmetric ±abb (R and B equally far from G).

### Idea Card
```
SHADER: chroma-lens-iridescence
IDENTITY: a magnifying glass lens (quadratic bulge) with radial chromatic aberration, a bright bevel rim and a thin-film iridescent bevel, on the photo
KEEP VERBATIM: 4 params + roles/double duties (x magnification; y aberration; z lens radius AND film thickness base; w iridescence strength AND edge blur); quadratic lens profile `1 − (1−n²)·mag`; R/G/B per-channel sampling around G; film colour via thinFilmColor (390–690 nm, 8 taps, filmIOR 1.45); rim highlight ring; 10 % C feedback; click ripple distortion; orbit/held lens behaviour; semantic alpha; ACES; A = display RGBA.
MECHANISM INTERROGATION (§12.1):
  tactic 1 (deepen the kernel): the symmetric ±abb offset approximates dispersion; the next approximation is n(λ)=A+B/λ² — blue deviates 1.7× more than red from green.
  tactic 2: film on a curved bevel is thicker where it pools at the rim (meniscus) → concentric fringes, and its viewing angle is the LENS surface normal, not the screen centre; a glass lens also throws a faint inverted internal-reflection ghost of bright highlights through its centre.
  tactic 3: `ndist` (lens-normalised radius) is already computed — the lens-cap angle is `cosθ = sqrt(1 − ndist²)`, the wedge is `ndist²`; `color` samples already hold the bright pixels the ghost reuses.
  tactic 6: C feedback unchanged; A-texel state = sprung lens centre.
ADD (3 native ideas):
  1. Cauchy dispersion (§12.2F) — R/B deviations from G follow n(λ)=A+B/λ² at 650/550/450 nm, normalised so the mean |dev| equals HEAD's ±abb anchors (G stays on the lens curve). Blue fringe ≈ 1.27·abb, red ≈ 0.73·abb.
  2. Meniscus film wedge (thin-film phase, §12.2F extension) — thickness × (1 + 0.55·ndist²) (film pools toward the bevel) + lens-centred viewing angle ⇒ concentric Newton-like fringes on the bevel; thickness noise → smooth value noise.
  3. Internal-reflection ghost (lens-flare ghost, §12.2F; this is the batch's single Airy/ghost use) — a faint inverted, 0.55-scaled copy of the source highlights (luma > 0.55) mirrored through the lens centre, strongest at the middle, fading to the rim, warm-tinted.
FORMULA ADMISSION: Cauchy row (chroma-lens + crystalline-shatter only); thin-film extension (this + bead-iridescence); ghost row (one file in batch, tell coordinator). Each consumes quantities already computed (ndist, lensCurve, color taps, smoothMouse). Brown–Conrady / Fresnel row not needed (R2 is a rescue using the HEAD exponent 2.5).
FORBID on this file: bead lattice, Airy rings stamped on screen, IQ palette, shockwave stamp, new params, changing the quadratic profile or the orbit.
A PACKING: ACES display RGBA (unchanged); texels (0,0),(1,0) = lens spring state.
```
### RESCUE list
- R1 lens position: racy extraBuffer → A-texel spring; orbit target when not held, cursor while held (HEAD semantics); time-based spring (ω 14, ζ 0.5) replacing the frame-rate-bound 0.18/0.82 pair (which was ζ≈0.25, ωn≈24 rad/s at 60 fps — overshoots 44 %).
- R2 film invisible → lens-centred angle `cosθ = sqrt(1 − ndist²)`, HEAD exponent 2.5 kept, plus a 16 % body floor in the mix (default look changes: iridescent bevel now visible).
- R3 click impulse (`extraBuffer[138]`, dead) → derived statelessly from the newest ripple's age, `exp(−3.7·age)` (≈ HEAD's 0.94/frame).
- R4 white-noise thickness → smooth value noise.
