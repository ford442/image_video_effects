# BRIEFS — fork D (data-moshing-diffusion, vortex-distortion)

Baselines snapshotted before any edit: `<scratch>/d/{data-moshing-diffusion,vortex-distortion}_head.wgsl` (+ `_prelude.wgsl`). Both files already `#include "_prelude.wgsl"` at origin/main (no migration needed). Both are **second pass**: existing `Ideas:` lines are KEEP VERBATIM.

HEAD findings (rendered, SwiftShader; verified before writing the cards):

| file | finding | verdict |
|---|---|---|
| vortex-distortion | mouse vortex age is `time*0.1` on the **app's global clock** → viscous core `sqrt(4νt)` grows without bound; at T0=300 s the pointer vortex is nearly flat (Γ=+6.4 render looks like a faint dark smudge) | **rescue R1** (Burgers strain arrests the core) |
| vortex-distortion | JSON default `circulation`=0.5 → Γ=`mix(-8,8,0.5)`=0, so HEAD at the JSON defaults is a plain image + chroma fringe. App ships `shaderDefaults.ts` `[0.45,0.45,0.55,0.40]` (Γ≈−0.8) so it is not blank in the app | **left** (signed-slider zero detent; changing the mapping would break saved presets). Flagged for coordinator. |
| data-moshing-diffusion | `q = 20*(1-quantize)+1+bass*5` → 1 level at `quantize`=1 → `floor(c*1)/1` = 0: slider maximum renders near-black (meanL 0.084 vs 0.480 at default) | **rescue R1** (`max(q, 2.0)`; default 0.3 unchanged because q=15) |
| both | other checks clean: no extraBuffer, no illegal stores, audio from `plasmaBuffer[0].xyz`, exact C loads, alpha semantic, ACES clamped, NaN 0 | — |

---

## data-moshing-diffusion

```
SHADER: data-moshing-diffusion
IDENTITY (one sentence): Perona–Malik anisotropic diffusion of the photo through a drifting per-pixel
  offset field (pointer swirl, click fronts, a racing stream packet) — a smeared, posterized datamosh.
KEEP VERBATIM: 4 params + roles (smearStrength / kappa / dt / quantize); Fp128 offset accumulation and
  0.96 damping; conveyor history load from exact C; mouse swirl + held weighting; packet + ripple forces;
  Perona–Malik coefficient exp(-(g/κ)²); tangentDiffusion axis weighting; trail mix; packetWake; ACES on
  display only; A = raw sim (offset.xy, unused, alpha), A is NOT tone-mapped.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): the diffusion stencil is the 5-point N/S/E/W cross → axis-biased:
    diagonal contours smear along the grid, not along the contour. Next-better approximation of the
    SAME operator is the isotropic 9-point Laplacian (§12.2D) — and HEAD's tangent weighting only knows
    E/W vs N/S, so it should be extended to the diagonal taps.
  tactic 2 (physics one step further): a datamosh is a codec artifact — a P-frame keeps the motion
    VECTOR of each macroblock and re-applies it to old pixels; the vectors are per-block, not per-pixel.
    HEAD's offset field is per-pixel, so a real mosh's block lattice is missing.
  tactic 3 (promote an intermediate): `coord` and the exact C offset are already in hand; the block
    centre is one more exact load. The 4 axis taps are loop-invariant (fetched twice per pixel at HEAD);
    hoisting them pays for the 4 diagonal taps.
  tactic 6 (history already owned): C IS the offset field (read as a field, exact loads). Reading it at
    the block centre is a legal extra read; the packing does not change.
ADD (2 native ideas):
  1. Macroblock motion carry (§12.2B, datamosh) — the history offset is blended toward the block-centre
     offset from last frame's C (block = res.y/48 px, ≥8). Weight rides the existing `quantize` role
     (compression coarseness): 0 at quantize=0 (HEAD look preserved), ~0.36 at default. Block seams
     appear in the smear exactly where a P-frame's MVs disagree.
  2. Isotropic 9-point diffusion stencil (§12.2D) — 4 diagonal taps at weight 0.2 (axis 0.8; total
     weight 4.0 = HEAD's 4×1.0, so overall diffusion strength is unchanged), each with its own
     Perona–Malik coefficient and the contour-tangent weight extended to the diagonals
     (|t·d̂|). Contours at 45° now smear along themselves.
FORMULA ADMISSION: macroblock motion carry — §12.2B row, "datamosh only", claimed by this file in
  COMMON.md; consumes the C offset field the file already reads; deleting it leaves the PM smear
  (additive), deleting the PM smear and keeping the block carry is not a mosh (not a replacement).
  Isotropic 9-pt Laplacian — §12.2D row, "RD, waves, heat, jelly" = diffusion; this shader is a
  heat-equation diffusion; consumes the same N/S/E/W taps plus 4 diagonals of the same image; same
  deletion test. Different rows, no overlap with another fork's claims.
FORBID on this file: new springs/ripple overlays (it already owns pointer + clicks), IQ palette, a second
  conveyor, new params, any change to coefficient/damping constants, ACES on A.
A PACKING: raw sim (offset.xy, unused, alpha) — unchanged. Block carry is applied to the history that is
  read; the stored offset is the post-carry field, still read as a field next frame.
RESCUE R1: `quantize` ≥ 0.947 collapsed to < 2 levels (black). Floor at 2 levels.
```

## vortex-distortion

```
SHADER: vortex-distortion
IDENTITY (one sentence): the photo displaced by a Lamb–Oseen vortex under the pointer (plus a ripple-born
  vortex per click) with a Kelvin–Helmholtz wobble, streamline smear and vorticity-coloured overlay.
KEEP VERBATIM: 4 params + roles (Γ signed / ν / KH amplitude / aberration); lambOseen velocity profile;
  khPerturbation m=6 envelope; alternating-sign ripple vortices with exp(-0.3 age) decay; 20-vortex cap;
  vel·0.04 UV displacement; 4-tap streamline smear; source-tied vorticity overlay and glow; semantic
  alpha; A = raw field (vel.xy, vorticity, speed), never ACES'd; HEAD's A.z "vorticity" (=|v|·sign Γ).
MECHANISM INTERROGATION:
  tactic 2 (physics one step further): Lamb–Oseen's defining property is that viscosity spreads the core
    (rc² = 4νt) and flattens the vorticity peak. In a grid solver that smoothing is what vorticity
    confinement re-injects. The file already holds ν, Γ, rc and the Gaussian exp(-r²/rc²) in
    lambOseen — vorticity is closed-form ω = Γ/(π rc²)·exp(-r²/rc²), ∇ω = −2dω/rc².
  tactic 3 (promote an intermediate): `exp(-r2/(4νt))` and `rc` are computed per vortex and thrown away;
    promoting them gives ω, ω·rc and ∇ω for free. (HEAD's `vorticity = length(vel)*sign(circ)` is
    speed, not curl — left as-is, it is the documented A.z.)
  tactic 6 (history already owned): the shader WRITES its raw velocity field to A every frame and never
    reads C. C.xy IS last frame's velocity — one exact load gives v at the departure point.
  tactic 7 (direction): the displacement is a single Euler step along the TANGENT, which drifts outward
    from the arc a real rotation follows. The second-order fix is MacCormack / RK2.
ADD (2 native ideas):
  1. Vorticity confinement (§12.2D) — accumulate ΣωΣ, Σω·rc, Σ∇ω over the SAME vortices; N =
     ∇|ω|/(|∇ω|∨ω²/|ωrc|) (ramps to 0 at the vortex centre and far field so no pin-point), Δv =
     ε·(Σω·rc)·(N.y, −N.x) added to vel. ε = mix(0.15, 0.5, viscosity) (viscosity role: more smoothing →
     more re-concentration). Per vortex it is a Gaussian core spin-up (~+35% at r=rc, far-field
     circulation unchanged); the non-trivial part is that N comes from the SUM, so overlapping click
     vortices bind and merge. Γ=0 ⇒ ω=0 ⇒ no change (the signed zero detent still means "calm").
  2. MacCormack advection (§12.2D) — φ̂ = warp(uv); back-step φ_back = S(uv+uvOff − uvOff(v(uv+uvOff)))
     with v at the forward point read EXACTLY from C (last frame's A.xy, `A.w>1e-4` guard, else the
     uniform-velocity fallback → zero correction); corrected = φ̂ + ½(S(uv) − φ_back), correction clamped
     to the min/max of the 4 streamline taps + 3 aberration taps already fetched (classic MacCormack
     clamp). To first order this is the RK2 midpoint departure point x − v + ½(∇v)v: the warp follows the
     arc instead of spiralling outward. Frame 0 / cleared C ⇒ correction exactly 0.
FORMULA ADMISSION: both §12.2D rows, both claimed by this file. Vorticity confinement operates on the
  Gaussian/ν/Γ the file already computes (no new state, no new solver); MacCormack operates on the
  warp the file already performs plus the A field it already writes (no new binding, no new
  state — reading C is the history the file already owns). Deleting either leaves exactly the HEAD
  Lamb–Oseen warp; deleting the warp and keeping either is not a vortex distortion.
FORBID on this file: springs/IQ palettes/shockwave overlays (the pointer is already the vortex),
  changing the vorticity colour code, ACES on A, any new param, a velocity-field solver.
A PACKING: raw field (vel.xy, vorticity, speed) — unchanged semantics; vel.xy now includes the
  confinement term (C is read next frame as the same field).
RESCUE R1: mouse vortex age `time*0.1` grew without bound on the global clock. Replace with the Burgers
  saturating age t_eff = (1−e^(−2a t))/(2a), a=0.4 (≈ HEAD for t≲1, saturates at 1.25 ⇒ rc stays
  finite). Also feed the same age to the mouse `coreR` used by khPerturbation.
```

---

## Amendments after implementation (cards above were written first and are left as written)

1. **vortex-distortion Idea 1 constants.** ε = `mix(0.15, 0.5, ν)` and a normaliser that ramped N to 0 over r < rc/2 left a thin chromatic fold sliver in the eye of a *young* click vortex (ripple age 0.3 s, rc ≈ 0.08, displacement ≈ 0.15 UV). Final: ε = `mix(0.1, 0.35, ν)` and the ramp spans r < rc (`2·|ω|/h̄` in the denominator). Same idea, gentler; verified the sliver is gone (variants A/B alone did not remove it, A+B did).
2. **vortex-distortion Idea 2 form.** The value form φ̂ + ½(S(uv) − φ_back) was implemented first. Measured on the strong scene: with a confidence weight that suppresses large round-trip errors it changes ≤ 0.012 anywhere (invisible), without it it adds a faint ghost arc of the *undisplaced* source-disc edge (a static source image has no "previous φ" to be consistent with) and costs 2 extra taps behind a dependent load (≈ 1.4–1.5× HEAD). Shipped form: the same round-trip error applied to the **backtrace** (`x_d = uv − off + ½(off(v(uv+off)) − off)`, i.e. RK2 / MacCormack-style predictor–corrector on the trajectory). For a rotation of θ per step it cancels the outward Euler drift (|x_d|² = |x|²(1 + θ⁴/4) instead of |x|²(1 + θ²)); no extra texture taps, no clamp needed beyond a half-Euler-step bound. The §12.2D row name stays (MacCormack); the *form* is the trajectory form.
3. **Free HEAD redundancies removed (output identical, verified 0.0% diff):** data-moshing fetched the same `distortedUV` texel once per channel; vortex fetched `clamp(uvBase)` twice (smear tap 0 and sG). Both folded into one fetch to pay for the added taps/loads.
