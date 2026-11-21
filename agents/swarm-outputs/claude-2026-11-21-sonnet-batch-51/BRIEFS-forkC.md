# BRIEFS — fork C (alucinate, generative-psy-swirls) — written BEFORE any WGSL edit

HEAD = worktree file when the fork started (copies in scratchpad `c/alucinate_head.wgsl`, `c/generative-psy-swirls_head.wgsl`, `c/_prelude.wgsl`). Both are **first pass** (alucinate's "Visualist 2026-05-03" and psy-swirls' "Batch 34" headers are hygiene, no idea text).

---

## 1. alucinate (first pass)

### What HEAD does (read in full, rendered on the harness, 192², SRC=img)

One pass, no history. `ca` = aspect-corrected centred uv → `domainWarp` (IQ-style q/r fbm, 16 value-noise calls) → `kaleidoscopeIFS` (5 × `abs(z)-(0.3,0.2)`, rotate, invert by `max(|z|²,0.1)`) → `conformalMap` (`(z²−c)/|z²−c|²·0.5`) → scale by `0.5 + mouse·0.5 + audio·0.2` → click ripples added into `warped` → `grayScott(warped*0.5+0.5)`. **`grayScott` is a stateless analytic function** of the warped coordinate and time (feed/kill 0.037/0.06 ± drift), not a solver: nothing reads C. `patternA/B` then (a) displace the three colour taps (R by `(pB·ab, 0)`, G by `(0, pA·ab)`, B by `−0.6·ab·(pB, pA)`), (b) key the hue of an HSV rainbow mixed in at `0.2 + p1·0.3`. gamma `1/(0.85+p4·0.3)`, depth shade ×(1+0.5·depth) at 0.35, semantic-ish alpha from luma/depth, A = `(a, b, |(a,b)|, sin-diffusion)` raw field with **no reader**, depth passthrough.

HEAD defects found (verified, not assumed):
- **R1 click blows the whole picture up (verified on the harness).** `time = u.config.x * 0.5` but ripple start times are in `u.config.x` units, and the loop does `rt = time − ripple.z`. For a click at session time T the age is `0.5·t − T`, negative until `t = 2T`, so `exp(−rt·2)` is huge (`exp(+9.9)` at t≈10.5 for a click at 10.0) and `ring·0.3` swamps `warped`; every pixel clamps to the border of the photo. `a_head_t10_click.png` (scratch) shows pure concentric noisy rings instead of the picture; the same params with no click show the normal remix (`meanL .553 → .540`, `stdL .106 → .090`, but visually the picture is gone). It also has **no cap** on `u.config.y`.
- **R2 no ACES** although `features` claims `upgraded-rgba` (colour can exceed 1 and hard-clips at the swapchain).
- **R3 `gradMag` is not a gradient** (it is `length(vec2(a,b))`), so the A.z channel name lies.
- Over-claim only (reported, not "fixed"): `reaction-diffusion` tag — there is no RD state; adding a real screen-space solver would replace the kaleido-tied pattern, which fails §12.4 (new solver / new state) and the deletion test, so it is **not done**.

### Idea Card

```
SHADER: alucinate
IDENTITY: the photo re-sampled through a domain-warped, kaleidoscope-folded, conformally-mapped
  domain, split into R/G/B by Gray-Scott-style Turing cells and washed with a pattern-keyed rainbow.
KEEP VERBATIM: 4 sliders and roles (intensity = warped/straight uv mix + aberration + rainbow mix,
  speed = warp/IFS drift, scale = warp frequency, detail = hue offset + gamma); domainWarp / fbm /
  conformalMap / grayScott bodies; IFS constants (0.3,0.2), 5 iterations, inversion max(d,0.1);
  the three aberration taps and their (pB,0)/(0,pA)/diag structure; HSV rainbow mix; gamma; depth
  shade; alpha formula; depth pass-through; A = (a, b, gradient, diffusionRate) raw field.
ADD (3 native ideas):
  1. Mirror-cell chirality — fold count as material (§12.2E): kaleidoscopeIFS counts its reflections;
     the parity of that count flips the sign of the chromatic offset on mirrored cells, so mirror
     facets show mirrored dispersion and the cell seams read as real kaleidoscope facets.
     Why here: the fold loop is the kaleidoscope; a real one mirrors handedness per cell.
  2. IFS orbit-trap filigree (§12.2E orbit trap): trap = min over iterations of | |z| − 1 | (the
     fixed circle of the file's own inversion z/|z|²). exp(−trap·k) brightens/boosts the rainbow
     overlay into fine veins on the fractal cell boundaries.
     Why here: it is the quantity the iteration already computes and throws away (tactic 3).
  3. Turing-cell lenslets (tactic 7, direction not just magnitude): the pattern's gradient ∇a (forward
     differences of the same analytic grayScott, 2 extra evaluations) displaces the R/G/B taps along
     the cell edge normal with a (+1, 0, −1) dispersion spread, so each cell edge refracts like a
     tiny lens and fringes along its rim. A.z becomes the true |∇a| (honest name).
     Why here: HEAD displaces by pattern *magnitude* along fixed axes, which has no orientation.
RESCUES (reported loudly, not ideas): R1 ripple clock (rt = 0.5·(config.x − ripple.z), the same
  half-rate the ring was designed in; gated 0 ≤ rt < 4; count capped at 50); R2 ACES on the display
  path (look change: mids brighten, whites compress to ~0.8); R3 A.z honest gradient (via idea 3).
FORBID: a screen-space Gray-Scott solver / new state, spring, IQ palette swap, new params, B writes,
  per-frame hash strobing, changing the warp/IFS/conformal bodies.
A PACKING: unchanged raw field (a, b, |∇a|, diffusionRate) — no reader in this file; ACES only on
  writeTexture.
```

### §12.1 mechanism interrogation

- **Tactic 1 (deepen the kernel).** The "Turing" displacement uses a scalar magnitude on a fixed axis. The next-better version of the same operator (a lens-like refraction by a height field) uses the *gradient* of that field: direction + slope.
- **Tactic 2 (physics one step further).** A kaleidoscope mirrors: adjacent cells are reflections, so lateral dispersion mirrors too (idea 1). A prism/lenslet array disperses along the surface normal (idea 3). Light-handling gets an honest display transform (R2).
- **Tactic 3 (promote an intermediate).** `kaleidoscopeIFS` computes fold sides and the inversion radius per iteration and drops both; `grayScott` returns (a,b) but only their magnitude is used and its gradient never. Ideas 1–3 promote exactly these three.
- **Tactic 6 (history).** The file owns no history and reads no C; A is an unread raw field. None of my ideas needs history.

### §12.4 formula admission
Rows used: fold count as material, orbit trap (both §12.2E; both claimed for alucinate only). Idea 3 is a tactic, not a row. All three consume the iteration/pattern the file already computes; no new state, binding or solver. Deletion test (both directions): remove any one idea → still the same remix; keep only one idea → not alucinate (no warp/IFS/conformal photo remix) ⇒ additive.

---

## 2. generative-psy-swirls (first pass)

### What HEAD does (read in full, rendered)

Never reads `readTexture` (generative). `p` = aspect-centred uv, fbm-warped by 0.10–0.20. For `i32(layers)` (2–7) layers it evaluates `layeredSwirlLayer` three times (R, G, B layers with ±`fi·0.02` offsets, treble/bass freq nudges, mids hue fan) and takes `(rLayer.r, gLayer.g, bLayer.b)`: arm `sin(3·(a + d·twist·freq − 0.5·t))·0.5+0.5` × ring `sin(10d − 2t)·0.5+0.5` as HSV value, hue `fract(0.5d + 0.1t + shift)`. Click ring (capped 50, window 1.7 s) added in violet. Trail: `prev = textureLoad(C)`, `mix(color, prev·0.92, 0.04 + 0.02·mids)`, clamp 1.2 + tint → A (alpha 1.0), same blend into the display, ACES(color·1.1), relief depth, coverage alpha. Harness (192², T0 9, 40 frames, defaults): `meanL .234 stdL .163 meanA .244 nan 0`; a soft three-armed pinwheel, dark core, mostly green/yellow, low-contrast edges (hue is a function of radius only; channel layers are nearly identical at idle).

Findings:
- **Finding 2 verified (dead spring).** The pointer spring lives in `extraBuffer[133..138]`, which the engine zeroes before every dispatch, so `extraBuffer[137] < 0.5` is always true: `mouse = rawMouse`, velocity 0, no smoothing. In the engine this is *raw pointer*. **Garnish, not identity** → left alone ("dead in engine, left alone"), no idea depends on it; the `sprung-mouse-vortex` feature tag is an over-claim (reported, not edited — nothing in my diff relies on or removes it, and if the engine write is ever fixed the spring would live again).
- **Finding 4 darkness is design, not a defect.** Value is `arm·ring` (product of two [0,1] sines, mean 0.25) averaged over layers, then ACES; alpha is coverage-based (`length(color)·0.72`). No blank/NaN/saturation. I do not change the brightness.
- Minor: `invLayers = 1/layers` divides by the float count while only `i32(layers)` layers are summed (up to 14 % dimmer at fractional counts). Left alone — it is a saved-look detail.
- Idle R/G/B layers are almost the same (offsets ±0.02·fi, freq nudges only with audio), so "chromatic-hue-separation" only shows on musical peaks.

### Idea Card

```
SHADER: generative-psy-swirls
IDENTITY: stacked fbm-warped polar swirl vortices (arms × radial rings, hue by radius) with an R/G/B
  layer split, a trail memory and a click ring; a generative psychedelic pinwheel.
KEEP VERBATIM: 4 sliders and roles (twist = vortex twist incl. bass kick, layers = layer count,
  frequency = arm pitch + warp scale, depthReduction = scene-depth flattening of the twist); arm
  sin(3·swirl), ring sin(10d − 2t), hue fract(0.5d + 0.1t + shift), HSV layer fn; mids hue fan;
  treble/bass freq nudges; fbm warp + drift; layer offsets (pointer spread + Lissajous); click ring
  (cap 50, 1.7 s window); trail memory (exact C load, 4 % + mids, clamp 1.2, tint); relief depth;
  coverage alpha; ACES(color·1.1); the dead pointer spring untouched.
ADD (2 native ideas):
  1. Core-profile differential rotation — additive domain twist with a Lamb–Oseen angular-velocity
     profile (§12.2E): the vortex core winds relative to the outer swirl, φ = A·g(d)·sin(Ω t),
     g(d) = (1−e^{−d²/rc²})/(d²/rc²) (g(0)=1, g→0 outside the core), added to the arm phase.
     A rides the existing twist (adjustedTwist, so the depth-flattening slider still bites).
     Bounded in time (sinusoidal), no refresh crossfade, no strobe.
     Why here: HEAD rotates every radius rigidly; a real vortex has a spinning core and a lagging
     outer flow, and the layers' rings/arms then shear into the spiral wring that reads as a swirl.
  2. Per-channel flow lag — the R, G, B layers sample the same core surge at t − δ, t, t + δ
     (δ ≈ 0.5 s; R leads, B lags). Chromatic arm fringes appear exactly where the core is shearing,
     vanish when it is momentarily still, and need no audio (idle HEAD has near-identical layers).
     Why here: the file's `chromatic-hue-separation` concept, made physical: different channels see
     the same flow at slightly different times.
FORBID: new params; a new spring/persistence scheme; a trail rewrite; click-ring overlay changes; IQ
  palette swap; frame-hash strobing; touching the brightness / layer averaging.
A PACKING: unchanged — A = pre-ACES trail colour (clamp 1.2, tint) with alpha 1.0, read back as
  colour history C.rgb; ACES only on writeTexture.
```

### §12.1 mechanism interrogation

- **Tactic 1 (deepen kernel).** Swirl phase is linear in radius with a constant spin rate (rigid). Next-better model of the same operator: angular velocity as a function of radius (Lamb–Oseen).
- **Tactic 2 (physics one step further).** A vortex's first-order side effect is *differential rotation* (shear) and the arms that result; an observer sees dispersion of timing across colour channels as chromatic fringes where the flow is fast.
- **Tactic 3 (promote an intermediate).** `d` (radius from the layer's centre) is already computed and used for hue and rings; the same `d` feeds the core profile, no new coordinates. Per-channel layers already exist (idea 2 only changes what each is fed).
- **Tactic 6 (history).** C is read as colour history. I add nothing to history; the packing stays. (An advected trail was considered: at HEAD's 4 % memory it would be invisible, and raising the weight changes the look — not additive. Rejected.)

### §12.4 formula admission
Row: additive domain twist (§12.2E, with the Lamb–Oseen profile from the algorithmist physical-equation table). The second idea is a tactic (per-channel timing), no row. Both consume `d`, `adjustedTwist`, `time` already in the layer function; no new state/binding/spring. Deletion tests: remove either → the same pinwheel; keep only the ideas → not a swirl (no arm × ring structure) ⇒ additive.

---

## AMENDMENT (coordinator message: Jules-bot 9b5cd56e reverted upgrades) — written before the final WGSL, after the salvage audit

`git log -S'Ideas'`: **generative-psy-swirls** had an upgraded version, sonnet/batch-28 `9acc4b18` (2026-11-09 08:22Z), reverted 13 h later by `9b5cd56e` (jules-bot, "Fix rotate and float errors", 65 files, deleted notes). **alucinate** has no such history (no commit ever added idea text) → nothing to salvage there; its card above stands.

Salvage audit of `9b5cd56e^:public/shaders/generative-psy-swirls.wgsl` (diff vs HEAD = exactly the 66 batch-28 lines, nothing else):
- No `pow` of a negative base; value `val ≥ 0`; hue goes through `fract()` (WGSL fract(x)=x−floor(x), always in [0,1)); `color` is non-negative so ACES never sees a negative.
- The A(0,0) glide-state texel: pixel (0,0) replaces its colour read with the live colour (`select(…, color, isGlideTexel)`), and no pixel reads a neighbour of C, so state is never read back as colour. `ok` is gated by `GLIDE_MARK == 7` and `st.w ∈ [0,1)`; `dt = fract(time − st.w)` is exact across integer seconds and clamped to [0.001, 0.05].
- Verified on the engine-faithful harness (extraBuffer re-zeroed per frame): glide vs raw pointer while sweeping = 74 % px differ, at rest = 0 % — the dead-spring rescue really works.
- No defects found → kept as is (not copied blind: re-read, re-ran, ablated).

**psy-swirls card, final (4 ideas = the ceiling):**
```
ADD:
  1. arm-wound hue (SALVAGED, batch-28) — spectrum winds with the polar arms; wound/TAU is continuous across the atan2 seam.
  2. Rankine eye-wall cores (SALVAGED, batch-28) — calm eye + bright wall instead of a pinwheel singularity.
  3. Lamb-Oseen core wring (mine, §12.2E additive domain twist) — bounded sinusoidal surge weighted by g(d); amplitude rides adjustedTwist.
     INTEGRATION: `wound` now includes the wring, so idea 1's hue still follows the *sheared* arms (variant B, hue ignoring the wring, left the colour bands behind the arms in the core).
  4. Per-channel flow lag (mine) — R leads / B lags the same surge by ±0.6 s.
RESCUE (SALVAGED): cursor glide in A texel (0,0) replaces the dead extraBuffer spring. This supersedes my first decision "dead in engine, left alone" (Finding 2 rule c): the glide is the sanctioned texel-resident form (rule b, one texel, stated packing, no colour read of it).
A PACKING: raw trail colour (clamp 1.2, pre-ACES, C read as colour); texel (0,0) = (glide.xy, 7, fract(time)).
```
Shared-WGSL note: preset `psy-swirls` (`shader_definitions/generative/psy-swirls.json`) uses the same WGSL with different slider names/defaults (swirl_speed 1, layer_count .5, rainbow_speed .8, twist_intensity .6) mapped onto the same four slots — a pre-existing role mismatch (its x=1 is full twist), not touched; with x=1 the wring amplitude is at its (bounded) maximum.
