# BRIEFS — fork E (heat-haze-volumetric, 1st pass) — written BEFORE any WGSL edit

HEAD = worktree file after the coordinator's prelude migration (copy at scratchpad `e/heat-haze-volumetric_head.wgsl`).

## What HEAD does (read in full, rendered)

State A/C = `(velocity.x, velocity.y, heat, column)` (raw sim state, never tone-mapped in storage). One pass: semi-Lagrangian advect (back-trace by `(vel + (0, heat*0.4))·du·dt`), 4-neighbour diffusion mixes (0.04 / 0.055 / 0.025), forces (heat-gradient swirl, per-pixel white-hash velocity jitter, "buoyancy" `+heat*0.018` in y), sources (held pointer brush `exp(-250 r²)`, click ring `age<1.7`), exponential decay, store. Render: 6 slices through the column, each re-samples the photo at `uv + (∇heat + vel*0.25 + shimmer·(1,-0.7))·refract·(0.25+z)/du`, accumulates with `exp(-column·depth·0.07)` extinction, + orange HDR glow `heat·(1.8,0.35,0.04)`, ACES, alpha = `column*0.38 + heat*0.16`.

HEAD renders (SwiftShader, 256², SRC=img, params 0.5):
- **idle, 90 frames: `meanA 0.000`, output == source photo** (state never leaves zero: the only sources are the held pointer and clicks).
- **pointer held 3 s: only a faint smear** under the pointer (`meanA 0.013`).
- **Buoyancy sign (measured):** with the pointer held still at (0.5,0.5) the alpha centroid y goes 0.520 → 0.533 → 0.536 (frames 20 / 60 / 120) and only 28 % of the alpha is in the top half. Texture y = 0 is the top of the picture and `p − vel` back-tracing moves content toward `+vel`, so HEAD's `+heat*0.018` and `+c.z*0.4` push the heat **down**. HEAD's heat haze sinks.
- No `readDepthTexture` read anywhere (tags/description say depth-aware); no `writeDepthTexture` store.
- `shimmer` = `hash21(p + z·23 + t·8)` — white per-pixel per-frame static, per slice.

## Idea Card

```
SHADER: heat-haze-volumetric
IDENTITY: a persistent heat + column field that rises, refracts the photo through six slices of hot air,
  and glows orange where it is hottest; the pointer / clicks inject thermal shocks.
KEEP VERBATIM: the 4 sliders and their shader roles (zoom_params.x heat strength, .y refraction scale,
  .z column depth, .w turbulence; JSON ids/mapping untouched); A/C packing (vx, vy, heat, column — raw
  state, no ACES in storage); semi-Lagrangian advect + diffusion mix constants; heat-gradient swirl force;
  pointer brush (step(w), exp(-250r²), audio.x/y/z terms); click ring (age<1.7, width 62, 0.2/s);
  decay rates (0.6 / 0.22 / 1.3); 6-slice extinction accumulate; glow colour & audio.z gain;
  alpha = column*0.38 + heat*0.16; ACES on the display write only.
ADD (3 native ideas):
  1. Sun-baked surface source — bright (sunlit) pixels of the photo radiate heat and a thin hot-air column.
     Why here: heat haze IS hot air over sunlit ground; the scene luma is already sampled at the end of
     `main` and thrown away (tactic 3). Rides the existing heat_gain slider.
  2. Boussinesq buoyancy — `b = α·heat − β·column` lifts hot air and lets old dense haze settle, replacing
     the `+heat*0.018` push (which sank the heat). The 0.4-scaled advection drift uses the same `b`.
     Why here: it is the buoyancy term HEAD already tries to have, made physical and correctly signed.
  3. Coherent convective eddies — the white-hash shimmer (per pixel, per slice, per frame) and the white
     velocity jitter are replaced by the curl of a value-noise field scrolled up the plume, with eddy size
     growing with slice depth and amplitude weighted by the local refractivity contrast
     (Gladstone–Dale: n−1 ∝ ρ_air, so deflection ∝ the heat contrast).
     Why here: real shimmer is spatially coherent eddies convected upward, not pixel static.
RESCUES (not counted as ideas, reported loudly):
  R1 idle pass-through at default (Finding 1) — fixed by idea 1.
  R2 buoyancy pointed down — fixed by idea 2 (measured above).
  R3 depth-aware tag with no depth read (Finding 3): refraction path length now scales with the scene's
     distance through the haze, `path = 0.5 + 0.5·(1 − depth)` (depth 1 = near; no depth map = 0 → ×1.0,
     i.e. identical to HEAD when no map is loaded). Plus a depth passthrough store (HEAD stored none).
  R4 `pow(x, 2.0)` with a possibly negative base in the click ring → `x*x` (latent on real GPUs, unproven on
     SwiftShader: HEAD click render `nan 0`).
FORBID on this file: springs / extraBuffer state, click shockwaves beyond the existing ring, IQ palette,
  fire / flame costume (this is haze, not flame), new params, any change to the saved param ids / defaults,
  recolouring the glow, thin-film / chromatic dispersion (not heat haze).
A PACKING: unchanged — raw sim state (vx, vy, heat, column) in A, read back as C; display RGBA only on
  writeTexture (ACES there). B and extraBuffer untouched.
```

## §12.1 mechanism interrogation

- **Tactic 1 — deepen the kernel.** The six slices approximate ∫∇n dz along the ray. The next-better approximation of the *same* operator: make the deflection field coherent (convected eddies) instead of white, decorrelate eddy *size* with the slice (far slices see bigger eddies), and scale the whole integral by the real path length (scene depth).
- **Tactic 2 — physics one step further.** The effect models refraction by hot air. The first-order side effects a physicist would name: (a) hot air comes off *sunlit surfaces* (source = surfaces, not only a finger); (b) it *rises* (Boussinesq), and dense residual haze settles; (c) shimmer is coherent convected eddies; (d) farther objects shimmer more (mirage — longer path).
- **Tactic 3 — promote an intermediate.** `base` (the photo at `uv`) is read last and only multiplied by `trans`; its luma is the sunlit-surface signal. `avg`/neighbours and `column` are already loaded — column is the "ρ" in Boussinesq. `depth` the *slider* is unrelated to scene depth (name collision: the scene depth is `sceneZ` in the edit).
- **Tactic 6 — history.** C is read as raw fields (v, heat, column). One extra piece of continuity that keeps that reading: the idle source writes into the *same* heat/column channels, so it rises, diffuses and decays through the existing solver — no new packing, no new state.

## §12.4 formula admission

| idea | §12.2 row / source | family match | consumes what exists | deletion test |
|---|---|---|---|---|
| 1 sun-baked source | tactic 3 (no table row) | heat haze ≡ hot air over lit surfaces | `base` luma already sampled, heat/column state | delete it → still the pointer-driven haze (HEAD); delete the *brush* and keep only it → still not heat haze: no refraction (additive ✓) |
| 2 Boussinesq buoyancy | §12.2D "Boussinesq buoyancy" `f_y = (α·T − β·ρ)·g` | liquid/sim table; the file is an advected heat/column sim | `heat`, `column`, existing `velocity` + advect term | delete → HEAD (sinking haze); buoyancy alone has no picture ✓ |
| 3 coherent eddies | tactic 5 (device artifact) + algorithmist.md curl row; Gladstone–Dale weight | the term it replaces is the file's own `shimmer` | the file's `shimmer` slot and velocity-jitter slot; `heat` for the refractivity weight | delete → white-noise shimmer (HEAD) ✓; eddies alone ≠ heat haze ✓ |

Claims honoured: Boussinesq buoyancy and Gladstone–Dale are used only here. No Cauchy / thin-film / Fresnel / HG / Beer–Lambert-as-idea / MacCormack / spring. Each idea gets a `// ── Idea n` comment at the place it acts.

## Cost plan

HEAD per pixel: 6 `textureSampleLevel` + 6 sin-hashes (+2 for velocity) + 6 exp. New: same 6 slice samples; `base` hoisted (same single sample, now at the top); +1 depth sample; the 8 sin-hashes become 3 value-noise evaluations (12 integer pcg2d hashes, the `_std` `hashCell21` copied verbatim) — near neutral expected; measure with `agents/mr_perf.mjs`, cap ≤ ~1.3×.
