# BRIEFS — fork D (sonnet/batch-40): gen-sonoluminescent-chrono-geode-matrix, gen-crystalline-chrono-dyson

Written BEFORE any WGSL edit. HEAD = origin/main 0761b6b9. Both files are second-pass (already have `Ideas:` lines); earlier ideas are KEEP VERBATIM.

## HEAD renders (SwiftShader, 192 px, saved-default sliders, SRC=img, 20–30 frames; looked at the PNGs)

| file | case | meanL | stdL | meanA | frameMs | nan | what the picture is |
|---|---|---|---|---|---|---|---|
| sonoluminescent (0.5,0.5,0.5,0.5) | idle | 0.166 | 0.179 | 0.175 | 122 | 0 | pale-blue faceted crystal ball on navy; iridescent scribble; strata/twins/pearls not individually readable |
| | held cursor 0.4,0.6,1 | 0.172 | 0.192 | 0.175 | 283 (load) | 0 | same, shards pushed |
| | audio 0.8,0.5,0.9 | 0.704 | 0.150 | 0.181 | 269 (load) | 0 | whole frame washed blue-white at that flash phase (kick=2 → flash ≈ 5×) |
| dyson (4,1.5,1,50) | idle | 0.250 | 0.312 | 0.277 | 2324 | 0 | rotating lattice of tilted crystal plates, cream quasar disc, conduit ring + spokes, statites, stars — reads well, NOT broken |
| | held 0.4,0.6,1 | 0.242 | 0.306 | 0.267 | 1751 | 0 | camera orbit |
| | audio | 0.313 | 0.336 | 0.301 | 1417 | 0 | brighter ring/spokes |

Dyson HEAD is ~2 s/frame at 192² on SwiftShader (100-step march, worley + fbm domain warp inside map). **Anything added must live in the hit-shading branch, not in the march loop.**

---

## SHADER: gen-sonoluminescent-chrono-geode-matrix

IDENTITY: a fast-orbiting, fractured crystal geode around a bubble core that implodes once per acoustic cycle in a blue-white flash, launching a ballistic shock shell through the shards.

KEEP VERBATIM: four sliders and roles (Intensity / Speed / Scale / Mouse Influence, no saved `params`, defaults 0.5 each from `x-meta.upgrade.params`); `sdGeodeShell` KIFS fold + noise-churned core SDF; closed-form orbital camera + eased `warpTime`; `collapse = exp(-7φ)` flash envelope, `regrow` radius, ballistic `ringR`; stateless `kick = min(2.5·bass, 2)`; Idea 1 shock jolt/ignition band, Idea 2 agate strata, Idea 3 thin-wall translucency, Idea 4 pearl chains, Idea 5 twinning glints; swirl-advected `dataTextureC` history (decay 0.86, HDR clamp 5.0, exact `textureLoad`); ACES on display only; A = raw HDR history + semantic alpha.

### §12.1 mechanism interrogation
- Tactic 1 (kernel): the flash envelope is a one-pole `exp(-7φ)` after a single collapse. The next-better approximation of the same operator is the Rayleigh–Plesset bubble: after the main collapse the wall rebounds and re-collapses with decaying amplitude.
- Tactic 2 (physics one step further): a real sonoluminescing bubble (a) afterbounces — R(t) rings down through two or three smaller collapses, each emitting a weaker flash; (b) launches a shock that *heats* what it crosses — shock-heated solid incandesces and cools along a blackbody ramp (white-hot → orange → red) behind the front. HEAD has the front and its band but nothing remains behind it.
- Tactic 3 (promote an intermediate): `ctx.flashPhase` and `ctx.ringR` already exist; "time since the front passed this wall" = φ − r/(5+3·kick) is one subtraction on them.
- Tactic 6 (history): C is read as HDR colour with swirl advection — ember written into `col` rides that trail for free; no change to packing.

### ADD
1. **Rayleigh–Plesset afterbounce** (native: bubble dynamics) — `coreR` ring-down dips at φ ≈ 0.20 and 0.38 and a secondary flash (0.40× then 0.16× of the primary) on each. Acts in `main()` where `ctx.coreR` / `ctx.flash` are built. Deletion test: still a one-collapse sonoluminescent geode; mechanism-only test: no geode → not this effect.
2. **Shock-heated ember afterglow with blackbody cooling** (§12.2F Rayleigh/blackbody, Wien form at 650/550/450 nm) — geode wall inside `ringR` keeps incandescing, `T = 1700 + 5200·heat`, `heat = exp(−5·age)`, `age = φ − r/(5+3·kick)`. Inner walls (crossed earliest) are dimmer/redder than the freshly crossed outer wall: a cooling gradient behind the front. Extends Idea 1 (ignition band) into its physical aftermath.

FORBID: springs, click ripples, IQ palette, any new param, a second tear/strobe system, replacing the core with a different creature.
A PACKING: unchanged — raw HDR history RGB (pre-ACES, ≤ 5.0) + semantic alpha.

### RESCUES (not ideas)
- **R1 — flash phase scrubbed by audio (suspected, confirm by measurement):** `flashRate = 0.8 + 1.2·speed + 0.6·bass`, `flashPhase = fract(animTime·flashRate)`. `animTime = time·rate` is large (10²–10³ after minutes), so any frame-to-frame change of `bass` shifts the phase by `animTime·0.6·Δbass` cycles → under live audio the flash re-triggers at random every frame (strobing, the same family as batch-30's "frame-hash strobing"). Fix: phase from the bass-free rate (identical at bass = 0); bass still drives `kick` amplitude and `ringR`.
- **R2 — `pow` with a negative base (suspected):** `pow((pearlPhase − 0.5)·7.0, 2.0)` is negative-base for half of every period (WGSL: undefined; GPUs lower it to exp2(y·log2 x) → NaN); `pow(1.0 − max(dot,0.0), 3.0)` can see base −1e-7 on an exactly face-on normal. Fix: `x*x` and `max(1.0 − dot, 0.0)`.

---

## SHADER: gen-crystalline-chrono-dyson

IDENTITY: a slowly rotating crystalline Dyson shell of tilting louvred KIFS plates around an audio-reactive quasar, with a statite swarm, a power-grid of spokes and conduit ring, an orbiting mouse camera.

KEEP VERBATIM: four params and roles (Panel Density → plate repetition; Quasar Glow → core light + packet/louvre intensity; Flux Speed → the clock `dysonClock()`; Swarm Count → statite count); the whole `map()` smin chain (panels / quasar / KIFS / conduit / statites / spokes); statite swarm (Idea 1), grid packets + halo (Idea 2), louvres (Idea 3), tick-crowns (Idea 4), twin seams (Idea 5); flat Beer–Lambert blue subsurface + `spectralGlow`; fog; integer-offset chromatic C feedback; ripple spectral glow; A = clamped HDR (≤ 8) + semantic alpha; ACES on `writeTexture` only.

### §12.1 mechanism interrogation
- Tactic 1: HEAD's "crystal" is shaded like opaque metal + a flat blue Beer–Lambert term; the next-better approximation of a crystal plate is a *refracting* plate whose transmitted ray is dispersive (Snell + Cauchy), so the quasar's image seen through each plate is colour-fringed.
- Tactic 2: a chronometer's first-order artifacts are the escapement beat (the seconds hand steps with spring overshoot, not smoothly) and lume (luminous paint charged by light, glowing with an exponential afterglow). HEAD has the tick marks but no hand and no lume.
- Tactic 3 (promote an intermediate): `lon = atan2(q.z, q.x)` (tick crown), `coreDir`, `onShell`, `n`, `rd` are all computed in the hit branch already; both ideas consume only those.
- Tactic 6: C history is colour; nothing to change.

### ADD (numbered after the file's existing in-body Ideas 1–5)
6. **Cauchy-dispersed plate transmission** (§12.2F Cauchy dispersion + Snell vector refraction) — on `onShell` hits refract the view ray per channel with n(λ)=A+B/λ² (650/550/450 nm), test each refracted ray against the quasar's angular disc (`asin(0.5/dist)`), light the plate with the per-channel coverage → coloured fringes of the quasar seen through each tilted plate. Louvre tilt now has an optical consequence.
7. **Lume sweep hand** (native: chronometer dial) — an escapement-stepped seconds hand (60 beats per revolution, spring overshoot `1 − e^{−14f}·cos(38f)`) charges lume on the tick crown (strong) and the shell plates (faint) with exp afterglow trailing behind it (green-cyan strontium-aluminate tint). Extends Idea 4 without replacing the scrolling ticks.

FORBID: springs, extra ripple fronts, IQ palette beyond the existing `spectralGlow`, any new param, anything in the 100-step march loop, replacing plates with a different material.
A PACKING: unchanged — clamped HDR linear RGB (pre-ACES) + semantic alpha.

### RESCUES / truth fixes
- **Header truth:** the `Ideas:` line lists only the tick-crowns and twin seams; the body also carries statite swarm, power-grid packets, louvred plates (Ideas 1–3). Append them to the line (additive).
- **Fresnel hardening:** `pow(1.0 − cosTheta, 5.0)` — base can be −1e-7 when `dot(n,v)` overshoots 1 by an ulp; `max(…, 0.0)`.
- Nothing else found broken: render is a readable lattice at every case; no audio-from-C, no `ripple.w`, Y-flip already fixed, alpha semantic. Premise confirmed (no rescue of the picture needed).

### Row budget
Sonoluminescent: blackbody (§12.2F) + native bubble dynamics. Dyson: Cauchy dispersion + Snell (§12.2F) + native chronometer. No row shared between the two files.
