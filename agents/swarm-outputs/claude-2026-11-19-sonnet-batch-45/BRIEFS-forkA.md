# BRIEFS fork A — conv-steerable-pyramid, conv-anisotropic-diffusion (both SECOND pass)

Written before any WGSL edit. HEAD = origin/main 8c537fe6. Harness: `agents/mr.mjs` / `agents/mr_perf.mjs` patched with `SRC=tex` (oriented gratings in 4 quadrants, thin bright/dark ridge lines, checker steps, ±0.07 speckle + salt/pepper) and `RIPPLES="x,y,elapsedSec;…"`.

HEAD measurements that shaped the cards (256², 6 frames, defaults):
- conv-anisotropic-diffusion: mean|out − ACES(src)| per channel R,G,B = 0.0048 / 0.0192 / 0.0046; Laplacian (noise) energy src 0.273 → HEAD 0.259. The speckle is untouched and only G is diffused: the "CA" line overwrites R and B with raw source samples (`finalColor = vec3(rSample, finalColor.g, bSample)`).
- conv-steerable-pyramid: 6 × `steerableFilter` = 6 × 121 taps = 726 texture samples + 726 g2/h2 basis evals per pixel; the four bands (and the two CA bands) re-fetch the same neighbourhood and recompute the same basis for every orientation.

---

## SHADER: conv-steerable-pyramid
IDENTITY: a four-orientation steerable G2/H2 band bank (0/45/90/135° + steer), quadrature energy per band, coloured by an orientation palette, mouse/bass/ripple steered, blended with the source — it must still read as "an orientation decomposition of the photo".
KEEP VERBATIM: `g2Basis`/`h2Basis`, the cos2T/sin2T steering mix, `steerableFilter`'s radius rule (`min(ceil(3σ),5)`), σ/responseScale/colorBoost/mouseInfluence param roles + mappings, depth-σ and depth-factor, bass steer + mouse angle + ripple steer + `time*0.15`, the three palettes (`pal0/45/90`) and their magnitude-weighted mix, CA (`b0_r`,`b90_b`), `mix(color, src*(0.55+total*0.35), 0.28)`, treble boost, C feedback `0.07*(1+mids)`, ACES, depth boost, alpha = |b135| semantic, depth passthrough; HEAD ideas "H2 quadrature energy" and "source-tied reconstruction".
MECHANISM INTERROGATION:
- tactic 1 (deepen the kernel): a *pyramid* has levels; HEAD evaluates one scale (depth-modulated σ). The next-better approximation of the same decomposition is a second octave built from the same kernel — the à-trous (dilated) version: the identical 11×11 weights over taps spaced 2 px apart ≈ the filter at 2σ. No new basis, only 121 more samples, and the loop already shares them.
- tactic 3 (promote an intermediate): `steerableFilter` computes the quadrature pair (evenR, oddR) and throws both away into `sqrt(even²+odd²)`. The pair carries *local phase* φ = atan2(odd, even): ridge vs edge, bright vs dark, rising vs falling edge — the classic reason a steerable pyramid has an H2 partner at all.
- tactic 2 (physics): HEAD's colour is |response| only, so a light line, a dark line and a step edge of equal contrast get the same hue.
- tactic 6 (history): C is already read for 7 % feedback; no change.
ADD (2 native ideas):
  3. **Local-phase polarity** — per band φ_k = atan2(odd_k, even_k) from the pair HEAD already computes; palette index gets `+ 0.12·sin φ_k` (rising vs falling edges rotate the existing palette), and the dominant band's ridge polarity `−cos φ` lifts bright ridges / ducks dark ridges (`color *= 1 + 0.3·pol·share`). Why here: the shader is literally a quadrature bank that was discarding the quadrature.
  4. **Second octave (à-trous, 2× tap spacing)** — a coarse level's four band magnitudes, coloured by the same three palettes rotated +0.33 in index (scale-coded hue), mixed under the fine level by an energy competition `0.6·Ec/(Ec+Ef)`: broad oriented structure gets its own tint, fine hatching keeps the HEAD palette. Why here: it is the "pyramid" in steerable pyramid.
FORMULA ADMISSION: no §12.2 row is consumed (the structure-tensor row is deliberately NOT used so fork A's second file can own it if it wants). Family match: image-conv band bank; operates on what exists (the (even, odd) accumulators and the same g2/h2 basis values per tap); deletion test both ways: remove either → exactly HEAD; keep only the idea (no G2/H2 bank) → no band colours at all, so it cannot replace the mechanism.
PERF PLAN (not an idea): one tap loop evaluating g2/h2 once and the four orientations as a vec4 (kernel = `(g2.x−g2.z)·cos2θ + g2.y·sin2θ`), fetching centre / +CA / −CA / coarse = 4 samples per tap = 484 samples vs HEAD 726, basis 121 vs 726. HEAD outputs must be reproduced to fp tolerance by the refactor *before* the ideas go in (checked by diffing renders).
FORBID on this file: springs, new palettes as the look, Gabor/structure-tensor coherence colouring, glow/bloom, IQ palette on top.
RESCUE: ripple wave uses `pow(neg, 2.0)` (undefined for negative base → NaN on some backends) → `q*q`.
A PACKING: ACES display RGBA, alpha = |b135|-semantic (unchanged).

---

## SHADER: conv-anisotropic-diffusion
IDENTITY: Perona–Malik edge-stopping diffusion that melts the photo into flat oil-paint regions along (not across) edges; mouse is a heat source, ripples are diffusion fronts; alpha is the diffusion-coefficient process map.
KEEP VERBATIM: `diffusionCoefficient`, `tukeyConductivity`, the 0.45 Tukey/exp mix, depth-κ, κ/dt/iterations/mouse param roles + mappings, bass `audioDt`, mouse `mouseBoost` on dt, ripple `rippleBoost` on dt, `followH/followV` (HEAD idea "4-neighbor coherence boost"), `paintBoost` mix, 0.15 C accumulation, CA-on-edges (the *intent*: `caOffset = edgeMag·0.025`), ACES, alpha = avg conductivity × (1 − 0.4·depth), depth passthrough; HEAD ideas "Tukey biweight conductivity" and "4-neighbor coherence boost".
MECHANISM INTERROGATION:
- tactic 1 (deepen the kernel): PM's well-known failure is that speckle looks like an edge (gradient from a single noisy pixel > κ), so noise is *preserved*. The textbook cure is Catté–Lions: take the conductivity from a pre-smoothed gradient. The 3×3 neighbourhood gives that for free: smooth along the edge (3 taps in the orthogonal direction), then difference. HEAD measurably leaves speckle intact (HF 0.273→0.259).
- tactic 4 (second-order the parameter): κ (Edge Threshold) is one scalar; the "heat source" already accelerates dt, but a barrier edge stays a barrier no matter how fast you diffuse. Hot paint softens its own edge barriers: κ should rise near the cursor / on a ripple front.
- tactic 1 again (stencil): the 5-point (N/S/E/W) PM stencil has axis bias (diagonal edges stair-step); the 9-point version (diagonals at ½ weight, gradient/√2) is the isotropic next step, and the diagonal taps are the same ones Catté–Lions needs.
- tactic 3: `edgeMag` (|center − current|) is HEAD's CA driver; unchanged.
ADD (3 native ideas, all from the same 4 extra taps / no new state):
  3. **Catté–Lions regularised conductivity** — per direction, gradient = `mix(raw, |rowOrColAvg(neighbour side) − rowOrColAvg(centre side)|, 0.65)` using the diagonal taps, fed to HEAD's own conductivity + Tukey mix. Noise below the edge scale now conducts; true edges (full-height steps) are unchanged. Why here: it is the standard repair of the very conductivity function this shader is built on.
  4. **Heat-melted edge threshold** — `κ_local = depthKappa · (1 + 2.5·mouseFactor + 1.5·rippleFront)`: edges soften where the heat/diffusion front is, so the paint actually drips *across* edges at the cursor instead of only converging faster to the same edge-limited state. Why here: Mouse Heat keeps its role, now physically hot.
  5. **Nine-point stencil** — four diagonal fluxes `c(|d−cur|/√2)·(d−cur)·½`, total rate renormalised by 4/6 (×0.7) so the default melt speed is unchanged; diagonal edges stop stair-stepping. Why here: PM *is* a discretised PDE; this is the isotropic stencil.
FORMULA ADMISSION: idea 5 = §12.2D "Isotropic 9-point Laplacian" (this shader is a diffusion solver → family D: one extra term, same solver); ideas 3/4 are tactic 1/4 (no table row); no structure-tensor row used. Each consumes quantities the file already fetches/computes (neighbour colours, κ, mouseFactor, rippleFront). Deletion test: delete any → exactly PM oil paint; keep an idea without PM → nothing.
RESCUES (HEAD defects, not ideas):
  R1. `finalColor = vec3(rSample, finalColor.g, bSample)` threw away the diffusion in R and B (HEAD diffuses only G). Now CA adds the *source's* shifted detail on top of the diffused channels (`+ (src(uv±off) − center)`), which vanishes at flats exactly as an edge-CA should.
  R2. `pow((rDist − …)·15.0, 2.0)` with negative base → `q*q`.
  R3. `effectiveDt` has no stability bound: mouse (×≤6) × ripple (×≤4) × audio (×1.8) × dt(≤0.25) overshoots past the neighbour mean. Update is clamped to a convex step (`k·Σw ≤ 0.95`); identical at default dt, only changes the overshoot regime.
  R4. Loop-invariant work hoisted (4 neighbour taps, mouse and the 50-ripple loop were redone every iteration); `max(finalColor, 0)` before ACES (the 1.15 `paintBoost` extrapolation and the CA delta can go negative; catalog ACES maps negatives to bright).
FORBID on this file: springs, bloom, neon edge pop, IQ palette, any new colouring, Gray-Scott, replacing the diffusion with a blur.
A PACKING: ACES display RGBA, alpha = diffusion-coefficient process map (unchanged).

---

## Coordinator-facing de-dup (fork A)
§12.2 rows used: conv-anisotropic-diffusion → "Isotropic 9-point Laplacian" (D). conv-steerable-pyramid → none. No shared formula between the two files. Neither file receives a spring / ripple overlay / IQ palette (both already own ripples + mouse; neither gets new ones).

---

## AMENDMENT (after measurement; cards above were written first and stay as written)

**conv-steerable-pyramid — Idea 3 changed from "phase polarity" to "line-vs-edge phase classing".** Measuring HEAD showed `corr(b0,b90) = 1.000` and `b135 ≡ b45`: HEAD's steering mix `(g2.x−g2.z)·cos2θ + g2.y·sin2θ` is a pure quadrupole (no isotropic term, cos2θ doubled), so band θ+90° is the exact *negative* of band θ (even0 = −even90, odd0 = −odd90; 0°/90° are also 2.2× stronger than 45°/135°). Consequences: (a) bright-vertical-line and dark-horizontal-line give identical responses, so the SIGN of the phase (polarity, rising/falling) is undefined with this kernel; (b) the four "orientation" bands carry two independent magnitudes. I built the exact steering (G2 with isotropic term; G3 with the missing 4th cubic basis term) and it works (four independent bands), but at default params it lowered mean saturation ~30 % (balanced bands average the 0/.33/.67 palette toward grey whereas HEAD's bias gave an accidental cast) and, being a kernel change, it violates KEEP VERBATIM. **Not shipped**; flagged for the coordinator. Idea 3 therefore uses `|odd|/m` (sign-invariant, well defined with HEAD's kernel): bars (even-dominant) and step edges (odd-dominant) get different palette-index offsets (`0.3·(edgeness−0.5)`). The ridge-polarity luminance lift was dropped with it.
**conv-anisotropic-diffusion — rescue R1 gated; Idea 4 gain raised.** The un-gated CA delta re-injected removed noise into R/B (caOffset follows `|center − current|`, the amount of melt, largest on noise): HF energy went *up*. The delta is now multiplied by `edgeGate = smoothstep(2κ, 5κ, max regularised edge strength)`. Idea 4 gain went from `2.5/1.5` to `4.0/2.0` after the 2.5 version measured as barely visible.
