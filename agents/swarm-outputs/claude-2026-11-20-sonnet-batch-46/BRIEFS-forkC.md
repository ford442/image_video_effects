# BRIEFS — fork C (sonnet/batch-46): ethereal-swirl-coupled, hybrid-chromatic-liquid

Written BEFORE any WGSL edit. HEAD = origin/main 673d780a. Both files are **first pass** (no `Ideas:` line).

---------------------------------------------------------------------------------------------------

## 1. ethereal-swirl-coupled  (`public/shaders/ethereal-swirl-coupled.wgsl`, advanced-hybrid)

### HEAD findings (rescues — each verified by reading the code and by rendering HEAD)

| # | HEAD defect | Evidence | Rescue |
|---|---|---|---|
| R1 | **`fbm` hashes the continuous coordinate** (`hash2(p*freq)`) → per-pixel white noise, so the "clouds" are grain. Sibling `ethereal-swirl.wgsl` already fixed this exact bug (Idea 1 there). | `hash2` multiplies by (123.456, 789.012) then `fract`: sub-pixel period. HEAD render is speckled. | `fbm` octaves use smooth value noise on an integer lattice (`vnoise`, body-identical to the sibling's). Plain octaves only — the sibling's *billow* octaves are the sibling's idea and are NOT copied. |
| R2 | **Mouse-history texel is clobbered.** `A(0,0)` is written with the mouse, then overwritten a few lines later by the fluid store for every pixel incl. (0,0) → `prevMouse = C(0,0).xy` = `vel` at the corner = 0 → `mouseVel = mousePos*60` every frame: the cursor injects maximum velocity + vortex while merely *hovering*. | read of `textureLoad(dataTextureC,(0,0)).xy` vs unconditional `textureStore(dataTextureA, gid, vec4(vel,…))` | single writer: texel (0,0) of A holds `(mouse.xy,0,0)`, every other texel holds fluid state. First frame (prev == (0,0)) is treated as "no history" → zero velocity. Corner texel sits inside the `edgeDamp` zone, so no visible fluid is lost. |
| R3 | **Feedback reads the fluid state as colour.** `prevFrame = C.rgb` = `(vel.x, vel.y, vel.x−vel.y)` ≈ 0, so `mix(blended, prevFrame, persistence)` is just *fade to black by persistence* (HEAD default mean luma 0.205 vs the picture it should show). A packing lie (A holds fluid, C read as colour). | HEAD render dim; `persistence`=0.5 → 0.475 darkening | Truthful packing: `A = (vel.x, vel.y, trail luma, dye density)`; the old fake "vorticity" in `.z` (read by nothing) becomes the **display-luma history**, advected with the fluid. Persistence now trails luminance along the flow instead of darkening. |
| R4 | `textureSampleLevel(dataTextureC, u_sampler, …)` — filtering sampler on `rgba32float` history. | contract §3 | exact `textureLoad` + hand bilinear (`loadHistory`, body-identical to sibling) |
| R5 | `audio-reactive` claimed in JSON/header but `plasmaBuffer` is never indexed. | grep | bass → vortex-injection gain (×(1+0.4·bass)); mids → additive flow-phase push. Never `config.y`. |
| R6 | alpha hardcoded `1.0`; no ACES on display. | contract §3 | alpha = swirl/dye coverage; ACES on display RGB (×1.1 like the sibling). |

Default-look consequence (flag for user): picture is no longer dimmed to ~half; clouds are smooth not grain; hovering the cursor no longer pins the fluid at max speed.

### IDEA CARD
```
SHADER: ethereal-swirl-coupled
IDENTITY: hsv fractal-swirl clouds laid over the photo, coupled to a viscous mouse-driven fluid that
  advects the swirl field and tints the footage with absorbed dye.
KEEP VERBATIM: 4 params + their (overloaded) roles: x cloudScale/viscosity, y flowSpeed/mouseRadius,
  z colorSpeed/colorShift, w persistence/vortexStrength; semi-Lagrangian advection (2 px · vel back-trace),
  viscosity decay, mouse drag + vortex injection, click-ripple loop (config.y count), edge damp, ±0.5 clamp,
  dens clamp 0..2; baseFlow/turb/flowVec/depthWarp/distortedUV structure; cloudBase/cloudDetail mix;
  hsv hue = fract(distortedUV…); cloud-over-photo blend gated by luminance; dye absorption tint (1,0.85,0.6).
ADD (3 native ideas):
  1. Vorticity confinement + curl-tinted hue (§12.2D "Vorticity confinement", snippet D1) — the header sells
     "vortex streets", but the viscous decay damps every small vortex; re-inject N×ω from the curl of the stored
     velocity (C.xy, exact loads). The same real curl (HEAD stored a fake `vel.x−vel.y`) nudges the cloud hue so
     vortex cores read as colour.
  2. Two-way coupling: swirl wind stirs the fluid, dense cloud seeds dye — `flowVec` and `cloudDensity` are
     computed every frame and thrown away; the fluid only ever feeds the swirl, never the reverse. Body force
     `vel += flowVec·k`, dye `dens += cloudDensity·luma·k'`. Makes the "coupled" in the name true at idle.
  3. (rescue-grade, folded into Idea 2's dye) none — kept at 2 ideas + coupling term to stay under 3.
FORBID: springs (the file's pointer is already the fluid), IQ palette, new params, billow octaves /
  silver-lining / depth-folded hue / wind-smear (those are the SIBLING ethereal-swirl's ideas).
A PACKING: A = (vel.x, vel.y, display-luma history, dye density); texel (0,0) = (mouse.xy, 0, 0).
  C read exactly (textureLoad / hand bilinear). Output ACES display RGB, alpha = coverage.
```
(Idea 3 slot deliberately empty — two ideas + the coupling term it needs.)

### Mechanism interrogation (§12.1)
- **T1 deepen kernel:** the "fbm" is white noise → value noise (rescue); the viscous solver → add the missing vorticity term (idea 1).
- **T2 physics one step further:** a viscous fluid with a stirring cursor sheds vortices that viscosity smooths away — real dye-in-water keeps filaments → confinement. A swirl "wind" over a fluid transfers momentum to it → coupling.
- **T3 promote an intermediate:** `flowVec` and `cloudDensity` (computed, discarded) → wind + dye source; the fake `vorticity` → a real curl.
- **T6 history:** C is read as a *field* (vel/dens) → keep it a field; the only extra continuity that doesn't change that is one scalar (luma) in the unused `.z`.

### Formula admission (§12.4)
- Vorticity confinement: row is in the D table; consumes `C.xy` already stored; deletion in both directions passes (still a swirl-over-photo; confinement alone isn't an ethereal swirl).
- Coupling term: D-family "one extra force the solver already implies"; consumes `flowVec`/`cloudDensity`; no new state/binding/spring.
- Not used: Boussinesq (would give a fixed drift direction), Beer–Lambert (linear tint ≈ exponential at these dens, invisible).

---------------------------------------------------------------------------------------------------

## 2. hybrid-chromatic-liquid  (`public/shaders/hybrid-chromatic-liquid.wgsl`, hybrid)

### HEAD finding — the WGSL is a different effect's code (BIG, flag for user)

- JSON name/description/params/features/`x-meta.chunks_used` all describe **"fluid-like distortion with RGB channel separation flowing along a noise-generated flow field"** (fbm2, fresnelSchlick, flow-field). Slider ids: `flow_scale / distortion / chromatic / flow_speed`.
- HEAD WGSL is a **halftone / ink-line / posterize print** (`dotSize`, `edgeThresh`, `levels`, `inkDensity`, Sobel-sum edges, naga round-trip `_eNN` names). Its four sliders drive dot size / edge threshold / levels / ink density, so every UI label is wrong → this is "param theft" (§4.4) already at HEAD.
- History: `09c8ff85` created the real chromatic liquid (it did not compile: assigns to `let rOffset`); `9983b1eb` "Fix batch of 24 shaders via subagent" **replaced the body with the halftone code** instead of fixing the `let`. The halftone body also reads `u.config.y` (= click-ripple count) as "audio".
- Decision: **restore the JSON-defined identity** (the algorithm the saved params / description / features were written for), fix its `let`→`var`, then add the native ideas. The HEAD halftone is not deleted from history (`git show origin/main:public/shaders/hybrid-chromatic-liquid.wgsl`). If the user prefers the halftone, revert this file and add a new catalog entry for it — the sliders cannot honestly serve both.

### Rescues
| # | defect | fix |
|---|---|---|
| R1 | body is another effect; sliders mismatch JSON | restore original flow-field chromatic liquid (verbatim constants: flowScale `mix(1,5,x)`, distortion `mix(0.02,0.15,y)`, chromatic `z·0.08`, speed `mix(0.2,1.5,w)`, 4-oct angle fbm, 5-step displace loop, ±flow/±(c,0) RGB split, fract wrap, blue highlight, edge Fresnel tint, alpha from luma+distortion, depth·(1−mag)) |
| R2 | original `let rOffset … rOffset.x = fract(…)` (won't compile) | `var` |
| R3 | `@workgroup_size(8,8,1)` | 16×16 |
| R4 | "audio" was `u.config.y`; original had none though JSON claims audio-reactive + mouse-driven | `plasmaBuffer[0].x` bass swells distortion, mids add to flow phase; HEAD's pointer behaviour (held-click ring + cursor pull, HEAD constants) ported onto the liquid's sample point so the JSON's `mouse-driven` stays true |
| R5 | no tone-map | `acesToneMap` on the **added light** only (highlight + glint); the photograph path is left untouched (ACES on the photo would be a grade, not this effect) |

### IDEA CARD
```
SHADER: hybrid-chromatic-liquid
IDENTITY: the photo seen through a flowing liquid — noise-flow displacement with RGB channels split along the flow.
KEEP VERBATIM: four params and roles; flow-angle fbm; 5-step accumulated displacement; R/G/B offset construction
  (flow·c + (c,0)); fract wrap; blue distortion highlight; edge Fresnel tint; semantic alpha; depth·(1−mag).
ADD (2 native ideas):
  1. Slope-driven dispersion (§12.2F "Snell refraction direction", tactic 4) — RGB split amount and direction
     follow the liquid-surface slope (∇ of the displacement noise): steep ripples split strongly along the
     gradient, flat patches stay nearly colour-true. Same `chromatic` slider, same flow-based offsets, plus a
     slope term. NOT Cauchy (reserved for the prismatic lens).
  2. Surface-normal Fresnel + specular glint (§12.2F "Fresnel–Schlick", tactic 3) — HEAD's Fresnel feeds a *fake*
     cosθ from screen radius; promote the displacement height to a normal and feed `n.z·(1−edge)`; add a
     Blinn glint on the same normal so the liquid has a wet sheen. Existing `fresnelSchlick` + (0.8,0.9,1.0) tint kept.
FORBID: Cauchy dispersion (prismatic fork), thin-film iridescence, IQ palette, new params, a spring, a solver.
A PACKING: no feedback; writeTexture only; display RGB + semantic alpha. A not written (no sim state). Depth as original.
```

### Interrogation
- **T1:** displacement via 5 fbm steps — next-better: keep; the *colour split* is a constant-vector offset — next-better is slope-dependent.
- **T2:** a real liquid sheet refracts by the surface slope → dispersion ∝ slope; and shows a specular sheen from the same normal.
- **T3:** `noiseVal` (height) is computed and thrown away → normal; `distortionMag` already drives the highlight.
- **T6:** no history owned → none used.

### Admission
Both rows in the F (lighting/optical) table; liquid sheet = refractive surface → family sentence holds; operate on `noiseVal`/flow already computed (+2 forward-difference `fbm2` taps); deletion test: removing either leaves the restored chromatic liquid.

---------------------------------------------------------------------------------------------------
## Addendum (after implementation) — card revision for ethereal-swirl-coupled
Idea 1 above (vorticity confinement) was implemented and **rejected**: grid-scale instability at every useful strength (see NOTES-forkC.md). The shipped ADD list is: (1) two-way swirl↔fluid coupling (the card's Idea 2), (2) dye-gradient refraction of the photo (§12.2F Snell on the stored dye density, tactic 3), (3) curl-tinted hue from the real curl (§12.2D, the visible half of the old Idea 1). The rescues and KEEP VERBATIM list are unchanged. hybrid-chromatic-liquid shipped exactly as carded.
