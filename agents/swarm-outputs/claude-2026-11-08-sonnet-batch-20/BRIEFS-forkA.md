# sonnet/batch-20 — Fork A briefs (written BEFORE any WGSL edit)

Shaders: gen-grokcf-interference (file `gen_grokcf_interference.wgsl`), gen-void-harmonic-cymatic-resonator, gen-stellar-acoustic-resonance-manifold.
All three are 2nd/3rd passes (HEAD already has `Ideas:`). HEAD ideas are KEPT; the cards below only list what is NEW.
Baselines: scratchpad `base/<wgslname>.png` (rgb | over-white | alpha), minirender 192px/24f/t=2.0, JSON defaults, audio 0.3/0.2/0.1.
Test renderer: `agents/minirender_fa.mjs` = minirender_img + `RIP=x,y,t0[,..]` (injects clicks, sets config.y) + `FFT=v[,v..]` (fills extraBuffer[5..132] bins).

---------------------------------------------------------------------------------------------------
## SHADER: gen-grokcf-interference  (Bessel circular-drum Chladni modes)

IDENTITY: a vibrating circular membrane — J_m(α_mn r)·cos(mφ+φ0)·cos(ωt) modes picked by the audio bands, drawn as a hue-coded
displacement figure with gold/white Chladni node lines, overlaid on the source frame.
KEEP VERBATIM: J0–J3 polynomials; the 6-mode table (m, α_mn, ω=α/2, φ0, band weights) and modeCount gates; slider roles
(x radial scale only, y hue rotation, z node sharpness, w mode count); mouse re-centres the drum; Dirichlet rim + rim highlight;
HEAD Ideas (radial/azimuthal node tint, displacement Lambert, antinode disks, radial beat); ACES on display; A = (u_total, ·, φ/2π, blendAlpha).

### Mechanism interrogation (§12.1)
- tactic 2 (physics one step further): a plate under sand shows the *stationary* nodal figure because grains migrate to where the plate does
  not move; and a mallet hit excites each eigenmode in proportion to that mode's shape at the strike point (the membrane's impulse response).
- tactic 3 (promote an intermediate): `u_total` is computed every frame and the A.g channel (`r`) is written but never read → a free slot for
  a history of |u|. `drumMode()` at t=0 is the pure mode shape S_mn — usable at the strike point.
- tactic 6 (history the shader owns): C.r is already the damped displacement; C.g can carry the leaky vibration energy.

### Diagnosis — visibility rescue (HEAD is dim; reason found, not guessed)
 1. `fftModeWeight()` reads `plasmaBuffer[1..8].x` as FFT bins. Only `plasmaBuffer[0]` is ever uploaded (audioDepth.ts:62-70), so every
    mode weight is the constant 0.6 (a permanent −40% dim, and the "true cymatics" FFT selection claimed in the header never ran).
    Real bins are `extraBuffer[5 + bin]` (128 bins, normalised 0..1; EXTRA_BIN_OFFSET=5).  → read the real bins; floor 0.6→0.85.
 2. Click strikes are gated on `rp.w > 0.001`; ripples[i].w is padding (always 0) → clicks never struck the drum. → strength 1.
 3. `val = |u|·1.5` makes a silent drum cover only ~0.2 alpha on a photo (rendered over an image the figure is a barely visible ring).
    → perceptual (√) transfer on the displacement→brightness map; node lines stay dark/gold because |u|→0 there.
 4. uv is not aspect-corrected, so the "circular membrane" is an ellipse on any non-square canvas (and strike rings were elliptical). → aspect-correct p.

ADD (2 new native ideas):
 1. **Sand on the plate** — grains settle where the time-averaged |u| is low: C.g keeps a leaky average of |u_total| (A.g, was the write-only
    `r`), sand = exp(−k·E) with k from the existing node-sharpness slider, drawn as static 2-texel grains in warm tan, strongest on the stationary
    nodal figure; instantaneous zero crossings (HEAD gold line) keep moving, the sand does not. History is clamped + gated by previousValid
    (inherited C from another shader converges within ~30 frames; no NaN path).
 2. **Modal strike response** — a click excites every active mode k by S_k(hit)·S_k(p)·e^(−γ_k age)·cos(ω_k age) (γ_k grows with α_k: high modes die
    first). A strike at the centre only rings the radially-symmetric (0,n) modes; an off-centre strike also lights the azimuthal ones. HEAD's
    contact packet stays as the impact transient (it was dead because of `rp.w`).
FORBID: springs, IQ palettes, new params, any other overlay; changing hue/lambert/antinode/beat maths.
A PACKING (changes, stated): rgb ACES display in writeTexture; A = (u_total raw, leaky |u| energy (sand), φ/2π, blendAlpha) — `r` was write-only, so no reader changes.
FORMULA ROWS: none from §12.2 (tactic-derived).

---------------------------------------------------------------------------------------------------
## SHADER: gen-void-harmonic-cymatic-resonator  (raymarched 3-axis standing waves inside a sphere)

IDENTITY: a spherical cavity whose standing-wave pressure field is shown as luminous nodal membranes, mode-split seams, gold antinode bellies and a
Helmholtz throat ring, rotating slowly, driven by bass/mids/treble.
KEEP VERBATIM: standingWave/splitModes (primary+adjacent eigenmode crossfade), 5-octave disp, membrane SDF `|p|-thickness`, Frequency/Amplitude/Glow/Complexity
roles, nodal/seam/antinode/throat integrals, fresnel + fog, ACES display RGBA in A, 6 % history mix.

### Mechanism interrogation
- tactic 2: the lowest mode of a *spherical* cavity is the radial breathing mode j0(kr)=sin(kr)/(kr) — HEAD only has Cartesian product modes, so nothing ever
  breathes; the wall of a real resonator flexes with it. Bass is what drives it.
- tactic 3: HEAD already samples pressure at every nodal-integral step (`field.y`) and discards the *slope* between steps — that slope is exactly what a
  knife-edge schlieren image of a standing wave shows (compression vs rarefaction flank).
- tactic 6: A is display RGBA → no state idea; none added.

### Rescue (found by reading the camera)
 - `cu = cross(cw, up) = (−1,0,0)` and `cv=(0,1,0)` with texture-down = +uv.y put world-right on screen-left and world-up on screen-down (a 180° rotation).
   The mouse warp (`mouse_pos = (mx·2, −my·2)`) is therefore at the point-mirror of the cursor, and the key light (1,2,−1) lights from below. → rd built from (+x, −y) so the
   existing mouse mapping is correct and the image is upright. Pure orientation fix; no param/look change beyond that.

ADD (2 new native ideas):
 1. **Radial breathing mode (l=0 spherical Bessel)** — pressure += (0.16 + 0.5·bass)·amp·sinc(k r)·cos(ωt) with k tied to the Frequency slider; the wall radius flexes with the
    same phase (±0.05) so the limb visibly pulses with the kick. Sheets bend radially instead of staying a rigid Cartesian lattice.
 2. **Knife-edge schlieren nodal sheets** — the nodal membrane glow is split by the sign of the pressure slope between consecutive integration steps
    (compression→rarefaction flank vs the reverse): cyan on one flank, warm on the other. Gives the sheets the asymmetric relief of a real schlieren photograph of a standing wave. No new field samples.
FORBID: springs, extra ripples, new params, particle sparkles, changing the Cartesian modes or the SDF thickness law.
A PACKING: ACES display RGBA (unchanged).  FORMULA ROWS: none from §12.2.

---------------------------------------------------------------------------------------------------
## SHADER: gen-stellar-acoustic-resonance-manifold  (repeated pulsating stars, raymarched, blackbody)

IDENTITY: a lattice of stars whose surfaces carry coherent p/g-mode shells, heated at compression antinodes, with nodal seams and coronal arcs; mouse bends the rays.
KEEP VERBATIM: stellarField (cell repeat, fbm body, pMode/gMode, phaseSlip seams), mouse gravitational lens, compression-antinode blackbody swing, coronal arcs,
Audio Reactivity / Plasma Density / Orbital Speed / Core Temperature roles, ACES display RGBA + 5 % history.

### Mechanism interrogation
- tactic 5 (artifacts of the real instrument): a helioseismic *Dopplergram* shows surface velocity, 90° out of phase with the intensity (pressure) map the shader already draws.
- tactic 2: a star disc is limb-darkened — emission falls toward the limb, more in blue than in red.
- tactic 3: `acousticPressure` is computed analytically, so its exact time derivative (surface velocity) is free; `stellarField().w` (local radius) and `.y` (cellPhase) are never read by main().
- real stars are *stochastically* excited (convection) so each star rings up and decays on its own clock — HEAD drives all repeated stars with one global amplitude.

ADD (3 new native ideas):
 1. **Limb darkening** — surface emission × (1 − u_c(1 − μ)), μ = n·(−rd), u = (0.35, 0.55, 0.80) (blue darkens most) → spheres read as stars, rim goes warm/red.
 2. **p/g-mode Dopplergram** — d/dt acousticPressure (exact, from the same pMode/gMode terms) returned in `stellarField().w`; blueshift / redshift tint on the surface, in quadrature with the pressure heating.
 3. **Stochastic excitation envelope** — per star: amplitude = 0.35 + 0.65·(½+½ sin(0.45·t + 7·cellPhase))², so neighbouring stars ring up/decay out of step; scales emboss, heating and velocity together.
FORBID: springs, ripples, palette overlays, new params, changing blackbody/temperature roles.
A PACKING: ACES display RGBA (unchanged).  FORMULA ROWS: none from §12.2.

## Batch de-duplication (Fork A)
No §12.2 row reused by Fork A files. Tactic-derived only.
