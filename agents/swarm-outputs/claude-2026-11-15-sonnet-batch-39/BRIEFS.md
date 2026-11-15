# BRIEFS — sonnet/batch-39 (liquid / flame / iris / loom / obsidian / hex-cymatics ten)

Written by the coordinator BEFORE any WGSL edit (docs/SHADER_UPGRADE_BATCH.md §2, §9, §12.7). Base: origin/main 7f6ce638 + an uncommitted header-only `_prelude.wgsl` migration of `ambient-liquid-coupled` and `chromatic-reaction-diffusion-rgba` (no `Upgraded:` bump; the migration script also removed their ids from `src/contracts/prelude_migration.json` `pending`). **HEAD for every comparison = that state; copies are in the scratchpad `head/` dir (see COMMON.md).**

Selection rule: the user's list, ordered by line count (109 → 95). It is **not** a theme batch, so the "one overlay stamped across the batch" risk is handled by giving every file ideas in its own vocabulary and capping every §12.2 row at one file (Row budget in COMMON.md).

First pass vs later pass (grep `Ideas:` at HEAD):
- **First pass** (no `Ideas:`): `ambient-liquid-coupled`, `gen-prismatic-quantum-loom`, `gen-acoustic-obsidian-resonator`, `gen-cymatic-hex-mandala`. These also get the plumbing floor, but the floor is not the upgrade.
- **Later pass** (existing `Ideas:`): `gen-fractal-flame-classic` (2nd), `liquid` (2nd), `chromatic-reaction-diffusion-rgba` (2nd), `viscous-drag` (2nd), `gen-iris-bloom-fractal` (3rd), `luma-velocity-melt` (2nd). Cards ADD to the existing `Ideas:` line; earlier ideas stay.

Forks: **A** ambient-liquid-coupled, liquid (height-field solvers, raw A) · **B** viscous-drag, luma-velocity-melt (history-advection liquids) · **C** gen-fractal-flame-classic, gen-iris-bloom-fractal (2-D polar/IFS gens, HDR history) · **D** gen-prismatic-quantum-loom, gen-acoustic-obsidian-resonator (raymarched first-pass gens; sister boilerplate, **different ideas**) · **E** chromatic-reaction-diffusion-rgba, gen-cymatic-hex-mandala (pattern formation).

## HEAD renders (coordinator, SwiftShader 256 px, 60 frames / 4 s, saved-default sliders, SRC=img)

| Shader | idle meanL / stdL | audio 0.8,0.5,0.9 meanL / stdL | Read |
|---|---|---|---|
| gen-fractal-flame-classic | 0.548 / **0.011** | 0.578 / 0.011 | flat orange wall, faint swirl structure at ±1 % — **plateau defect** |
| gen-acoustic-obsidian-resonator | **0.008 / 0.004** | 0.42 / 0.37 | **black at silence**; gold blobs on bass |
| gen-cymatic-hex-mandala | 0.015 / 0.013 | 0.11 / 0.10 | dark idle; the "hex" is a skewed rectangle/triangle lattice, not hexagons |
| gen-prismatic-quantum-loom | 0.22 / 0.14 | 0.22 / 0.14 | audio has **no effect** (idle ≡ audio); thick brown beam bottom-centre |
| chromatic-reaction-diffusion-rgba | 0.084 / 0.053 | 0.17 / 0.20 | dark, dithered, noisy — suspect numerically unstable |
| gen-iris-bloom-fractal | 0.36 / 0.23 | 0.42 / 0.27 | fine; rich |
| ambient-liquid-coupled, liquid, viscous-drag, luma-velocity-melt | 0.50–0.51 / 0.17–0.18 | ~same | photo with subtle waves; fine at idle |

Every claim marked *(verify)* was read from the WGSL (or from the table above), not proven. Forks must confirm it with a HEAD render (or a numpy port for sims) before acting, and write what they found in their NOTES file; if a hypothesis is false, drop the rescue and say so.

Two host facts used below, both verified in source: (a) `src/renderer/webgpu/audioDepth.ts` `writeExtraBuffer` uploads the whole 256-float scratch every frame, so `extraBuffer[133..255]` is zeroed each frame and **no spring/state ever persists** (the `hasSpring` blocks in `liquid` / `ambient-liquid-coupled` always see `extraBuffer[138] == 0`, so `pointerVelocity` is identically 0); (b) the A-texel scheme in `public/shaders/cyber-lens.wgsl` L160-200 is the sanctioned way to carry a pointer track.

---

## 1. ambient-liquid-coupled — 1st pass (fork A) — `advanced-hybrid`

```
SHADER: ambient-liquid-coupled
IDENTITY: two persistent height fields (top surface + lower layer) joined by a membrane; the photo is seen through
  both layers; pointer presses/twists the top, click counter-waves, a torn membrane shows the lower layer.
KEEP VERBATIM: the whole solver (both Laplacians, coupling term, damping/velocity/height updates, clamps, impulses,
  click counter-wave ring), A raw packing (R=top height, G=top velocity, B=lower height, A=lower velocity — NO ACES
  on A), the 4 saved params and roles (wave_strength, viscosity, vortex_strength, layer_separation), `membrane`
  smoothstep, layer-separation blend, Fresnel, ACES on writeTexture only, semantic alpha, depth write.
MECHANISM INTERROGATION (§12.1):
  t2 physics one step further: light reaching the camera from the lower layer crosses BOTH interfaces. HEAD offsets
     the lower sample by the lower normal only — the top surface's slope never bends it.
  t8 energy accounting: the lower layer is just mixed in by `separation`; real water absorbs it by the gap it passes.
  t5 device artifact: a torn film / membrane has a thick collected RIM at the hole edge (surface tension pulls the
     liquid back into a bead). HEAD shows only a soft `membrane` smoothstep of |top−lower|, no rim.
  t3 promoted intermediate: the 4 neighbour loads of BOTH layers are already in registers → the gap gradient
     |∇(top−lower)| is free.
RESCUE R1 (verify): `vortex_strength` is DEAD at HEAD: its only use is `pointerTwist = dot(pointerVelocity, …)`
  and pointerVelocity ≡ 0 (host wipes extraBuffer[133..138]). Restore it with the cyber-lens A-texel track
  (corner texels (0,0)/(1,0) of A carry [mouse,time,sentinel]/[smoothed velocity,…,sentinel]); the 2 corner pixels'
  sim state is sacrificed (say so; the solver clamps/relaxes it). Drop the dead spring block (it only races).
ADD (2):
  1. Compound refraction + Beer–Lambert gap absorption (§12.2F "Beer–Lambert"): the lower-layer sample UV is displaced
     by the membrane slope AND the top-surface slope it already passed through (second-order bend), and the lower
     photo is attenuated by exp(−gap·σ) with σ per channel (water eats red first) where gap = |top−lower| path.
  2. Torn-film rim (native): bright refractive bead + darker wet shadow along the edge of the torn region, from the
     already-loaded gap gradient (rim ∝ |∇gap|·membrane). Gives the "torn membrane" a visible edge.
FORBID: Gray-Scott, IQ candy palette as the whole look (HEAD's `spectral` stays as is), a third height layer, display-
  history sparkles, new params, B writes.
A PACKING: raw coupled-height state (unchanged), 2 corner texels hold pointer track (sentinel) after R1.
```

## 2. liquid — 2nd pass (fork A) — `liquid-effects`

```
SHADER: liquid
IDENTITY: canonical interactive capillary surface — height/velocity/foam/coverage field in A, photo refracted
  through it, caustic + Fresnel tint + foam, click rings with a capillary precursor, foam that drains into troughs.
KEEP VERBATIM: solver (5-point Laplacian, velocity/height update, tension/damping mixes), A raw packing
  (R=height, G=velocity, B=foam, A=coverage — NO ACES on A), the 4 saved params and roles (viscosity, turbulence,
  ripple_strength, color_shift), Idea 1 (capillary precursor) and Idea 2 (foam drain) of the 2026-09-21 pass,
  caustic, Fresnel tint, Beer tint `exp(-height·…)`, ACES on writeTexture only, alpha, depth write.
MECHANISM INTERROGATION (§12.1):
  t2 physics: refraction at a water surface is Snell's law. HEAD displaces the photo by `normal.xy·(0.012+h·0.052)` —
     a thin-lens guess that ignores the refracted ray's true direction and the water column it traverses.
  t2/t5 wave physics: a pebble drop makes a TRAIN of crests behind the front (deep-water dispersion: long waves
     outrun short ones, so the ring spreads into trains). HEAD's click is one Gaussian shell times sin(age·k); the
     precursor (capillary side, faster) exists, the gravity-wave wake behind the main crest does not.
  t3 promoted intermediate: `normal` and `clickEnergy` are computed; neither feeds a second optical term.
RESCUE (verify): `length(pointerVelocity)·0.008` in `impulse` is a dead term (pointerVelocity ≡ 0, host wipes
  extraBuffer). Delete the dead spring block or leave it — do NOT start relying on it; no new pointer physics needed.
ADD (2, optional 3rd):
  1. Snell vector refraction (§12.2F): `refract()` the view ray through the normal at n≈1.33; lateral shift = refracted
     xy / z × height (depth-scaled), replacing the thin-lens offset. Magnification now grows with depth AND slope.
  2. Dispersive wake train (§12.2D "Deep-water dispersion"): 2–3 trailing crests behind each click front at radii
     spaced by the gravity dispersion (ω² = g·k), amplitude decaying with viscosity. Rings become pebble-drop trains.
  3. (only if idea 1+2 are <3 % of frame and cost allows) sun glint: a Blinn-Phong glint of a fixed sky light off the
     perturbed normal, ∝ slope — sparkle on ripples only.
FORBID: replacing the solver, Gray-Scott, new params, extraBuffer springs, IQ palette changes, the 9-point Laplacian
  (reserved for chromatic-reaction-diffusion-rgba), kimi-liquid-glass-style Cauchy dispersion.
A PACKING: raw (unchanged).
```

## 3. viscous-drag — 2nd pass (fork B) — `liquid-effects`

```
SHADER: viscous-drag
IDENTITY: thick-liquid displacement — an advected offset field (RG) with thickness (B) and drag energy (A), pushed by
  a jet, travelling vortices, the pointer and click pressure fronts; the photo is sampled through the offset.
KEEP VERBATIM: the whole state update (jet advect via `baseCoord`, 4-neighbour mix by viscosity, mouse/vortex/click
  forces, recovery decay, thickness/dragEnergy updates), A raw packing (RG offset, thickness, drag energy; NO ACES
  on A), the 4 saved params and roles (viscosity, drag-strength, recovery-speed, distortion-scale), Idea 1 (shear-
  thinning) and Idea 2 (bass jet surge), ACES on writeTexture, alpha, depth pass-through.
MECHANISM INTERROGATION (§12.1):
  t3 promoted intermediate: `thickness` (z) is stored but only weights alpha and the specular magnitude; the surface
     normal for the highlight is built from the OFFSET VECTOR (`vec3(newOffset, 0.02)` — nearly horizontal), so the
     "wet" shading has nothing to do with how thick the liquid is.
  t7 direction: drag is directional. HEAD samples the photo at ONE point `uv − offset·scale`; thick liquid dragged
     along a direction STRETCHES the image along it (anisotropic smear), proportional to the strain it carries.
  t1 kernel (verify): `advectPixels = vec2<i32>(round(jetDirection·…))` quantises the jet to the integer pixel lattice
     — a slowly rotating direction snaps between ~8 compass headings (staircase drift, anisotropic flow).
ADD (2, optional rescue):
  1. Thickness-gradient meniscus lighting (native): normal from ∇thickness (neighbours already loaded) for the existing
     specular term; thick ridges catch the light, thin film does not. Keeps the light direction and exponent.
  2. Strain-directed smear (native): a 4–5 tap line integral of the photo along the offset direction, length ∝
     dragEnergy (paint dragged by a spatula). Quiet where nothing has flowed.
  R1 (verify, only if the staircase is real and visible): bilinear sub-pixel fetch of `previous` for the advection.
FORBID: replacing the offset model, a Navier–Stokes solver, extraBuffer springs, IQ palette, Gray-Scott, Cauchy fringe.
A PACKING: raw (unchanged).
```

## 4. luma-velocity-melt — 2nd pass (fork B) — `liquid-effects`

```
SHADER: luma-velocity-melt
IDENTITY: the photo melts downward where it is bright — exact-load HDR display-history advection; hot pixels flow,
  columns bead into drips, ledges in the depth map pool the melt.
KEEP VERBATIM: `hot` threshold ramp, `flow` construction, history advect `uv − flow` with exact C load, injected
  chroma R/B split, `historyWeight` / `pileHold`, Idea 1 (drip pinch-off) and Idea 2 (depth-ledge pooling), A packing
  (untonemapped HDR RGB + semantic alpha; B unwritten), the 4 saved params with their RAW ranges (melt-speed 0–0.02,
  heat-intensity 0–5, persistence 0.5–0.999, luma-threshold 0–1), mouse stir + click rings, ACES on writeTexture.
MECHANISM INTERROGATION (§12.1):
  t2 physics: melting wax / hot polymer does not only fall. Surface tension depends on temperature
     (thermocapillary / Marangoni flow): material is pulled from hot (low σ) to cold (high σ), so a hot region SPREADS
     sideways at its rim. HEAD's lateral flow is just two noise fields + the drip pinch.
  t5 device artifact: a real rivulet MEANDERS — it does not run in a ruler-straight vertical line. HEAD's columns have a
     perfectly vertical centre line (`colLocal` is measured from a fixed x).
  t3 promoted intermediate: `hot` (a smoothstep of luma) is already a temperature field; only its value at the pixel is
     used, never its gradient.
ADD (2, optional 3rd):
  1. Marangoni thermocapillary spread (native): lateral flow ∝ −∇hot from two extra luma taps of the source; hot
     regions bleed outward at their boundary, cold surroundings are pushed. Scaled by the existing melt-speed.
  2. Rivulet meander (native): the column centre line wobbles with a per-column slow phase along y, amplitude growing
     with speed; the existing bead/pinch rides the wobbling centre line.
  3. (optional) Arrhenius viscosity ramp: flow speed ∝ exp(heat·(hot−1)) so cool material stays stiff and hot runs.
FORBID: replacing the melt with a fluid solver, springs, ripples overlay beyond the existing, IQ palette, Cauchy fringe.
A PACKING: HDR RGB + semantic alpha (unchanged).
```

## 5. gen-fractal-flame-classic — 2nd pass (fork C) — `generative`

```
SHADER: gen-fractal-flame-classic
IDENTITY: a classic fractal flame — a per-pixel IFS orbit through swirl / horseshoe / polar / spherical / julia
  variations with log-density compression and white-hot cores; hold shifts the centre, clicks launch flame fronts.
KEEP VERBATIM: the variation set and the `pick`-band blend (swirl/horseshoe/polar/spherical/julia), the affine step,
  the accumulators (`density`, `edgeTrap`, `hueMoment`) as quantities, log-density compression + per-channel vibrancy
  (2026-10-10 Idea 1), the julia branch flip (Idea 2), click flame fronts, hold shift, ACES on writeTexture, A =
  raw HDR display RGBA (C read as the same colour history), the 4 saved params and roles (iterations, variationMix,
  flameZoom, paletteCycle).
MECHANISM INTERROGATION (§12.1):
  RESCUE R1 (verify — measured at HEAD): the frame is a flat orange wall, stdL 0.011 idle and with audio. The affine map
     is contractive, so every pixel's late iterations sit at the same fixed point and add the SAME `center`/`trap`
     plateau (≈ Σ 0.06·e^{−4.5|z|}/(1+0.025i) over ~48 iterations); the pixel-dependent early transient is <1 % of the sum.
     Gate or weight the accumulation so that the plateau does not dominate (e.g. count only the not-yet-converged part
     of the orbit by |z_i − z_{i−1}|, or decay the weight with iteration index), without changing the accumulators' role.
     Target: stdL of the default frame ≥ 0.10 and no clipped-white/orange wall.
  t2 physics one step further: a flame's colour comes from a per-transform COLOUR INDEX averaged along the orbit
     (c ← (c + cᵢ)/2), not from a density-weighted mean of a trap sum. HEAD derives hue from `hueMoment / density`.
  t3 promoted intermediate: the per-iteration pick band (`pick`) already decides which variation ran; it is not used
     to decide colour.
ADD (2):
  1. Colour-index averaging (native, the flame's own colouring): maintain a running colour coordinate that is pulled
     toward a per-variation constant each iteration; accumulate `palette(c)` weighted by the same per-iteration
     weights; this replaces the `hueMoment/density` hue but the `palette` and `paletteCycle` slider stay.
  2. (after R1) Final-transform bloom: the orbit trap's `exp(-|len(z)-0.48|)` ring and the `center` glow become two
     separately tinted layers (ring = classicWarm→spectral by cycle, core = white-hot), so the flame has a filament
     skeleton and a hot core instead of one fused blob. Keep the HEAD constants as the default balance.
FORBID: a different fractal, histogram/chaos-game accumulation, new params, IQ-palette-as-the-whole-look, springs,
  scanline costumes. Orbit-trap / blackbody rows are used by other files; do not add blackbody.
A PACKING: raw HDR display RGBA (unchanged).
```

## 6. gen-iris-bloom-fractal — 3rd pass (fork C) — `generative`

```
SHADER: gen-iris-bloom-fractal
IDENTITY: an iris — pupil, collarette zigzag, Fuchs crypts, limbal ring, radial veins, recursive petal layers with
  stroma parallax and ciliary tension ringing; held pointer shifts the eye, clicks bloom.
KEEP VERBATIM: everything in the file (petal layers loop, irisMask/pupil/veins/limbal/collarette/crypts/tension
  rings, click bloom, palette, history mix 0.27+0.012·depth, ACES, coverage alpha, depth), 4 saved params and roles
  (petalCount, bloomDepth, aperture, colorCycle), A = raw HDR display RGBA. Earlier Ideas stay.
MECHANISM INTERROGATION (§12.1):
  t2 physics one step further: the real pupil is never still — pupillary unrest (hippus) is a 0.05–0.3 Hz
     irregular oscillation of its diameter, and the pupil constricts on a flash (light reflex). HEAD's `aperture` is
     constant except `·(1 + bass·0.08)` (a dilation on bass — the wrong sign for a light flash).
  t5 device artifact: a dilated iris shows CONTRACTION FURROWS — circular grooves in the periphery, deeper when the
     pupil is large. HEAD has radial veins and a zigzag collarette but no circular periphery folds.
  t3 promoted intermediate: `aperture` is computed once and drives ALL layer radii (`ringR = aperture + 0.07 + …`), so
     any modulation of it breathes the whole bloom coherently for free.
ADD (2):
  1. Hippus + light reflex (native): aperture × (1 + irregular unrest from 2–3 incommensurate slow sines) × (1 −
     reflex·bass), so the pupil breathes and constricts on a beat; the saved `aperture` slider still sets the mean.
  2. Contraction furrows (native): 2–3 faint concentric periphery grooves (darkening + a thin warm lip) between the
     collarette and the limbus, wobbling with angle, deeper for a larger aperture.
  3. (optional if cheap) corneal catchlight: a small soft window highlight off-axis at the pupil rim, fixed in screen
     space (does not move with the held shift).
FORBID: new petal system, changing palette/hue mapping, springs, scanlines, second iris, new params.
A PACKING: raw HDR display RGBA (unchanged).
```

## 7. gen-prismatic-quantum-loom — 1st pass (fork D) — `generative`

```
SHADER: gen-prismatic-quantum-loom
IDENTITY: a camera drifting through a domain-repeated lattice of glowing threads (three orthogonal cylinder families,
  domain-warped, 64-step march), glow tinted by a hit-distance sine; mouse hold bends rays toward the cursor.
KEEP VERBATIM: `map()` structure (domain warp → opRep → three crossing cylinder SDFs → min), the glow accumulation
  `0.02/(0.01+d²)`, the 64-step march, the `sin(t·k + shift)` chromatic tint, the 4 saved params with RAW ranges
  (thread-density 0.5–3, chromatic-shift 0–6.28, gravity-well-strength 0–2, quantum-fluctuation-speed 0.1–5), the
  mouse gravity pull intent, camera drift.
MECHANISM INTERROGATION (§12.1):
  RESCUE R1 (verify): "audio" is read from `textureLoad(dataTextureC, …)` — C is the history texture and this shader
     never writes A, so it is always 0: the file is NOT audio-reactive at HEAD (idle ≡ audio render). Use
     `plasmaBuffer[0].xyz` (bass → thread radius pulse, as intended by `audioPulse`).
  RESCUE R2 (verify): `opRep` uses WGSL `%` on f32, which is TRUNCATED remainder: for p + 0.5c < 0 the result is
     negative, the cell is no longer centred and the SDF is discontinuous (a plausible cause of the thick brown beam).
     Use `p − c·floor(p/c + 0.5)`.
  RESCUE R3 (verify): mouse pull compares `uv` (centred, ±aspect/2, y DOWN) with `mousePos` built as ±aspect (2× scale)
     and y UP-flipped — the well is not where the cursor is; the image may be upside-down vs the world-up camera.
  RESCUE R4: floor — A and depth are never written, alpha is a bare 1.0, no ACES (`c/(1+c)`), no header.
  t2 physics: a "prismatic" glow should disperse — the halo of a thread is not the same radius in R, G and B.
  t5 device artifact: a LOOM interlaces: warp and weft pass over and under each other; a cylinder-union lattice has
     every crossing fused.
ADD (2):
  1. Weave interlace (native): offset each thread family across its cell by ±a thread radius with a cell-parity
     alternation, so at every crossing one thread passes in front and the other behind (plain weave in 3-D).
  2. Dispersed glow halos (§12.2F Cauchy dispersion): accumulate the glow term three times with the thread radius
     shifted per channel by the Cauchy scale (R widest-near … B), inside the existing march, so each thread has a
     spectrally fringed halo; the saved chromatic-shift keeps its role as the hit-distance phase.
FORBID: raymarched creature/fractal, springs, ripples, scanline/glitch costume, changing the SDF to another primitive
  family, step-count AO / curvature (reserved for obsidian).
A PACKING: display RGBA — ACES display + semantic alpha (glow coverage); A = same display RGBA (nothing reads C).
```

## 8. gen-acoustic-obsidian-resonator — 1st pass (fork D) — `generative`

```
SHADER: gen-acoustic-obsidian-resonator
IDENTITY: tall obsidian monoliths with an octahedral cavity carved in, domain-repeated, rotating; bass swells the
  cavity and lights gold emissive, mids crack the surface; held pointer pulls the lattice (shockwave).
KEEP VERBATIM: `map()` (mouse pull → domain repetition → rotation → box minus octahedron + fracture), the 100-step
  march, the `steps`-based occlusion term `ao`, the gold-on-bass emissive, the 4 saved params with RAW ranges
  (rotation_speed 0–2, shockwave_force 0–10, fracture_scale 0–3, domain_spacing 0.5–5 → spacing = w·5), the dark
  obsidian base colour.
MECHANISM INTERROGATION (§12.1):
  RESCUE R1 (verify — measured): black at silence (idle meanL 0.008). `col = mix(0.02, gold·bass·2,
     smoothstep(0.8,1,ao))·ao` is ≈ 0.016 with no audio: the geometry is invisible until the music plays. Obsidian is a
     high-gloss black glass that reflects its surroundings; add a sky/environment reflection so the silent frame shows
     the object.
  RESCUE R2 (verify): `fracture_scale` (zoom_params.z) is used only as `bass·z` on the octahedron size; `mids` fracture
     is an unscaled sin³ — check that all four sliders are live. `normalize(p)` in the mouse pull is unguarded at p=0.
  RESCUE R3 (verify): uv has y DOWN into a world-up camera — the scene is upside-down. Floor: alpha is a bare 1.0, A is
     written as vec4(0), no ACES.
  t2 physics one step further: obsidian shows CONCHOIDAL fracture — curved concentric shell ripples radiating from the
     impact point — and gold-sheen obsidian shows a metallic schiller at grazing angles from oriented inclusions.
  t3 promoted intermediate: the march's step count is the only shading input; a normal is never computed.
ADD (2):
  1. Conchoidal scars (native): a concentric-shell displacement (`sin(k·|p − origin_cell|)` with a per-cell origin) added to
     the fracture term at a small static amplitude, so the monoliths carry curved fracture arcs even at silence.
  2. Gold schiller + curvature wear (§12.2E "SDF curvature"): from a 6-tap central-difference normal (post-hit only):
     Fresnel-weighted gold sheen banded by layer coordinate (the inclusion planes), and an edge highlight where the SDF
     curvature is convex (chipped edges). Bass still drives the emissive on top.
FORBID: a different object, glass/refraction rewrite, springs, ripples, scanlines, IQ-palette-as-the-whole-look,
  orbit-trap / Beer–Lambert (used by the previous batch's abyssal geode — do not copy its code), Cauchy halos (loom).
A PACKING: display RGBA — ACES display + semantic alpha; A = same display RGBA (nothing reads C) or documented otherwise.
```

## 9. chromatic-reaction-diffusion-rgba — 2nd pass (fork E) — `simulation`

```
SHADER: chromatic-reaction-diffusion-rgba
IDENTITY: two coupled Gray–Scott layers (warm U/V, cool U/V) in one RGBA state, cross-coupled, competitive overlap
  quench, photo chroma seed, hover spiral, click fronts; displayed as warm/cool pigment over the photo with edge fringe.
KEEP VERBATIM: the 4-species state and its reaction terms, feed/kill/separation/coupling mappings from the 4 saved
  params (feed, kill, chromaticSep, crossCouple — note the JSON has NO `mapping` field; the shader reads x,y,z,w in
  that order), Idea 1 (overlap quench) and Idea 2 (photo chroma seed), hover spiral, click fronts, pigment display +
  fringe, A raw packing (warm U, warm V, cool U, cool V — NO ACES on A), ACES on writeTexture only, alpha.
MECHANISM INTERROGATION (§12.1):
  RESCUE R1 (verify — suspected, measured symptom: dark dithered idle): explicit Euler with an UNNORMALISED 5-point
     Laplacian: Du·dt = 0.82·0.8 = 0.66 (and 0.76·0.8 for the cool U) against the 2-D stability limit D·dt ≤ 0.25. The
     update is clamped to [0,1], so instability shows as saturated high-frequency noise rather than NaN. Port the update to
     numpy (see `scripts/sim_models/`) and run ≥ 600 frames at 192 px to confirm; if confirmed, restore stability with the
     smallest change (scale the Laplacian by the stable factor or dt) and say what pattern scale changed. If NOT
     confirmed, drop R1 and say so.
  t1 kernel: the 5-point Laplacian has an axis bias (stripes/worms line up with the pixel grid); the 9-point isotropic
     stencil (0.2 edges, 0.05 corners, −1 centre) removes it — and the 4 diagonal loads cost 4 `loadState` calls.
  t4 second-order the parameter: `separation` and the diffusion constants are global scalars. The Turing wavelength scales
     as √D, so scaling D by the PHOTO's local luma makes the pattern scale follow the picture (a typographic, halftone
     texture) with no new seed.
ADD (2):
  1. Isotropic 9-point Laplacian (§12.2D) — drop-in for `lap`, same constants after the stability fix.
  2. Luma-scaled diffusion length (native, t4): D_u, D_v multiplied by (0.75 + 0.5·photoLuma), bounded to stay stable,
     so bright regions grow bigger spots/worms than dark ones. Rides the existing `src` fetch.
FORBID: Gray-Scott on another file's turf, kill-map/photo-kill (batch-38 reaction-diffusion did that), new params,
  display-history sparkles, springs, IQ palette.
A PACKING: raw 4-species state (unchanged).
```

## 10. gen-cymatic-hex-mandala — 1st pass (fork E) — `generative`

```
SHADER: gen-cymatic-hex-mandala
IDENTITY: a hexagonal lattice lit by a radially travelling standing wave (cymatic rings), bright cell edges, node
  sparks on treble, coloured by angle, with a trail history; held/moved pointer offsets the centre.
KEEP VERBATIM: radial wave `sin(dist·freq·TAU − t·…)·exp(−dist·…)` and its audio mapping (mids → frequency, bass →
  amplitude/decay), hex lattice as the "mandala" ground, edge lines, node sparks, angular hue palette, trail blend
  `mix(prev·(0.9−p4·0.1), col, 0.28+p4·0.18)`, ACES display, IGN dither, depth attenuation, the 4 saved params and roles
  (hex_scale, wave_frequency, ring_intensity, trail_persistence).
MECHANISM INTERROGATION (§12.1):
  RESCUE R1 (verify — seen in the HEAD render): `hexCoords` splits each axial parallelogram into two triangles and measures
     an "edge" in the skewed frame, so the lattice is a skewed checker of parallelogram halves, not hexagons.
     Use the standard two-lattice nearest-centre hex (or cube rounding) to get true hex cell id + distance to the edge.
     The two ideas below cannot read as "hex mandala" until this is right.
  RESCUE R2: C is read with `textureSampleLevel(dataTextureC, u_sampler, …)` (filtering sampler on rgba32float): use an exact
     `textureLoad(dataTextureC, pixel, 0)`. Output is `col·alpha` with alpha floored at 0.1 (idle meanL 0.015): check how the
     other generative files write the display store (straight alpha) and do not double-darken; alpha must stay semantic.
  t2 physics one step further: a cymatic plate does not carry one travelling ring — it carries MODES. A circular plate's modes are
     J_m(k·r)·cos(m·θ); the hex symmetry of this file selects m = 6. HEAD has only the m = 0 radial wave.
  t6 history: the trail already persists; real Chladni sand migrates AWAY from antinodes and collects on the NODAL lines
     (where the standing wave is ≈ 0). The history can be that sand.
ADD (2):
  1. Hex-symmetric modal wave (native; Bessel in `docs/WOLFRAM_SHADER_DATA.md`): add the m = 6 mode
     `J6-ish(k·r)·cos(6θ + phase)` to the radial wave, weight by `wave_frequency` mix so m=0 rings remain; the mandala gets
     six-fold nodal petals. Approximate J_m by the large-argument cosine with a core fade (no Bessel builtin).
  2. Chladni sand (native): accumulate sand density in the history's A.a (raw scalar, a documented packing) where |modal
     wave| is small and drain it where it is large; sand brightens the nodal lines. Replaces nothing — the colour trail stays
     in A.rgb. Slider `trail_persistence` keeps scaling the colour trail and ALSO the sand's retention.
FORBID: a different pattern family (Voronoi, Truchet), particle sparkles, springs, ripples, new params, changing the palette.
A PACKING: A.rgb = display-linear colour trail (as HEAD), A.a = Chladni sand density (raw scalar; HEAD stored `bassEnv` there,
  unused). State it in the header and the JSON `feedback` note if present.
```
