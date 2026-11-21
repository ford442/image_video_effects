# BRIEFS — fork C (liquid-jelly-fluid, interactive-magnetic-ripple-em)

Written BEFORE any WGSL edit. HEAD = worktree file after the coordinator's prelude migration (copies in the fork-C scratch dir).
Evidence below comes from GPU (SwiftShader) raw-state renders and a numpy port (`em_port.py`), both in the scratch dir.

---

## 1. SHADER: interactive-magnetic-ripple-em

**IDENTITY (one sentence):** a 2-D electromagnetic-wave field (E vector + out-of-plane B + energy) that the pointer drives as a dipole and clicks launch as rings, shown as iron-filing stripes, a spectral glow and an E-field warp of the photo.

**KEEP VERBATIM:**
- 4 params and roles: `field_strength`→`fieldGain` (source amplitude), `ripple_freq`→`waveSpeed` (grid wave speed + ring speed), `damping`→`damping`, `color_rotation`→`spectral` (palette phase + warp amount). JSON `params` untouched.
- A packing = raw sim state `(E.x, E.y, B, energy)`; clamp ±2.5 / 0..4; **never ACES on A** (only on `writeTexture`).
- Source terms: held pointer dipole (tangential E + `sin(6t)` B), click rings (tangential E + ±B alternating by index).
- Divergence-clean term (`electric -= (∂xEx,∂yEy)·divE·0.025`).
- Display: iron-filing `pow(cos(dir*10 + …),12)`, `spectralColor` cosine palette from `magnetic`/`energy`, warp `uv + E/du*(3+spectral*4)`, semantic alpha `energy*0.32+filings*0.45`.

**HEAD findings (all verified, numbers):**
1. **Faraday sign is wrong → elliptic, not a wave.** HEAD: `E += c·curlB`, `B += c·curlE`; analytically `∂²B/∂t² = −∇²B`. CPU port (single B pulse, 128², clamp ±2.5): energy @10/60/120/240 frames = 6.2 / 2.1e4 / 1.2e5 / 2.7e5 at the default sliders (saturated: 128²·2.5² ≈ 1e5 per field); same at damping 0, at speed 0 it still grows (1.7e4 at 240). GPU raw-state render of HEAD after ONE click (128², defaults): E-energy 1.3e3 @15 frames → 5.8e4 @60 → 2.9e5 @150, **97.3 % of pixels pinned at |B| = 2.5** by frame 150. Picture: a growing grid-aligned *diamond* of cyan checker noise (see `em_head_click150.png`) — not a wave.
2. Flipping the sign alone is **not** enough: with forward Euler (HEAD's scheme) the true wave equation is weakly unstable (amplification √(1+ω²)/step): port, flipped sign, default speed, default damping: 0.52 → 1.6e-3 @60 → 2.0e-2 @120 → **5.0e4 @240** (blows up once the high-k modes outgrow the damping); speed 0.5/damping 0 and speed 1: saturates. A symplectic (leapfrog) update — B first, then E from the *new* B — decays monotonically at every setting tried (speed 0..1, damping 0..0.5; 2.3 → 0.18 @240 at damping 0).
3. HEAD decay `exp(-damping·(0.6+dt·30))` ≈ 0.91 per frame at the default slider. With a *stable* wave a ring would die within ~5 cells (wave speed 0.49 cell/frame). HEAD never noticed because the instability fed it.
4. No pointer + no click ⇒ `meanA 0.000`, picture = source photo (Finding 1 of COMMON).
5. `pow((len−radius)*64.0, 2.0)` with negative base in the click ring: latent on real GPUs, unproven on SwiftShader (0 NaN with a click).

**RESCUES (loud — they change the default look):**
- **R1** symplectic Faraday/Ampère update (B' = B − c·curlE; E' = E + c/ε·curl B' with B' recomputed at the 4 axis neighbours → 13 state loads instead of 5).
- **R2** damping calibration: decay constant 1.1 → 0.04 per frame·slider (`exp(-damping*0.04)`); slider role unchanged ("more = dies faster"), ring-down at the default becomes ≈5 s instead of 0.5 s. A stable wave cannot live in HEAD's calibration.
- **R3** idle antenna: with the pointer *not* held, the same dipole source runs at a weak amplitude on a small orbit around the pointer (default pointer 0.5,0.5), so the effect shows at default. Held pointer behaviour is unchanged.
- **R4** `pow(x,2.0)` → `x*x` in the click ring (bit-identical for finite values).

**ADD (2–3 native ideas):**
1. **Dielectric photo medium** — the photo's luma is the relative permittivity `ε_r = 1 + 2·luma`, the E update becomes `c/ε_r · curl B`: wave speed `c/√ε_r`, so wavefronts slow down and refract around bright objects in the photo. Belongs here: Maxwell in matter is the first-order consequence of the field the file already solves; it makes the *picture* shape the waves, not just be warped by them.
2. **Absorbing sponge boundary (PML-lite)** — conductivity `σ(d) ∝ (1−smoothstep(0,0.09,d_edge))²` multiplies E and B near the frame edge so waves leave the frame instead of reflecting (HEAD's clamp-to-edge `stateAt` is a mirror; weakly damped waves would fill the screen with standing interference).
3. **Poynting-flux energy transport** (if it reads) — the `energy` channel is currently the isotropic smoothed `E²+B²`; add first-order upwind advection of it by the energy velocity `S/u` with `S = (E_y B, −E_x B)` using the 4 neighbours already loaded (0 extra loads), so the spectral glow visibly travels with the wave front.

**§12.1 interrogation:** tactic 1 (deepen kernel): forward-Euler → leapfrog is the next-better scheme for the same curl operator. Tactic 2 (physics one step further): Maxwell in a dielectric; open-boundary absorption (every FDTD code has it). Tactic 3 (promote an intermediate): `curlE`, `gradB`, `electric`, `magnetic` already exist; `S = E×B` falls out for free. Tactic 6 (history): C is read as raw fields; leapfrog needs only C at radius 2 — no change to packing.

**§12.4 formula admission:** idea 1/2 are rows "Damped wave equation / dielectric medium / sponge boundary" (claimed by this file only). Both consume state the file already has (E, B, uv); idea 1 additionally consumes `readTexture` luma (one sample) which the file already samples elsewhere. Deletion test passes both ways (remove either → still the same ripple/filings effect; remove the EM field → not this effect). Idea 3 passes only if visible; otherwise it is dropped and recorded as rejected.

**FORBID:** new springs/extraBuffer, IQ palette changes, ripple/shockwave overlays beyond the file's own click ring, replacing filings, any new param, `fwidth`.
**A PACKING:** raw state `(Ex, Ey, B, energy)` unchanged (not tone-mapped).

---

## 2. SHADER: liquid-jelly-fluid

**IDENTITY:** a translucent, wobbling dye fluid over the photo — semi-Lagrangian velocity+density advection, one-iteration pressure, vorticity confinement, ambient ribbon/Kelvin–Helmholtz forcing, pointer stir and click fronts; cyan/violet/lime dye keyed to flow angle and curl.

**KEEP VERBATIM:**
- Params: `viscosity`→`viscosity` (diffusion + density persistence), `dye_intensity`→`dyeGain`, `vorticity_strength`→`confinement`, `elasticity`→`elasticity` (ribbon + click forcing). JSON `params` untouched.
- A packing = raw state `(vel.x, vel.y, pressure, density)`, exact bounded loads; ACES only on `writeTexture`.
- Vorticity confinement, 1-iteration pressure projection, ribbon/kh ambient forcing, pointer stir (`held`), click fronts, density source/decay, dye palette (cyan/violet/lime) and its angle/curl mix, speed/packet emission, photo displacement `uv + vel*1.8`, depth write.

**HEAD findings (verified):**
1. **Held pointer ⇒ white-noise dye.** Per-component clamp ±0.065 UV/frame (±8 cells/frame at 128²) saturates under the stir forcing (20 % of pixels at the clamp). Velocity roughness `|v − avg4(v)|/|v|` = **0.230 / 0.251 / 0.252 at 128 / 256 / 512 px** (resolution independent) — the dye hue is keyed to `atan2(vel)` so it flips per pixel; picture is cyan/violet speckle that hides the photo (`jelly_head_held5_*.png`). Idle (no pointer) is smooth (roughness 0.087, density std 0.000).
2. `subsurface-scattering` is in JSON `features`/`tags` but nothing in the code is subsurface: dye is an opaque `mix(src, color, clamp(density·dyeGain·0.55, 0, 0.88))`.
3. Idle density is a perfectly uniform 0.2 (source `0.0025` everywhere) — fine, left alone.

**RESCUE (loud):**
- **J1** replace the three per-component clamps (±0.06, ±0.06, ±0.065) with one *magnitude* limiter `vmax = 0.03`. Held pointer, 90 frames: HEAD roughness 0.230 / 0.251 / 0.252 at 128 / 256 / 512 px; with vmax 0.03 it is **0.030 at 192 px and 0.018 at 384 px** (limiter measured at 192/384, HEAD at 128/256/512 — resolution-independent in both cases); mean |v| 0.047 → 0.024 (half the peak speed kept). Idle: roughness 0.087 → 0.071, mean |v| 0.0153 → 0.0143 (unchanged look). Alternatives measured: hue smoothing alone does not help (picture still speckle); confinement off / pressure off do not change it (so they are not the cause).

**ADD (2 native ideas):**
1. **Translucent jelly body — Beer–Lambert + subsurface wrap** (§12.2F; claimed by atmos-fog + jelly). HEAD's mix weight `density·dyeGain·0.55` is already an optical thickness τ. The photo is now seen *through* the dye: `T = exp(−σ·τ)` with σ = absorption of the complement of the dye colour (cyan jelly eats red), plus in-scatter `color·(1−e^(−1.2τ))`, plus a subsurface wrap term `color·wrap(n·L)·(1−e^(−1.4τ))e^(−0.6τ)` that peaks at intermediate thickness so thin rims glow. Belongs on THIS file: density *is* the jelly's thickness and the JSON already promises subsurface scattering.
2. **Wet-jelly sheen — Fresnel–Schlick + Blinn on the density surface** (§12.2F; claimed by metal + jelly). Normal from the density gradient of the four neighbours HEAD already loads (0 extra loads): Schlick rim `0.04+0.96(1−n_z)^5` plus a tight Blinn highlight, gated by density so the idle (flat) jelly is unchanged. Alpha gains a small sheen/coverage term.

**Tried and rejected (recorded so nobody repeats it):** (a) elastic recoil by letting the pressure channel keep a fraction ε of itself (`mix(avg, p, ε)`, ε = 0/0.5/0.8/0.95, one click, KE over 20–160 frames: 8–32 ×1e-5 in all four, differences inside ambient-forcing noise) — no measurable bounce, not shipped. (b) MacCormack dye advection (§12.2D): with nearest-neighbour fetches and a far departure point the neighbourhood clamp needs +4 loads and the benefit is unmeasurable — not shipped.

**§12.1:** tactic 3 (promote intermediate): `density` is thickness, `l/r/d/up.w` already loaded → normal for free. Tactic 5 (device artifact): a jelly's two optical signatures are translucency/absorption and a wet specular glint. Tactic 6: C is read as raw fields; nothing in the new code touches C packing.
**§12.4:** both rows are the lighting/optical table; both consume `density` + loaded neighbours; deletion test: remove either and it is still the same dye fluid; remove the solver and nothing is left of the effect. Fresnel–Schlick appears on jelly + metal only, Beer–Lambert on jelly + atmos-fog only (COMMON claims).
**FORBID:** springs, extraBuffer, new palettes (cyan/violet/lime kept), Gray–Scott, replacing the solver, new params.
**A PACKING:** raw state `(vel, pressure, density)` unchanged.

---

## AMENDMENTS (written after implementation; the cards above are unchanged, this records what moved and what was wrong)

1. **Correction — the "after ONE click" GPU numbers in §1 finding 1 were not a one-shot click.** `agents/mr.mjs` sets `ripple.z = t − r[2]`, so the 3rd `RIPPLES` value is a constant *age*; `RIPPLES='…,0.0,0'` is a click source pinned at age 0 for the whole run. Re-measured with a harness copy that takes an absolute start time (`agents/mr_c_abs.mjs`, `RIPPLES='x,y,start,0'`): HEAD, true one-shot click at t = 0.1 s, 128², defaults: E-energy 2.0e3 @30 frames → 5.9e4 @90 (19.5 % of pixels at |B| = 2.5) → 1.9e5 @150 (64.7 %) → **3.0e5 @300 (99.4 %)**. The CPU-port numbers (B pulse, no source) were already one-shot and stand. Conclusion unchanged, figures replaced. (Other forks using `RIPPLES` with a 3rd value of 0 are also testing a pinned click.)
2. **Scheme changed from symplectic leapfrog (13 loads) to a staggered Yee-style update (7 loads).** The leapfrog needed a radius-2 stencil: timed 1.47× HEAD (median, range 1.24–1.75, 6 interleaved rounds at 512², held pointer), over the ≈1.3× cap. The Yee form (B advanced with forward differences of E, E advanced from the new B with backward differences — the adjoint pair) needs c, e, w, n, s, nw, se only; timed 1.10× (0.87–1.50, 7 rounds). It is stable for c ≤ 1/√2, so the propagation constant is `waveSpeed*0.77` (top of the slider 0.69 cells/frame; slider keeps its full range and role). Bonus: forward/backward differences have no checkerboard null space.
3. **Divergence clean replaced (R1b), not kept verbatim.** HEAD's `E −= (∂xEx, ∂yEy)·divE·0.025` is quadratic with an indefinite sign. Bisected on the GPU (remove one term at a time, stable scheme otherwise): with it |B| reached the 2.5 clamp; without it energy stayed ~0.7–18. Replaced with the linear dissipative `E += 0.05·∇⁻(∇⁺·E)` (same intent: damp the longitudinal part of E), using only the 7 loaded cells.
4. **Source calibration `srcCal` (R2b).** With a stable wave and HEAD's source constants the field peaks at |B| ≈ 0.1–0.5 and the display thresholds (`smoothstep(0.03,0.7,|E|)`, `energy*0.55`) show almost nothing. `srcCal` multiplies the dipole, idle-antenna and click sources (a calibration constant, not a slider). Chosen by measurement: 10 and 6 clipped the click/held sources at the ±2.5 clamp (1–3.6 % of pixels), 3 touched it only at hotspots at 128², 2.5 does not clip in any test at 128²–512².
5. **Idea 3 (Poynting transport) kept but it is the quietest idea.** Sign verified on a plane-wave packet (CPU port): the packet moves to +x when Σ Ey·B > 0 and to −x when it is negative, so upwind advection by S/u follows the wave. Ablation (held + click, 256², 300 frames): removing it changes 36 % of pixels by > 0.02 but only 4.6 % by > 0.1 (mean |d| 0.015). Medium: 77.5 % / 47.1 % (mean 0.084). Sponge: 34.0 % / 12.0 % (mean 0.024).
6. **Jelly: no change to the cards** beyond tuning constants after looking at renders (σ = (1−color)·1.0 + 0.15 so the photo stays visible under thick dye; specular 0.6, normal slope capped at 1 to stop rim glitter). The elastic-pressure-memory and MacCormack experiments stay rejected (numbers above).
