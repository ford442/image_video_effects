# NOTES fork A — conv-steerable-pyramid, conv-anisotropic-diffusion (second pass)

Harness: `agents/mr.mjs` / `agents/mr_perf.mjs` (SwiftShader), patched with `SRC=tex` (oriented gratings in 4 quadrants, thin bright/dark ridges, checker steps, ±0.07 speckle + salt/pepper) and `RIPPLES="x,y,elapsedSec;…"`. Real-GPU look: NOT done. Cards + mechanism interrogation: `BRIEFS-forkA.md` (with an AMENDMENT for what measurement changed).

## conv-steerable-pyramid
SHADER: conv-steerable-pyramid
IDENTITY: four-orientation steerable G2/H2 band bank, quadrature energy, orientation palette, mouse/bass/ripple steered, blended with the source
KEEP VERBATIM: g2Basis/h2Basis bodies + HEAD's steering mix, radius rule, σ/response/boost/mouse param roles, depth σ/factor, bass+mouse+ripple steer, 3 palettes + magnitude-weighted mix, CA bands, source-tied reconstruction (0.28), treble, C feedback, ACES, depth boost, alpha = |b135| semantic, depth passthrough. HEAD ideas "H2 quadrature energy", "source-tied reconstruction".
ADD:
  3. line-vs-edge phase classing — `edgeness = |odd|/m` per band from the (even, odd) pair HEAD already computed and discarded; palette index `+ 0.3·(edgeness − 0.5)`: bars (even-dominant) and step edges (odd-dominant) of equal contrast get different hues. Sign-invariant on purpose (see finding below). `// ── Idea 3` in main.
  4. second à-trous octave — the same g2/h2 weights over taps spaced 2 px apart (≈ filter at 2σ), 4 band magnitudes; three palettes with index +0.33 (scale-coded hue) mixed under the fine layer by `0.6·Ec/(Ec+Ef)` energy competition. `// ── Idea 4` in the tap loop (sample + accumulators) and in main (colour).
FORBID: springs, new palettes as the look, Gabor / structure-tensor coherence colouring, glow, IQ palette. None added.
A PACKING: ACES display RGBA (unchanged); alpha unchanged (|b135| semantic, bit-identical vs HEAD with ideas ablated).
FORMULAE: no §12.2 row (tactic 1 deepen kernel → second octave; tactic 3 promote an intermediate → phase). Structure-tensor row deliberately unused.
RESCUES / structural:
  - ripple wave `exp(-pow(neg, 2.0))` → `exp(-rq*rq)` (pow with a negative base is undefined).
  - perf: HEAD called `steerableFilter` 6× (b0/b45/b90/b135 + 2 CA bands) = 726 texture samples + 726 g2/h2 evals per pixel; now one tap loop, basis evaluated once, 4 orientations as a vec4 lane each, 4 samples/tap (centre, +CA, −CA, coarse) = 484 samples. With both ideas ablated the output equals HEAD (max |Δ| 1.4e-4 default, 3e-4 mouse+audio).
FINDING NOT FIXED (coordinator decision): HEAD's steering `(g2.x−g2.z)·cos2θ + g2.y·sin2θ` (and the same mix on h2) is a pure quadrupole: band θ+90° is the exact negative of band θ, so `corr(b0,b90) = 1.000`, `|b135| ≡ |b45|`, 0°/90° are 2.2× the 45°/135° level (mean 0.299/0.135/0.299/0.135), and bright-vertical ≡ dark-horizontal. The bank is 2 independent bands, and `b135` (alpha) duplicates `b45`. I built the exact version (G2 = ½(Gxx+Gyy)+½(Gxx−Gyy)cos2θ+Gxy sin2θ; G3 with the missing `y³−3y s²` term; ×0.5 to keep response level): 4 independent bands (corr −0.07, means 0.45/0.45/0.46/0.44 before ×0.5). It lowered default-params mean saturation 0.164 → ~0.13 (balanced bands average the 0/.33/.67 palette toward grey) and is a kernel change, so it was not shipped. A follow-up would also weight the palette mix by |b|² and add a 4th palette for b135.
Diff vs HEAD @256² defaults (6 frames, SRC=tex): 40.3 % px > 12/255 (mean |Δ| 0.028); removing Idea 3 alone changes 17.8 %, removing Idea 4 alone 15.5 %. mean saturation 0.164 → 0.144, stdL 0.063 → 0.064, alpha mean 0.343 → 0.342. Stress (mouse down, audio 0.9/0.6/0.8, two ripples, max params): 0 NaN, ripple-steer swirls preserved.
Timing (load 14–19, min-of-drained, 4 interleaved rounds, 192²): per-round 0.67 / 0.36 / 0.41 / 1.01 → median 0.54× (cheaper than HEAD even with the second octave).

## conv-anisotropic-diffusion
SHADER: conv-anisotropic-diffusion
IDENTITY: Perona–Malik edge-stopping diffusion that melts the photo into flat oil-paint regions; mouse = heat source, ripples = diffusion fronts, alpha = diffusion-coefficient process map
KEEP VERBATIM: diffusionCoefficient, tukeyConductivity, the 0.45 Tukey/exp mix, depth κ, κ/dt/iterations/mouse param roles, bass audioDt, mouseBoost and rippleBoost on dt, followH/followV, paintBoost, 0.15 C accumulation, the intent of CA-on-edges, ACES, alpha = avg conductivity × (1−0.4·depth), depth passthrough. HEAD ideas "Tukey biweight conductivity", "4-neighbor coherence boost".
ADD:
  3. Catté–Lions regularised conductivity — per direction the gradient fed to HEAD's own conductivity is `mix(raw, |3-tap row/col mean (neighbour side) − 3-tap mean (centre side)|, 0.65)` using the diagonal taps. Noise below the edge scale conducts; a full-height step is unchanged. `// ── Idea 3` in the loop.
  4. heat-melted edge threshold — `meltKappa = depthKappa·(1 + 4.0·mouseFactor + 2.0·min(rippleFront,1))`: the heat source and ripple fronts soften edge barriers instead of only converging faster to the same edge-limited state. `// ── Idea 4`.
  5. nine-point stencil — four diagonal fluxes `c(|d−cur|/√2)·(d−cur)·½`, total rate renormalised ×0.7 (4/6) so the default melt speed is kept (§12.2D "Isotropic 9-point Laplacian"). `// ── Idea 5`.
FORBID: springs, bloom, neon edge pop, IQ palette, new colouring, replacing diffusion by a blur. None added.
A PACKING: ACES display RGBA, alpha = diffusion-coefficient process map (unchanged meaning; values rise because conduction is now higher on noise/near heat — alpha mean 0.25 → 0.32 at defaults).
FORMULAE: idea 5 = §12.2D isotropic 9-point; ideas 3/4 = tactics 1/4. No structure-tensor row (fork A's other file does not use one either).
RESCUES (all four are HEAD defects):
  R1. `finalColor = vec3(rSample, finalColor.g, bSample)` overwrote R and B with RAW source samples, so only green was ever diffused (|out−src| R,G,B = 0.005/0.019/0.005 at defaults). CA now adds the source's shifted detail on top of the diffused channels (`+ edgeGate·(src(uv±off) − center)`), gated by `edgeGate = smoothstep(2κ,5κ, regularised edge strength)` because caOffset follows `|center − current|` (the amount of melt, largest on removed noise) and an un-gated delta re-injected that noise (HF energy went UP before gating). Now R/B diffuse: 0.033/0.025/0.033.
  R2. `exp(-pow(neg, 2.0))` in the ripple front → `exp(-rq*rq)`.
  R3. no stability bound: dt(≤0.25) × audio(≤1.8) × mouse(≤6) × ripple(≤4) × Σ(c·follow ≤ 5.4) pushed the explicit step past 1. At Mouse Heat 1 + bass 1 HEAD renders a saturated green/magenta speckle blob around the cursor (2.9 % of px at 0/1, mean|Laplacian| 0.255); the update is now a convex step (`min(effectiveDt, 0.95/Σw)`): 0.3 % saturated, mean|Laplacian| 0.125, no blob. Without the clamp the new ideas diverge worse (24 % saturated), so it is load-bearing. Identical at default dt (all-off variant ≡ HEAD bit-exact: max|Δ| 0.0).
  R4. hoists (4 neighbour taps, mouse, the 50-ripple loop were redone every iteration) and `max(finalColor,0)` before ACES (paintBoost 1.15 extrapolation and the CA delta can go negative; catalog ACES maps negatives bright).
MEASURED (256², SRC=tex, 6 frames; robust MAD noise std in flat noisy blocks, R/G/B):
  - κ slider 0.3, dt 0.8, iter 1.0, mouse off: dark block src 0.070/0.066/0.059 → HEAD-equivalent 0.070/0.066/0.059 → all changes 0.051/0.045/0.046; with Idea 3 off 0.067/0.061/0.059 (Idea 3 alone is −24 %/−25 %/−23 % residual noise at κ 0.3, −17 % at 0.4, −7 % at 0.5; it is invisible once κ ≫ noise).
  - aggressive (0.6,0.8,1.0,0.5): dark block src 0.076/0.069/0.064 → HEAD 0.054/0.060/0.046 → new 0.039/0.034/0.034.
  - edge contrast across the checker boundary kept 93 % (HEAD 98 %) — the price of ideas 3+5.
  - Idea 4: grating contrast near/far from the cursor 0.98 (with) vs 1.01 (without) vs 1.04 (HEAD); mild by design — strong edges (ΔL 0.7) stay blocked even at κ×5.
Diff vs HEAD @256² defaults (mouse centre, 6 frames): 18.2 % px > 12/255 (mean |Δ| 0.022). Ablation (idea removed alone): Idea 3 3.5 %, Idea 4 3.7 %, Idea 5 1.5 %, CA gate/R1 13.8 %, clamp 0.2 % at defaults (it matters only in the mouse/audio/ripple regime).
Timing (load 14–23, min-of-drained, 4 interleaved rounds, 256²): defaults (3 iter) median 1.06× (0.63–1.7), 5 iterations 0.84× (0.57–1.96), 1 iteration 1.08× (0.75–2.05). Under the ≤1.3× cap by medians; per-round noise is large (box load).

## Gates
`wgsl_precommit_gate.py --files` 2/2 (pasted headers 0, extraBuffer violations 0); `verify-naga-wasm.mjs --files` 2/2 valid; `audit_dead_sliders.py --files` 0 new dead sliders (all 4 sliders read in both files: `zoom_params.x/y/z/w`); `audit_extrabuffer.py` PASS (no extraBuffer use). JSON: `description` appended only (text edit), `params` byte-exact, `features` untouched, no new keys. Not done: real-GPU look, `upgrades:record`, shader lists, `verify:shaders:fix`, commit (coordinator).

## Coordinator-checklist self-check
- Cards before diff: yes (`BRIEFS-forkA.md`; amendment appended for the two measured changes). Each idea pointable via `// ── Idea n`.
- No §12.2 row on more than two files in fork A (one row on one file). No spring/ripple/IQ overlay added to either file.
- Diff composition: pyramid +87/−24 mostly the bank loop + two idea blocks; anisotropic +101/−49 ideas + rescues + hoist; no header/ACES boilerplate churn.
- Packing unchanged for both.
