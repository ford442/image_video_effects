# BRIEFS — fork D (liquid-smear, 1st idea pass) — written BEFORE any WGSL edit

HEAD = worktree file at start (copy: scratchpad `d/liquid-smear_head.wgsl`; already used `#include "_prelude.wgsl"`). It carries only a hygiene-era header (`Upgraded: 2026-08-23 Batch 58B`) and no `Ideas:` line, so this is the first idea pass.

## What HEAD does (read in full, rendered, instrumented)

One pass. C is read as **pigment colour history** (`historyBilinear` ×5 + `historyBounds` cross stencil). Per pixel: spring-damped pointer (position + velocity) → `strokeDir`; `guidedDir` = stroke direction bent toward the source-image contour tangent by `edgeEnergy`; `offset = guidedDir · clamp(speed·0.02, 0, 0.06) · smear · (0.5+held) · brushFalloff`; bounded click splats add radial `offset`; history is back-traced to `uv − offset`, blurred by a 5-tap Gaussian **along the stroke normal** whose width comes from an FFT band, clamped to the local extrema of the cross stencil (monotone reconstruction); cold start seeds from the plate; `refresh` (splat + held brush) re-injects the plate; `blend = mix(plate, smeared, keep)`; colour = `mix(plate, blend, mixStrength)` + tints + fibre sin, ACES; semantic alpha from `thickness`/`absorption`/Fresnel; A = pre-ACES `blend.rgb` + alpha (floor 0.02), no mask/field in A.

**Measured on HEAD, SwiftShader, engine-faithful harness (extraBuffer[133..255] re-zeroed every dispatch), 96², 60 frames, held pointer sweeping x 0.15→0.85, params 1,0.6,1,1** (debug copy of HEAD writing `speed` and `mousePos` to RGB):
- **Pointer velocity is dead in the engine**: `speed` max **0.000** (persisting-buffer harness, i.e. what the old harness showed: 0.745). `strokeDir` = 0, `dragLen` = 0, `offset` = 0 → **the drag never happens**; only click splats move pigment.
- **The brush lands in the wrong place**: **70.4 % of invocations read `mousePos == (0,0)`** (they race invocation (0,0)'s write into a buffer the engine zeroed before the dispatch); 29.6 % read the pointer. The alpha panel shows a brush nub in the top-left corner (visible in `hs_engine_move.png`). A persisting buffer gives 0 % such pixels.
- `band = plasmaBuffer[bandIdx + 1u].x` is **never uploaded** (`writePlasmaBuffer` writes only `plasmaBuffer[0]`); Structure 2's "per-band FFT" has been a constant 0. Real FFT bins are engine-owned: `extraBuffer[5 + bin]` (128 bins, 0..1).

## Idea Card

```
SHADER: liquid-smear
IDENTITY (one sentence): the live photo as wet pigment that the pointer rakes along its own stroke,
  following source contours, bleeding sideways per FFT band, splatting on clicks, relaxing back to the plate.
KEEP VERBATIM: the 4 sliders and roles (x Smear Strength → drag length + bleed gain; y Brush Size →
  falloff radius; z Persistence → decayRate 0.9..0.995; w Mix Strength → smeared-over-plate blend);
  spring constants (k = 1−exp(−9·0.016), velocity mix 0.25); strokeDir/guidedDir edge-guided transport;
  5-tap Gaussian bleed along the normal + monotone local-extrema clamp; exact textureLoad history with
  hand-rolled bilinear; cold-start seed; click splat loop (age<2.2, front 0.42, exp(−150 f²)); refresh;
  tints; fibre sin; ACES on display; semantic alpha; depth pass-through; A = pre-ACES pigment RGB +
  alpha (floor 0.02) read as C colour. Saved params byte-exact.
RESCUES (reported loudly, not counted as ideas):
  R1 pointer position + velocity persist where they can: texel (0,0) of A→C = (smx, smy, svx, svy).
     Every invocation recomputes the identical spring step from C(0,0) (deterministic, no race);
     only invocation (0,0) stores it. Every history load of texel (0,0) is redirected to texel (1,0)
     so no pixel reads state as colour. Fixes: dead velocity smear, brush at (0,0) for 70 % of pixels.
  R2 per-band bleed reads the engine FFT bins (extraBuffer[5 + 4·band], 0..1; two adjacent bins,
     averaged) instead of the never-written plasmaBuffer[1..8]. Silent audio → identical to HEAD.
ADD (3 native ideas):
  1. Bank-and-wake pile-up — §12.2D shallow-water continuity ∂ρ/∂t = −∇·(ρv). The drag field `offset`
     (which the file already computes) is a displacement map; pigment mass is conserved, so thickness
     scales with 1 − ∇·offset: pigment banks up ahead of the brush and thins in its wake. The
     divergence is analytic from brushFalloff's derivative (no extra taps). Feeds the file's own
     `thickness` (semantic alpha) and a Beer–Lambert density shade on the pigment before the existing
     mixStrength blend, so Mix Strength 0 still shows the plain plate.
  2. Bristle rake striations — §12.1 tactic 7 (direction, not just magnitude) + §12.2C stroke tangent.
     The file already knows the stroke normal; the across-stroke coordinate in the brush frame
     (aspect-corrected, perpendicular on screen) modulates the drag length by a smooth 1-D bristle
     profile (zero-mean, 0.5..1.5×). Fixed in the brush frame → streaks parallel to the path. Total
     drag unchanged on average.
  3. Speed-thinning — §12.2C: R = R0 / (1 + 0.35·|v|). Second-order Brush Size (tactic 4): fast flicks
     rake with a narrow brush, slow drags pool wide. At rest R = R0, i.e. identical to HEAD. Uses the
     live `speed` that R1 revives.
FORBID on this file: ferrofluid/oil-slick/IQ palette, holographic or neon pop, new solver, any
  spring/state in extraBuffer, new click shockwaves, new params, thin-film, vorticity, replacing the
  smear with display-history sparkles, changing the A packing.
A PACKING: unchanged = pre-ACES pigment RGB + alpha(≥0.02) in A, read back as C colour.
  Exception (R1): texel (0,0) holds pointer state (smx, smy, svx, svy), never pigment; consumers of C
  redirect that one texel to (1,0). B untouched; extraBuffer[0..132] untouched; no [133..255] use.
```

## §12.1 mechanism interrogation

- **Tactic 1 — deepen the kernel.** The kernel is a semi-Lagrangian back-trace through a displacement map, then a 5-tap bleed. The next-better approximation of the *same* operator is to honour what a displacement map implies physically: mass conservation (continuity), and that a raking tool is discrete bristles (the drag is not a smooth function across the stroke).
- **Tactic 2 — physics one step further.** A thumb / palette knife / flat brush dragging wet pigment: (a) paint banks up in front of the tool and thins behind it; (b) a bristled tool leaves striations parallel to the stroke; (c) contact width narrows as speed rises (kinematics).
- **Tactic 3 — promote an intermediate.** `offset`/`dragLen`/`brushFalloff` are computed and only used to shift a uv; `normalDir` is used only for the bleed taps; `speed` only scales `dragLen`; `thickness` only feeds alpha. Ideas 1/2/3 each consume one of these.
- **Tactic 6 — history.** C is read as pigment colour. The one piece of continuity it can additionally carry without changing that reading is a 4-float pointer state in a single texel (R1) — the only way to keep the effect's identity alive given Finding 2.

## §12.4 formula admission

| idea | row | family match | consumes | deletion (both ways) |
|---|---|---|---|---|
| 1 pile-up | §12.2D shallow-water continuity | liquid / pigment drag *is* a flow field | `offset` (= `guidedDir·dragLen·brushFalloff`), `brushFalloff` derivative, `thickness` | remove → still the same smear ✓; keep only the shade → just a shaded ring, not a smear ✓ |
| 2 bristles | §12.2C stroke tangent / tactic 7 | file already owns the pointer, `normalDir` exists | `normalDir`, `toMouse`, `dragLen` | remove → plain smooth rake ✓; keep only striations → no drag at all ✓ |
| 3 speed-thinning | §12.2C speed-thinning | pointer-owned brush | `speed`, `brushSize` | remove → fixed radius (HEAD) ✓; keep only → nothing moves ✓ |

Rows used on this file: shallow-water continuity (also free elsewhere in the batch — nobody else claimed it), speed-thinning (claimed for liquid-smear only). No other fork is likely to pick them. No new state, binding, solver or spring beyond R1's single texel.
