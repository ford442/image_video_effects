# BRIEFS — sonnet/batch-38 (liquid / fractal / galaxy / aurora / kaleido / neon ten)

Written by the coordinator BEFORE any WGSL edit (docs/SHADER_UPGRADE_BATCH.md §2, §9, §12.7). Base: origin/main 7f6ce638 + an uncommitted header-only `_prelude.wgsl` migration of `radiating-haze` and `reaction-diffusion` (no `Upgraded:` bump; their two ids were removed from `src/contracts/prelude_migration.json` `pending`). **HEAD for every comparison = that state; copies are in the scratchpad `head/` dir (see COMMON.md).**

Selection rule: the user's list, ordered by line count (123 → 117). It is **not** a theme batch, so the dedupe risk (one overlay stamped across the batch) is handled by giving every file ideas in its own vocabulary and capping every §12.2 row at one file (see Row budget in COMMON.md).

ID note: the list says `kimi-liquid-glass`; the catalog id is `kimi-liquid-glass` (definition `shader_definitions/liquid-effects/kimi-liquid-glass.json`) but the **file is `public/shaders/kimi_liquid_glass.wgsl`** (underscores).

First pass vs second pass (grep `Ideas:` at HEAD):
- **First pass** (no `Ideas:`, no `Upgraded:`): `gen-abyssal-geode-matrix`, `gen-audio-reactive-spiral-galaxy`, `gen-audio-reactive-aurora-ribbons`. These also get the plumbing floor (they are Jules/swarm landings), but the floor is not the upgrade.
- **Second/third pass** (existing `Ideas:`): `kimi-liquid-glass`, `kaleido-scope`, `radiating-haze`, `gen-flame-fractal-attractor` (3rd), `reaction-diffusion`, `liquid-oil`, `neon-edge-glow`. Cards ADD to the existing `Ideas:` line; earlier ideas stay.

Forks: **A** liquid slabs/films with raw-state A (kimi-liquid-glass, liquid-oil) · **B** artistic sim + colour filter, both just prelude-migrated (reaction-diffusion, radiating-haze) · **C** raymarch/IFS generative (gen-abyssal-geode-matrix, gen-flame-fractal-attractor) · **D** sister audio-reactive gens, same boilerplate, **different ideas** (gen-audio-reactive-spiral-galaxy, gen-audio-reactive-aurora-ribbons) · **E** photo-plane optics (kaleido-scope, neon-edge-glow).

Every claim marked *(verify)* was read from the WGSL, not measured. Forks must confirm it with a HEAD render (or numpy port for sims) before acting, and write what they found in their NOTES file; if a hypothesis is false, drop the rescue and say so.

---

## 1. kimi-liquid-glass  — 2nd pass (fork A) — file `kimi_liquid_glass.wgsl`

```
SHADER: kimi-liquid-glass
IDENTITY: a persistent liquid-glass slab — height/velocity/thickness field in A, Snell-refracted photo,
  Fresnel + Beer absorption, three-band caustic, held lens push, click wave rings, seed bubbles, TIR flank flash.
KEEP VERBATIM: the whole solver (laplacian, velocity/height/thickness update, coverage), A raw packing
  (R=height, G=velocity, B=thickness, A=coverage — NO ACES on A; ACES only on writeTexture), the 4 saved params and
  their ROLES in the file (zoom_params x=intensity, y=speed, z=scale, w=detail — the saved *names* are
  glass_thickness/ior/depth_weight/distortion; leave names and ids byte-exact), Snell `refract`, Fresnel, Beer
  absorption, TIR (Idea 1 of the last pass), seed bubbles (Idea 2), held lens push, click rings, depth write.
MECHANISM INTERROGATION (§12.1):
  t2 physics: glass dispersion is non-linear in wavelength (Cauchy n = A + B/λ²). HEAD splits R and B by a linear
     ±δ·normal.xy around the green sample — symmetric and independent of how thick the glass is.
  t8 energy accounting: the caustic is `pow(|laplacian|·k, 2.2)`. abs() makes both converging and diverging
     curvature bright, but a refracting surface FOCUSES light where it converges and STARVES it where it diverges
     — every real caustic line has a dim twin beside it. HEAD invents light on the diverging side.
  t3 promoted intermediate: `laplacian` already carries the sign; it is thrown away by abs().
RESCUE (verify): R1 `exp(-pow((dist - age*v)*k, 2.0))` in the click ring — `pow` with a NEGATIVE base (inside the
  ring, dist < age·v) is undefined in WGSL and NaN on some GPUs (project memory: pow negative-base NaN). Replace
  by `x*x`; no visual change expected where it already worked; say what the SwiftShader render showed.
ADD (2):
  1. Cauchy dispersion (§12.2F, snippet B2 `cauchyScale`): scale the refraction `offset` per channel by
     s = n(λ)/n(550 nm) for 650/550/450 nm instead of the fixed ±δ add; B coefficient from the file's existing
     amplitude `(0.001 + detail*0.006 + treble*0.0025)`. Blue then bends more than red, non-linearly, and the
     fringe grows with thickness × slope (true of glass). Calibrate so the mean R/B separation at default
     sliders is within ±30 % of HEAD, not 3× it.
  2. Signed-focus caustic (native, energy accounting): split `laplacian` into converge = max(−lap,0) and
     diverge = max(+lap,0). Caustic brightness follows converge (sharper, brighter lines); diverge subtracts a few
     percent from `source*absorption` (the dim twin). The abs-based HEAD caustic term is reweighted, not deleted.
     Default-slider mean luma must stay within ~±6 % of HEAD.
FORBID on this file: replacing the solver, springs, a new IQ palette (the thin-film `interference` is HEAD's own),
  a second bubble system, extraBuffer state, promoting A to display RGBA.
A PACKING: raw (unchanged). ACES on writeTexture only.
```

## 2. kaleido-scope  — 2nd pass (fork E)

```
SHADER: kaleido-scope
IDENTITY: the photo seen through a morphing Poincaré-disk mirror kaleidoscope — wedge fold, iridescent metal seams,
  a vertex ring, geodesic hypR creases, depth-aware chromatic split, opposite-wedge dihedral blend.
KEEP VERBATIM: `poincareMap` fold and `hypR`, the `segments` morph between tessA/tessB (zoom_params.x), `lensDistort`,
  mouse-shifted `center`, depth-driven CA split, `boundary`/`metal`/`vertex` ring, hypR crease (last pass Idea 1),
  opposite-wedge mix 0.28 (Idea 2), 4 params and roles (segments / rotation / zoom / ring offset), ACES display,
  A = the same display RGBA as writeTexture (nothing reads C).
MECHANISM INTERROGATION (§12.1):
  t5 device artifacts: a real kaleidoscope (a) silvers its mirrors at ~92 % reflectance, so every reflected image
     is dimmer and cooler than the primary — the image count k ≥ 1 reflections shows as k bounces of loss;
     (b) its object cell TUMBLES: beads drift under gravity relative to the mirror frame, so the picture slides
     under the mirrors instead of only spinning rigidly (HEAD only rotates `theta`).
  t3 promoted intermediate: `theta/6.283*segments` is computed inside `poincareMap`, then only `fract()` of it is
     kept — `floor()` of it is the wedge index = the bounce count, thrown away.
RESCUE (verify): R1 `fract(theta/2π * segments)` with a NON-integer `segments` (HEAD morphs 4–7 → 6–11
  continuously) cannot close around 2π: a hard radial seam sits on the atan2 branch cut (θ = ±π, left of centre)
  at every morph value except exact integers. Render HEAD at several `morph` times. If visible AND it can be hidden
  in ≤ 15 lines without changing identity (e.g. let the existing `boundary` metal highlight carry the seam so it
  reads as a mirror seam), do it; otherwise document it and leave it.
ADD (2):
  1. Mirror loss per bounce — fold count as material (§12.2E): bounces = min(k, segments − k) with
     k = floor(theta'/2π·segments) from the same `theta'` poincareMap uses; baseColor *= 0.93^bounces with a faint
     cool tint on odd counts (silvered back-glass). Primary wedge unchanged; farthest images ≈ −25–30 %.
  2. Tumbling object cell (native): a slow Lissajous drift of the SAMPLE window in source space
     (e.g. `0.05*vec2(sin(t*0.37), cos(t*0.29))`, scaled by `zoom` and the existing morphSpeed) applied to
     `mirrored`/`opposite`/CA taps, not to the mirror frame — mirrors stay put, content slides underneath.
FORBID on this file: more creases/palettes, springs or ripples, changing `hypR`, a new param, true-geodesic arcs
  drawn as decoration (they would not match the mirrored content).
A PACKING: ACES display RGBA (unchanged).
```

## 3. radiating-haze  — 2nd pass, prelude-migrated (fork B)

```
SHADER: radiating-haze
IDENTITY: a colour-selective aura filter: saturated colours (not neutrals/browns/blacks) pulse hue-shifted rings
  that radiate from the cursor and leave a fading trail; the photo stays the photo.
KEEP VERBATIM: HSV neutral rule (`isNeutral` incl. the brown band), `satThresh = z*0.4+0.2`, 1-texel neighbour
  corona (Idea 1), cursor-origin waves `origin = mix(0.5, mouse, 0.85)` (Idea 2), `aura` formula, persist =
  max(prev*0.92, aura) in A.r, A = (persist, aura, strongMask, 1.0) raw packing (A.a is a hard 1.0 today — keep it, say
  so), display ACES with semantic alpha, 4 params and roles (wave speed / aura intensity / sat threshold / aura radius).
MECHANISM INTERROGATION (§12.1):
  t3 promoted intermediate: `strongMask` is computed per pixel and only ever used on THAT pixel (plus a 1-texel
     bleed) — a haze "radiating" from coloured objects never leaves their footprint.
  t6 history: `prev` is loaded in place, so the persisted trail fades where it was; it does not travel with the
     wave. Exact C is already read, so advecting the read position is free state.
RESCUE (verify): R1 wave frequency vs aura radius: `sin((dist − t·speed)·15)` with the aura clipped to
  dist < radius+0.08 ≈ 0.155 uv at default means < 0.4 wavelengths fit in the visible disc — no ring is resolved,
  the "waves" are a pulsing disc. Render HEAD idle AND held at default and at radius = 1. If confirmed, scale the
  ring frequency so ≥ 2 rings fit inside `radius+0.08` at default WITHOUT changing the disc size; record the default
  look change.
ADD (2):
  1. Source-hue halo gather — energy-conserving bloom (§12.2F): an 8-tap golden-angle ring (radius ~4–10 px scaled by
     res.y/1080) gathers strongMask-weighted source colour; NEUTRAL pixels receive that hue's aura (via the same
     waveMask·intensity) so the glow spills OUT of coloured objects into the surround, and the strong pixel gives up
     a little (`src *= 1 − 0.25·haloW`) so energy moves rather than appears. Neutral-ignore rule stays true for the
     pixel itself.
  2. Outward-advected persistence (native): read `prev` at `pixel − round(radialDir·k)` with k ≈ 1–2 px scaled by the
     existing wave `speed` (exact `textureLoad`, texel-centre, clamped; hand-lerp two taps if nearest quantisation
     shows) so faded rings keep travelling away from the cursor.
FORBID on this file: springs, IQ palette, whole-image bloom, changing the neutral/brown rule, a new param, ripple
  shockwaves, ACES on A.
A PACKING: raw (persist, aura, strongMask, 1.0) — unchanged. Display ACES RGB on writeTexture.
```

## 4. gen-abyssal-geode-matrix  — FIRST PASS (fork C)

```
SHADER: gen-abyssal-geode-matrix
IDENTITY: a raymarched cavern of fractal-folded octahedral crystals on a domain-repeated lattice, camera flying
  forward, deep-sea bioluminescent glow gathered near surfaces — cyan on bass, magenta on mids — with a mouse
  gravity well.
KEEP VERBATIM: `map()` (held-mouse gravity well, domain repetition c = 4, the abs-fold + `rot` loop with
  `iters = max(1, 4·w)`, `sdOctahedron`), the 100-step marcher and `glow += 0.01/(0.01+dS²)` accumulation, the forward
  camera, lightDir, deep-sea base colour (0.05,0.15,0.25), emissive = cyan·bass + magenta·mids scaled by glowIntensity,
  the 4 params with their RAW ranges and roles (gravityPull 0–1, fractalSpeed 0–5, glowIntensity 0–2, fractalDetail 0–1).
MECHANISM INTERROGATION (§12.1):
  t2/t8: the file is "abyssal" and models glow but not water: nothing absorbs light with distance, so far crystals are
     as bright as near ones. A geode is also *mineral*: veins and growth inclusions are the first thing a viewer reads.
  t3 promoted intermediate: the fold loop already computes `p` per iteration (an orbit); `dO` (distance) and the
     step count are thrown away.
HEAD DEFECTS (verify by render, idle AND with bass/mid = 0.8/0.5):
  R1 `ao = 1.0 − f32(MAX_STEPS)/100.0` is exactly **0** → `col = baseCol*diff*ao` is black; the lit crystal surface
     contributes nothing.
  R2 `emissive = cyan·bass + magenta·mids` is 0 at silence → the frame is black without audio; glowIntensity does
     nothing. An idle bioluminescent floor is needed (e.g. cyan·(0.25+bass) + magenta·(0.10+mids)); say what the
     default frame looked like before.
  R3 `glow` sums up to ~100 steps of ≤ 1.0 each and is unnormalised — expect white blow-out once R2 is fixed; pick the
     glow scale that gives a sane default exposure and document it.
  R4 writeTexture only: alpha hard 1.0, no ACES (raw clip), no depth, no A → ACES on display, alpha semantic
     (hit coverage + glow), depth from dO normalised, A = display RGBA (nothing reads C).
ADD (2 + 1 rescue-as-idea):
  1. Orbit-trap mineral veins (§12.2E): track `trap = min(trap, length(p.yz))` (or distance to a fold plane) inside the
     existing fold loop (carry it out of `map()` in a module-scope `var<private>`, or write a
     second function that repeats the fold loop only on hits); veins = exp(−trap·k) on hit surfaces, warm amber/quartz against the cold base; `treble`
     modulates shimmer (treble is read and unused today).
  2. Beer–Lambert deep-water absorption (§12.2F): surface + glow colour × exp(−dO·vec3(0.30, 0.09, 0.04)) (red dies
     first) plus a faint in-scatter fog vec3(0, 0.03, 0.06)·(1 − exp(−dO·0.15)), so the cavern recedes teal → black.
  3. Step-count AO (§12.2E, snippet E2) on the hit, replacing the zeroed fake AO (R1). 5 extra `map()` calls only on hits.
FORBID on this file: new SDF primitives or creatures, springs/ripples (the gravity well is the pointer interaction),
  IQ palette, glitch/scanline costume, replacing the fold loop.
A PACKING: ACES display RGBA (HEAD stored nothing).
```

## 5. gen-flame-fractal-attractor  — 3rd pass (fork C)

```
SHADER: gen-flame-fractal-attractor
IDENTITY: a curling swirl+abs-fold IFS "flame" — an orbit-density attractor drawn as glowing ember filaments, even/odd
  iteration bands, orbit-capture contour filaments, rising-ember feedback, click rings, held vortex, bass-driven.
KEEP VERBATIM: the 36-iteration loop and every accumulator (creaseAcc, evenDen/oddDen, lineTrap, capture/contour),
  the 4 params and their `mix` ranges, the held vortex and click embers, the rising-ember `riseCoord` exact load with
  wobble (last pass Idea 2), ACES on writeTexture, A = raw HDR (hdrColor, alpha) fed back through C as COLOUR
  (documented packing — keep it, keep the `≤ 8` clamp), semantic alpha, depth.
MECHANISM INTERROGATION (§12.1):
  t2 physics: a flame fractal (Draves) is a density histogram displayed with LOG scaling and a "vibrancy" mix between
     per-channel and luminance-preserving log. HEAD maps density linearly (`min(orbitDensity*0.38+lineTrap, 5)`) and
     ACES's it, so dense cores clip flat and sparse tails vanish — the signature soft-core/long-tail flame falloff is
     missing.
  t8 energy/blackbody: rising embers cool — white → yellow → orange → deep red → gone. HEAD feeds history back at the
     same colour (`mix(hdr, history.rgb, …)`), so trails never redden.
ADD (2):
  1. Log-density flame display with vibrancy (native to flame fractals): `L = log(1 + K·lum)/max(K·lum, ε)` applied to
     `hdrColor`, mixed per-channel vs luminance by a fixed vibrancy (~0.6–0.8) so cores keep colour instead of clipping
     white. Calibrate to the default look: report the fraction of pixels with max channel ≥ 0.98 after ACES at HEAD vs
     new (should fall), and meanL within ±10 %.
  2. Blackbody cooling of rising embers (§12.2F blackbody): tint the loaded `history.rgb` by a per-frame Wien-ish cooling
     ramp (blue dies fastest, red slowest, e.g. `exp(−vec3(0.004, 0.022, 0.07))`) before the mix, so each frame of rise
     redshifts and dims the trail. Prove it: after 60 frames, trail colour ~20 px above a filament has a higher R/B
     ratio than HEAD's. Keep the ≤ 8 clamp on what is stored in A.
FORBID on this file: replacing the IFS, a new palette, particle sparks, new params, springs.
A PACKING: raw HDR display RGBA (unchanged: A = hdrColor, alpha; ACES on writeTexture only).
```

## 6. reaction-diffusion  — 3rd pass, prelude-migrated (fork B)

```
SHADER: reaction-diffusion
IDENTITY: a Gray-Scott two-chemical field (U, V in A.rg) seeded by the photo's luma, carried by a rotating one-pixel
  conveyor, fed by travelling packets and click fronts, anisotropically smeared along the flow, with mitosis pinch,
  shown as a three-ramp colour of U − V.
KEEP VERBATIM: conveyor advection (`flowDir`, `baseCoord`), the 0.55 anisotropic Laplacian mix (Idea 1 of the last
  pass), packets, ripple fronts, mouseSeed, mitosis pinch (Idea 2), colour ramps, `totalAlpha` accumulation, A raw
  (U, V, packet, accumulation — do NOT ACES the stored fields), ACES on writeTexture, 4 params with their ROLES
  (zoom_params.x → diffusionRate, .y → feedRate + packet speed, .z → killRate, .w → accumulationRate; the saved
  names Intensity/Speed/Scale/Detail do not match — leave them).
MECHANISM INTERROGATION (§12.1):
  t3 promoted intermediate: `seed` (photo luma) is computed once and used only to nudge V by 0.002 and floor U.
  t4 second-order parameter: killRate is one scalar for the whole frame; Gray-Scott's pattern TYPE (spots / worms /
     stripes) is decided by (f, k) — a spatially varying k makes the pattern morphology follow something.
HEAD HYPOTHESES — **verify before touching anything (numpy port per project memory "Sim CPU Validation"; models in
  `scripts/sim_models/`; N ≤ 160, ≤ 100 s per run)**:
  R1 `a = clamp(max(prev.r, 0.75 + seed·0.25), 0, 1)` floors U at ≥ 0.75 every frame — U can never be depleted, so is
     this still a Turing system or a forced-decay V field? Compare spots/stripes formation with and without the floor.
  R2 effective diffusion is `rate·0.25·lap` with rate 0.025–0.1 and Dv = rate/2 → Du ≈ 0.006–0.025 (canonical
     Gray-Scott is Du ≈ 0.16–0.2, Dv ≈ 0.08–0.1 per step on a 5-point stencil). Is the pattern length scale
     pixel-sized (noise) at default?
  If the chemistry is dead or noise at default, the first deliverable is a RESCUE inside the shader (constants only;
  saved params, ranges and roles stay byte-exact — no preset migration), with the numpy evidence; ideas follow.
ADD (2, only after the chemistry is shown to evolve):
  1. Isotropic 9-point Laplacian (§12.2D, snippet D2): replace `isoLap` (5-point) by the 0.2/0.05/−1 stencil on the
     same conveyor-shifted `baseCoord`, rescaled so its magnitude matches (`lap9 · 0.25/0.3`), removing the
     diamond/square bias of spots. The anisotropic mix stays.
  2. Photo-driven kill map (native): `killLocal = killRate + (seed − 0.5)·Δ` with Δ small enough to stay inside the
     Pearson pattern band (≈ ±0.004–0.008), so spots / worms / stripes follow the photo's tonal regions. `Scale`
     (killRate) keeps its global role.
FORBID on this file: replacing Gray-Scott, a new solver, new springs (mouseSeed exists), IQ palettes, restyling the
  click fronts.
A PACKING: raw (unchanged).
```

## 7. gen-audio-reactive-spiral-galaxy  — FIRST PASS (fork D)

```
SHADER: gen-audio-reactive-spiral-galaxy
IDENTITY: a luminous log-spiral galaxy — hot core, 2–5 arms of stars that tighten on bass and turn with mids, a
  dust lane, treble supernova sparks, mouse parallax, trail persistence; depth fade, ACES, IGN dither.
KEEP VERBATIM: the log-spiral arm geometry `spiral = a − armPhase − log(r)/tightness`, `arms = 2 + floor(mix(2,5,p2))`,
  the core, star colours (blue → amber via `temp`), the C trail mix with `p4`, bass/mid/treble roles, mouse parallax,
  depth fade, `hue_preserve_clamp` + ACES + IGN, premultiplied `col*alpha` with the same alpha formula, the 4 params
  and roles (arm_tightness / arm_count / spin_rate / trail_persistence), A = raw HDR trail colour + bassEnv in .a.
MECHANISM INTERROGATION (§12.1):
  t2 physics: stars in a real spiral do NOT rotate rigidly with the arms — the arm is a density wave with a pattern
     speed, and stars orbit at their own (flat-rotation-curve) speed, so inner stars lap the pattern and drift through
     the arms. HEAD turns everything by one `orbit` angle.
  t5 artifacts: density-wave arms have a fixed colour sequence across them — a dust lane on the inner (leading) edge,
     pink HII star-forming knots just behind it, blue young stars, then yellow-orange old disk stars between arms.
  HEAD's dust term is `sin(a·arms − log(r+0.05)·3)` — a different spiral from the arms (tightness-independent), so the
     lane is not tied to any arm.
HEAD DEFECTS (verify by render):
  R1 stars: `pos = (cos(a+armPhase), sin(a+armPhase))·(r+jitter)` is the PIXEL'S OWN radius at a rotated angle, so
     |uv − pos| = 2r·sin((orbit+armPhase)/2) and `starGlow` (sizes 0.002–0.006) is ≈ 0 at almost every pixel: the 96-star
     loop contributes almost nothing. Render HEAD with the loop's contribution zeroed vs on. If Δ ≈ 0 the arm stars are
     dead → rescue by placing each star ON its arm: radius r_i from `h.y`, angle from the same log-spiral relation, then
     glow at that position (this is the intended effect, not a new one). Report the % of pixels that change.
  R2 `textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0)` — a FILTERING sampler on rgba32float history, and
     `uv01 = pixel/res` is not the texel centre → exact `textureLoad(dataTextureC, pixel, 0)`.
ADD (2):
  1. Differential rotation — flat rotation curve (native): star angle = arm angle at its radius + (Ω(r) − Ω_pattern)·t,
     Ω(r) = Ω₀/(1 + r/r_c); `orbit` (mids + spin_rate) stays the PATTERN speed. Inner stars lap outward ones and drift
     along the arms. Prove with a 2-frame difference of star positions vs radius.
  2. Density-wave colour sequence (native): tie the dust lane to the arm's inner edge using the existing `spiral`
     offset (replacing the misaligned `sin(a·arms − log(r+0.05)·3)` term), pink HII knots (hash-thresholded blobs) on
     the trailing edge, blue young stars at the arm centre, amber old stars in the inter-arm disk — all functions of the
     `spiral` offset, using the file's own star colours as endpoints.
FORBID on this file: a bar/ring galaxy, nebula noise clouds, IQ palette, galaxy collision, springs/ripples, replacing the
  arm model, and **anything stamped from the aurora-ribbons card in the same fork** (different ideas, different code).
A PACKING: raw HDR trail colour + bassEnv in .a (unchanged — it is what C is read as); ACES on writeTexture.
```

## 8. liquid-oil  — 3rd pass (fork A)

```
SHADER: liquid-oil
IDENTITY: a high-viscosity oil film — persistent height/velocity/shear in A, slow capillary flow, pointer stirring that
  parts the film, click rings, shear-aligned thin-film colour streaks, specular glints; photo refracted underneath.
KEEP VERBATIM: the solver (capillary Laplacian × damping, curl forcing, stir, click rings, velocity/height update),
  displacement wake (Idea 1) and shear streaks (Idea 2) of the previous pass, A raw packing (R=film height,
  G=vertical response, B=shear, A=coverage — NO ACES on A), the 4 params and roles (viscosity / turbulence / ripple
  strength / colour shift), Fresnel, specular, absorption, ACES on writeTexture, depth.
MECHANISM INTERROGATION (§12.1):
  t2 physics: an oil slick's colour is thin-film interference whose phase depends on VIEWING ANGLE (δ ∝ cos θ_t), so
     hue shifts across a curved film. HEAD's `interference` is a fixed cosine of thickness only; `fresnel` already
     uses `dot(normal, viewDir)` but that angle never reaches the colour. Thin-film is the file's identity, so the
     §12.2F "thin-film phase" row is native here.
  t2/lubrication: a film on a non-horizontal surface drains under gravity with flux ∝ h³ (thick films flow much faster
     than thin ones). HEAD has no gravity: nothing ever sags. Shallow-water continuity (∂h/∂t = −∇·F) is the one extra
     term the solver implies.
RESCUE (verify): R1 `exp(-pow((d − age*0.085)*34.0, 2.0))` in the click ring — pow with a negative base (inside the
  ring). Replace by `x*x`.
ADD (2):
  1. Angle-dependent thin-film interference (§12.2F, snippet F1 `thinFilm`): replace the fixed IQ-cosine phase by
     R(λ) = cos²(δ/2), δ = 4π·n·d·cosθ_t/λ at λ = 650/550/450 nm, d from `filmHeight` through the existing
     `colorShift` frequency role, cosθ_t from `dot(normal, viewDir)` (already computed). Keep the amplitude factors on the
     term. Default look stays an oil slick; hue now drifts across the frame and along slopes.
  2. Gravity drainage (§12.2D shallow-water continuity): add a flux term in height, `h −= k·(F(h_{y+1}) − F(h_{y−1}))/2`
     with F = h³ along screen-down, k small and scaled by (1 − viscosity·0.7); thick wake rims slump into slow
     teardrops; heights stay clamped; mass is conserved up to the clamp. **Numpy-port it first** (stability + that it
     does something at default over 300 frames) — project memory "Sim CPU Validation".
FORBID on this file: springs, replacing the solver, display-history sparkles, Gray-Scott, a new param, promoting A to
  display RGBA.
A PACKING: raw (unchanged).
```

## 9. gen-audio-reactive-aurora-ribbons  — FIRST PASS (fork D)

```
SHADER: gen-audio-reactive-aurora-ribbons
IDENTITY: flowing aurora curtains over a dark polar sky — 3–7 domain-warped ribbons (wave line × curtain falloff × vertical
  shimmer rays), bass swells amplitude, mids shift hue, treble ionospheric sparkle, mouse shifts the sky, trail persistence.
KEEP VERBATIM: `ribbonField` structure (fbm warp → sinusoid → curtain → shimmer noise at `uv·(24,6)`), ribbon count
  mix(3,7,p2), baseAmp/baseFreq audio mapping, `auroraPalette` hue clock (`fi·0.11 + mids·0.35 + time·0.04 + p1·0.2`),
  treble sparkle, the C trail mix with `p4`, depth fade, `hue_preserve_clamp` + ACES + IGN, premultiplied `col*alpha`
  and its alpha formula, 4 params and roles (ribbon_intensity / ribbon_count / wave_frequency / trail_persistence),
  A = raw HDR trail + bassEnv in .a.
MECHANISM INTERROGATION (§12.1):
  t2 physics: an auroral curtain is a thin emitting sheet seen edge-on: (a) its lower border is razor-sharp and it fades
     slowly upward, (b) emission colour follows altitude — N₂⁺ violet-blue at the very bottom, O 557.7 nm green through
     the body, O 630.0 nm red high up, (c) it is brightest where a fold turns the sheet along the line of sight (longer
     emitting path). HEAD's `exp(−|dy|·k)` is symmetric and colourless in altitude, and every part of the curve is
     equally bright.
  t3 promoted intermediate: `uv.y − wave` (signed altitude above the curve) and the wave's slope are computed or
     computable inside `ribbonField` and discarded; only a scalar comes out. (Remember `uv.y` is DOWN on screen:
     dy > 0 is below the curve.)
HEAD DEFECT (verify): R1 `textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0)` — filtering sampler on rgba32float
  history, `uv01 = pixel/res` off the texel centre → exact `textureLoad(dataTextureC, pixel, 0)`.
ADD (3):
  1. Asymmetric curtain profile (native): sharp falloff below the lower border (dy > 0) and a long soft fade above it
     (dy < 0), same peak value 1 at dy = 0 as HEAD so default brightness at the curve is unchanged.
  2. Altitude emission colour (native, spectral): blend the ribbon's `auroraPalette` colour toward violet-blue (0.35,
     0.35, 1.0) in a thin band below the border and toward red (1.0, 0.22, 0.12) with height above it
     (`smoothstep(0, 0.35, −dy)`); the hue clock and mids shift keep acting on the green body.
  3. Fold limb-brightening (native): multiply the curtain by `sqrt(1 + s²)` (capped) with `s = amp·freq·cos(x·freq + t·0.8 +
     phase)` — the analytic slope of the sinusoid — so steep folds brighten like edge-on sheet; flat stretches stay as HEAD.
FORBID on this file: stars/moon/landscape overlay, a new creature, IQ palette, springs/ripples, scanlines, and **anything
  stamped from the spiral-galaxy card in the same fork** (different ideas, different code).
A PACKING: raw HDR trail + bassEnv in .a (unchanged); ACES on writeTexture.
```

## 10. neon-edge-glow  — 2nd pass (fork E)

```
SHADER: neon-edge-glow
IDENTITY: a gas-discharge neon-tube edge filter — 4-tap luma gradient drawn as emission-line tubes with a dark glass
  sheath, 60 Hz mains flicker, mercury secondary lines, electrode sputter, mouse-bent tube hue, chroma end-shift.
KEEP VERBATIM: the 4-tap `edgeMag`, `neonSpectrum`/`mercurySpectrum` line shapes, mains/flicker model, tube core + dark
  sheath (last pass Idea 1), 60 Hz beat (Idea 2), mouse `bendUV` + hue clock, electrode glow, chroma end-shift,
  atmospheric haze, depth-driven alpha, ACES display, the 4 params and roles (edgeStrength / glowRadius / neonTint /
  intensity), A = the same display RGBA as writeTexture.
MECHANISM INTERROGATION (§12.1):
  t1 deepen the kernel: HEAD's `glow` is a smoothstep band of the SAME 1-px gradient magnitude, so it has no spatial
     spread — `glowRadius` moves a gradient threshold, the halo is 1–3 px, and no light spills onto the wall around the
     tube. A real neon sign casts a soft pool of coloured light around its tube (soft inverse-square from a line source).
  t7 direction: `l, r, t, b` already give the gradient; its perpendicular is the tube tangent, free of charge. A real
     positive column shows standing striations (bright/dark bands) along the tube.
RESCUE (verify): R1 `pow((t − centre)/width, 2.0)` ×6 in `neonSpectrum`/`mercurySpectrum` — a NEGATIVE base for every
  t below a line's centre (up to ~35–70 % of the hue range): undefined in WGSL, NaN on some GPUs. Replace by squares.
ADD (2):
  1. Spill glow by soft inverse-square gather (§12.2F soft inverse-square, "deepen the kernel"): a 12-tap two-ring gather
     (6 + 6 taps, radii ∝ `glowRadius` in px scaled by res.y/1080) of local edge strength — a cheap `|luma(tap) − luma(c)|`
     proxy is fine — weighted 1/(d² + r0²), added in the tube's own `neonColor`, so light spills onto the surroundings.
     `glowRadius` keeps its role (bigger = wider spill), now in real pixels. Energy stays bounded: the spill is added to
     the dark-sheath-darkened base, not stacked on top of an already-saturated tube.
  2. Positive-column striations (native gas discharge): bands travelling along the local tube tangent,
     `phase = dot(pixelPos, tangent)/period − time·v` with period ≈ 12–18 px, amplitude ≲ 0.25 on `tubeCore` only,
     faded where edgeMag is low; `v` and amplitude ride the existing `flicker`/mains terms. Curved edges will show the
     projected phase wrapping — check crops at 3× and mask by coherence if it looks like noise.
FORBID on this file: IQ palette, holographic scanlines, springs/ripples, raymarch, replacing the 4-tap kernel, new params.
A PACKING: ACES display RGBA (unchanged).
```
