# Lorenz pair — Idea Cards (claude, 2026-09-13)

## Assessment (Strategy Matrix §5.3)

- `gen-lorenz-attractor`: floor present and it already has several ideas (density splat, hero SDF tube, treble mirror fold, orbit-trap tube shading). But the density field, which is the core of the effect, is thin in one specific way. `contribR`/`contribB` split each splat by lobe, then get **summed into one scalar** before feedback. The lobe identity is thrown away, and the on-screen warm/cool split is just a screen-space `viewX` gradient. The accumulated density also ignores the attractor's speed structure. So this is **"floor present, picture still thin"** in the density layer. I'm adding two ideas, both inside the density accumulation. The tube gets nothing new.
- `gen-lorenz-attractor-flow`: floor is partial (no ACES, no standard header). The 2D phase-space flow field only colours by final position and path length. It knows nothing about chaos, which is the main thing about the Lorenz flow. Idea Card plus floor.

---

```
SHADER: gen-lorenz-attractor
IDENTITY (one sentence): a glowing x–z butterfly built up by Monte Carlo Lorenz splats over frames, with a raymarched hero tube orbiting in 3D.
KEEP VERBATIM: lorenz_step Euler kernel (dt 0.010), 20-step burn-in + 52-step Gaussian splat onto x–z, sigma/rho/glow/decay slider roles, mouse pan, treble mirror fold, hero capsule chain + sphere trace + cone LOD, orbit-trap tube palette, ACES composite.
ADD (2–4 native ideas):
  1. Per-wing accumulated density — keep the right-lobe and left-lobe splat sums as separate temporal channels in A/C, so each wing's colour comes from where the trajectory actually was (strands that cross mix colours honestly) and not from a screen-space x gradient.
  2. Speed-weighted splat (flow-speed tint) — also accumulate |dp/dt|·g; mean speed = speedSum/density. The fast outer sweeps of each wing burn hot/white, the slow spiral near the C± equilibria stays deep. This is the Lorenz flow's own speed structure.
FORBID on this file: springs, click ripples, IQ palette swaps, new geometry, touching the hero tube.
A PACKING: raw sim — A.r = right-wing density, A.g = left-wing density, A.b = speed-weighted density, A.a = display alpha (HEAD: r=density, g=tubeDepth, b=glow3d, a=alpha; HEAD never read g/b/a, so repacking is safe; stored fields are not ACES'd).
```

```
SHADER: gen-lorenz-attractor-flow
IDENTITY (one sentence): every pixel seeds a point in Lorenz phase space and Euler-integrates it, colouring the screen by where the flow carries it, with a swept 3D orbit tube and kaleidoscopic orbit-trap backdrop over soft feedback.
KEEP VERBATIM: 80-step Euler phase-space integration, hsv hue from p.z/pathLength/colorShift, per-channel audio lobe dispersion, swept tube glow + mouse orbit camera, kaleido orbit-trap backdrop, click ripples, vignette, param roles (integration speed / color shift / glow / mouse influence), extraBuffer[133] smoothed bass.
ADD (2–4 native ideas):
  1. Finite-time Lyapunov ridges — integrate a shadow twin seeded 1e-3 away through the same loop; log(separation growth)/steps gives the FTLE field. Its ridges are the flow's stretching separatrices, drawn as bright filaments. This is the chaos the Lorenz flow is known for.
  2. Wing-switch symbolic banding — count sign flips of x (lobe hops) along the 80-step orbit; parity/count bands the field by hop count, a map of which pixels flip wings and how often.
  3. Flow-advected feedback — C history is sampled (exact textureLoad) upstream along the seed point's projected Lorenz velocity, so trails stream along the butterfly flow and don't just sit in place.
FORBID on this file: new springs, IQ palette, replacing the ODE, extra ripple systems.
A PACKING: ACES display RGBA (HEAD wrote pre-tonemap rgb and read C as colour; now display space on both sides, so feedback no longer double-tonemaps).
```

---

# NOTES

## gen-lorenz-attractor (`public/shaders/gen-lorenz-attractor.wgsl`)

- **Decision:** upgraded, not skipped. The tube/fold/trap layers were already rich. But the density layer threw away its own lobe split (R+B summed into one scalar before feedback) and had no speed structure. Both ideas live in that layer, so they aren't theatre.
- **Kept verbatim:** `lorenz_step`, 20-step burn-in + 52-step Gaussian splat, slider roles (sigma / rho+bass / glow+tube radius / decay), mouse pan, treble `mirror_fold`, hero orbit + `heroDE` sphere trace + cone LOD, orbit-trap tube shading, shimmer, ACES composite, depth formula, alpha formula.
- **A packing:** raw sim: r = right-wing density, g = left-wing density, b = speed-weighted density, a = display alpha. C read with exact `textureLoad(dataTextureC, coord, 0)` (`prevC`). HEAD's g/b (tubeDepth, glow3d) were never read back, so repacking is safe. The stored fields are not tone-mapped.
- **Idea 1 (per-wing accumulated density):** `accR`/`accB` from `prevC.r`/`prevC.g` right after the splat loop. Colour comes from `wingMix = accR / max(accumulated,1e-4)` → `wingT` (falls back to the old `lobeMix` only where density is empty). `accumulated = accR + accB` keeps the downstream density/shimmer/alpha/depth maths identical.
- **Idea 2 (speed-weighted splat):** `contribS += g * speedN` inside the splat loop (`speedN` = smoothstep of |dp/dt|). `accS` from `prevC.b`. `meanSpeed = accS/accumulated` scales `col` and adds a white-gold hot sweep term (treble lifts it slightly).
- **Header:** Features trimmed to `mouse-driven, audio-reactive, upgraded-rgba`, Upgraded 2026-09-13, Ideas + A packing lines added.
- **JSON:** appended `mouse-driven`, `audio-reactive`, `upgraded-rgba` to `features` (all true: mouse pans, plasmaBuffer bass/mids/treble drive rho/glow/decay/fold/camera, ACES present). This definition has **no `params` key** (only `updatedParams`), so nothing to keep byte-exact there. Left untouched.
- **Gates:** naga OK; precommit gate PASS (bindgroup, workgroup, extraBuffer). The dead-slider audit passes but reports "Definitions scanned: 0" because the JSON has no `params` array. All four `zoom_params` are read in WGSL (checked by hand).

## gen-lorenz-attractor-flow (`public/shaders/lorenz-attractor-flow.wgsl`, JSON id gen-lorenz-attractor-flow)

- **Kept verbatim:** 80-step Euler phase-space integration, hsv hue/sat/val formula, per-channel audio lobe dispersion, swept tube + mouse orbit camera, kaleidoscopic orbit-trap backdrop, ripple loop, mouseDown boost, vignette, depth, extraBuffer[133] smoothed bass (single writer at 0,0), FFT bin reads, all param roles.
- **A packing:** ACES display RGBA. HEAD wrote pre-tonemap rgb and read C as colour. Now the history mix happens in display space after `acesToneMap`, and the same `disp` goes to writeTexture and dataTextureA, so there's no double tone-map drift.
- **Idea 1 (FTLE ridges):** shadow twin `q` (seeded +1e-3 in x) integrated in the same 80-step loop. After the hsv colour, `sep`/`ftle`/`ftleN`/`ridge` add bright complementary-hue filaments (glow slider scales them, treble lifts them). The ridge also slightly raises alpha and the feedback weight.
- **Idea 2 (wing-switch banding):** `hops += select(0,1, p.x*prevP.x < 0)` in the loop. After the hsv colour, `hopParity` swaps channels (rgb.gbr) on odd hop counts and `hopBand` shades by hop count (phase from colorShift).
- **Idea 3 (flow-advected feedback):** `seedVel` (Lorenz dx,dy of the seed point) is computed before the loop. In the feedback block, `upstream` (≤3 px, scaled by the integration-speed slider) offsets an exact clamped integer `textureLoad(dataTextureC, srcC, 0)`.
- **Header:** Features `mouse-driven, audio-reactive, upgraded-rgba`, Upgraded 2026-09-13, Ideas + A packing lines. The older b32 notes lines are kept.
- **JSON:** appended `upgraded-rgba` to `features` (mouse-driven/audio-reactive were already there and true). `params` byte-exact, formatting preserved.
- **Gates:** naga OK; precommit gate PASS; dead-slider audit PASS (1 definition scanned, 0 dead).
- **GPU QA caveat:** the FTLE thresholds (`ftle*0.12`, ridge smoothstep 0.55–0.95) and hop band strength are tuned by reasoning only. Check on a real GPU that ridges read as filaments and don't flood the frame.
