# NOTES — Fork A (sonnet/batch-24): fabric-zipper, fabric-step-gabor

Renders: scratchpad/forkA/ (HEAD: zip_head_*, step_head_*; new: zip_new*, step_fin*, step_576_*; sweeps zip_sweep.png, ext_img.png).
All numbers from minirender (SwiftShader, rgba32float, synthetic `SRC=img` photo + depth). Not a real-GPU check.

---------------------------------------------------------------------------------------------------
## fabric-zipper (2nd pass)  —  `public/shaders/fabric-zipper.wgsl`

**Kept verbatim:** 4 params and roles (teeth_density→tooth pitch, spread→opening_width, weave_freq→twill density,
jaggedness→scallop amplitude); slider follows the cursor, opening above it; twill height field + lighting
(`twillRib`, `twN/twDiff/twAO/twSheen`); rolled tape lips + image contact shadow (HEAD idea 2a/2b, comments relabelled
"last pass"); seam line; `calculateFabricAlpha` material alpha; ACES display RGBA written to A, C not read; depth
passthrough. No spring, no ripples, no new param, no audio. JSON untouched (features/tags/x-meta already correct).

**A packing:** display RGBA (post-ACES colour + material alpha) — unchanged.

**Ideas in the diff (4):**
1. *Interlocking chain* — `toothBarrel` (l.104) + the `// ── IDEA 1: interlocking chain` block (l.170) and the chain
   composition (l.284): L/R teeth at phases `y·pitch ∓ 0.25` (half-pitch stagger, duty 0.5, rounded blocks anchored on the
   tape, heads reach `TOOTH_REACH` past the cut edge so the closed chain meshes). The reveal scallop of the right flap is
   the left one flipped and is locked to the tooth phase (HEAD used `6.28`, not 2π, which drifted ~0.2 pitch down the page).
   Edges are footprint-band-limited instead of `step`.
2. *Lit metal hardware* — `metalShade` (l.117): diffuse + Blinn from the twill's own `LIGHT_DIR`, **Fresnel–Schlick**
   grazing rim (§12.2F, brass F0 on teeth, steel F0 on slider). Teeth are barrels (normal from their own a,b); slider is a lit
   dome with a pull-tab post hole; teeth and slider throw soft contact shadows onto tape / image.
3. *Twin lockstitch rows* — `stitchRow` (l.129) + block at l.245: two dashed thread rows per flap measured from the MEAN tape
   edge `|dx| − width` (so they do not zigzag with the sawtooth scallop), pushed out by the scallop amplitude once open,
   one stitch per tooth pitch, round thread cross-section, darkened twill groove, thread alpha → SEAM_ALPHA.
4. *Tape bunching at the slider* — l.197: chevron folds `(|dx|·0.8 + dy)·FOLD_FREQ` under an elliptical envelope around the
   slider bend the weave phase (`tp.y`) and tilt the twill normal + AO.
Formula names for NOTES / `Ideas:` line: Fresnel–Schlick (§12.2F). Ideas 1, 3, 4 are tactic-derived (no table row).
Header `Ideas:` extended (all earlier ideas kept); `Upgraded: 2026-09-28, 2026-11-09`.

**Rescues:** none needed (HEAD healthy). Incidental: scallop `6.28`→`TAU` (see 1).

**Default-look change:** yes, by design — staggered brass barrel teeth (HEAD: flat gold bars, mirrored phase), lit slider,
stitch rows, subtle folds. Overall stats ≈ unchanged (192 idle meanL 0.225→0.227, stdL 0.118→0.119, meanA 0.796→0.799;
held 0.251→0.252 / 0.144→0.142; 576 idle 0.239→0.237 / 0.132→0.136).

**Gates:** wgsl_precommit_gate ✅ (naga + bindgroup); audit:extrabuffer PASS; audit:dead-sliders PASS (all 4 zoom_params
read and visible: x pitch, y opening, z weave, w scallop). Renders 192 + 576, idle + held cursor + audio 0.4/0.3/0.2 (no audio
path), parameter-extreme sweep (0000 / 1111 / spread 1 jag 0 / spread .2 jag 1 / teeth 1 weave 1): no NaN, nothing degenerates.
Timing (SwiftShader, back-to-back ×2, 576 px): 38–40 ms → 62–84 ms (light shader; not one of the heavy ones).

**Open items / doubts:** at 192 px the half-pitch teeth are ~1.6 px long, so the interlock only reads from ~384 px up (HEAD was the
same scale). Stitch rows jump where the open V meets the closed seam at the slider (rows switch from the closed offset to
closed+scallop over `openF`'s 0.02 ramp) — reads as the tape turning. Fold chevrons are deliberately subtle; real-GPU look pending.

---------------------------------------------------------------------------------------------------
## fabric-step-gabor (1st pass)  —  `public/shaders/fabric-step-gabor.wgsl`

**Kept verbatim:** 4 params and roles (stiffness, tearThreshold [range 1.5..4 kept — now a stretch RATIO], gravity,
damping 0.95..0.999); Verlet displacement with previous state; fbm wind (`fbm(pos·4+…)`); cursor pushes the cloth away inside
r = 0.15, linear falloff; pinned top edge; Gabor bank (4 orientations, σ 2.1, `freq = mix(.05,.25,.3+strain·.4)`,
`responseScale`, 9×9 support, luma taps, gaussian·cosine kernel); the four cosine palettes; |response|-weighted blend; ×1.3;
`mix(source, gabor, strain·0.7)`; strain colour ×0.2; `fabricAlpha = mix(.9,.7,strain·.5)`; B = (strain, vel.xy, 1.0); depth
read at `pos`. No spring/ripple/audio overlay, no new params.

**A packing (changed, documented):** raw sim state **A = (d.xy, dPrev.xy)** displacement OFFSETS from the rest uv (HEAD
stored absolute (pos, prevPos)). Zero state = at rest. Not tone-mapped; ACES only on `writeTexture`. B as HEAD.

**HEAD defects (measured before editing — HEAD 192 px, 60/150/300/600 frames, idle + held):** whole frame saturated in Gabor
colour from the first seconds; magenta tear regions along the top/left edges and a permanent smear plume under a held cursor
that GROW from 300→600 frames and never heal. Causes: per-pixel independent oscillators (no neighbour coupling), constraint
window measured in texels `(2, tearThreshold)·(1/res.x)` that wind (~1 texel/frame steady-state) escapes within a few frames and
nothing ever pulls back, strain = displacement size (`|pos−uv|·50`, saturates at 0.02 uv), texel-edge C read, f16-unsafe absolute
positions, 4× redundant Gabor tap fetches.

**Rescues (R1–R5, not ideas):**
- R1 cloth is a real mass-spring sheet: Hooke tether `kRest = 0.004 + 0.016·stiffness` + isotropic **9-point Laplacian**
  coupling (§12.2D) `kStruct = 0.5·stiffness` on a fixed ~180-cell grid (`stride = round(res.y/180)` — same sheet at every
  resolution), explicit-Verlet stable; wind/gravity/cursor are accelerations; a stretch-gated *soft* tear (springs weaken to 15 %,
  never vanish) → tears HEAL (A has no free channel for a permanent flag).
- R1c strain = real stretch/compression `max(σmax−1, 1−σmin)·2` from the deformation gradient.
- R2 exact `textureLoad` of C (clamped) + `|d| ≤ 0.15` guard (inherited A from a previous shader on switch decays).
- R3 offsets, not absolute uv (f16-safe; velocities no longer quantise to zero).
- R4 the 9×9 neighbourhood is fetched once and shared by the 4 orientations (identical maths): **2.3–3.6× faster** than HEAD
  (192: 84/128 ms → 35/29; 576: 686/913 → 292/249).
- R5 cursor distance aspect-corrected (HEAD's was an ellipse).

**Ideas in the diff (3):**
1. *Principal-strain orientation* (**Structure-tensor orientation**, §12.2A) — l.123–: Cauchy–Green `C = JᵀJ`, `θ = ½·atan2(2C₁₂,
   C₁₁−C₂₂)`, coherence `(λ₁−λ₂)/(λ₁+λ₂)`; the bank rotates by `θ·coh·strain·2` (l.202; HEAD: `atan2(vel)·strain·2`). Same J also
   gives σmax (tear gate) and σmin (strain).
2. *Thread lattice in material space* — `weaveLum` (l.74): plain-weave checker + thread crowns, period 9 source px, evaluated at the
   source/material position each pixel shows. Enters the Gabor tap luma at ±0.3·(w−0.55) (l.232) so the bank detects real
   0/45/90/135° thread structure that stretches and shears with the cloth, and the displayed cloth shows its threads
   (`mix(0.14, 0.30, strain)`, l.261) — folds of a smooth photo were nearly invisible before.
3. *Compression buckling* — l.278: `det J < 1` darkens (wrinkle valley, −38 %), `det J > 1` lifts (+12 %, threads spread). No new state.
Formula names: Structure-tensor orientation (§12.2A), Isotropic 9-point Laplacian (§12.2D, used as the rescue coupling).
Header `Ideas:` + `Rescue:` lines added; `Upgraded: 2026-11-09`. JSON: `upgraded-rgba` feature added (ACES on display + ideas),
`x-meta.upgrade.params` aligned additively; `params` byte-exact (asserted against HEAD).

**Default-look change:** yes, large — this is the rescue. HEAD default: saturated Gabor wash that worsens over time; new: the
photo with a thread lattice, soft cloth flutter, a strained psychedelic patch + radiating waves around the cursor (idle cursor is
parked at 0.5,0.5 so the focal patch is always there, as HEAD's push always was). Stats (192, 24 fr, t 2–5, defaults): idle
meanL 0.491→0.529, stdL 0.111→0.145, meanA 0.847→0.880; held 0.501→0.543 / 0.106→0.129 / 0.847→0.880 (ACES lifts mids).
Stability: new strain mean 0.32 steady 60→300→600 frames, `strain>0.5` on 14–16 % of pixels (my first, too-hot tuning had 87 %;
HEAD's strain is a different quantity — displacement size — so it is not numerically comparable, but its renders are visibly
saturated and growing).

**Gates:** wgsl_precommit_gate ✅; audit:extrabuffer PASS; audit:dead-sliders PASS (tearThreshold verified live: tear 0 vs 1 at
300 frames, held area differs in strain by >0.05 on 23 % of pixels, max displacement 0.122 vs 0.031). Param extremes at 300
frames: stiffness 1 (calm, strain 0.15), stiffness 0 (floppy, strain 0.89 before the tether floor was raised), damping 1 + gravity 1
(ringing, bounded by the 0.15 clamp), tear 0 + held: no NaN, no blow-up.

**Open items / doubts:**
- Stepping is per frame at a fixed dt (as HEAD): cloth speed is frame-rate dependent.
- A is rgba16float on real tiers: offsets are f16-safe by design but this was only run in f32 (minirender) — needs a real-GPU
  check, particularly the calm regime (d ≈ 1e-3).
- Saturated regions (strain→1, around the cursor) show pixel-scale palette confetti: the HEAD bank uses the even (cosine) Gabor
  phase only, so a periodic lattice makes it oscillate with phase. Kept (Gabor recipe is KEEP VERBATIM); lattice amplitude in the
  bank lowered 0.8→0.5→0.3 for it. A quadrature (even+odd) pair would remove it but changes the kernel.
- Tears are soft and heal; a permanent rip would need a state channel A does not have.
- Stiffness at its minimum is still very floppy (by design — it is the loose-cloth end of the slider).
- Real-GPU visual QA is external; nothing here is claimed to "look right" beyond SwiftShader.
