# BRIEFS — Fork C (cyber-ripples-coupled 2nd pass, digital-haze 1st pass)

Written BEFORE any WGSL edit. Renderer: private copy of minirender_img (scratchpad/forkC/rend.mjs) adding real click ripples (`RIPPLES`), a moving cursor (`MPATH`), the app's per-frame zeroing of extraBuffer (`ZERO_EXTRA=1`) and a crisp test photo (`SRC=detail`: checker cells, 1 px grid lines, diagonal bars, small bright lights). The shared tools feed `config.y = 0` (no ripples), a static cursor, and a never-zeroed extraBuffer, so they cannot show either shader's click / cursor behaviour.

## HEAD findings (measured, 192 px unless noted)

| What | cyber-ripples-coupled | digital-haze |
|---|---|---|
| idle, audio 0 | meanL .509 stdL .162 meanA .061 | meanL .507 stdL .172 meanA .119 |
| moving cursor, app semantics (extraBuffer zeroed) | **identical to idle** (.509/.162/.061) — cursor stirs nothing | ≈ idle (.508/.169/.126) — window has zero lag |
| moving cursor, shared-tool semantics (extraBuffer persists) | meanA .080, visible swirl trail in the alpha panel — what the dead spring was *meant* to do | ≈ idle |
| click ripples fed | ring speckle + dens discs appear | no visible change |
| default / max / min sliders on SRC=detail (288 px) | n/a | **all three look identical**: no haze, no hex lattice, no pixelation, no clear window |

## RESCUE list

### cyber-ripples-coupled
- **R1 dead pointer spring.** `extraBuffer[133..138]` is re-uploaded zeroed every frame, so `hasSpring && extraBuffer[138] > 0.5` is false on every frame, `mouseVel` is 0 for all pixels, and `vel += mouseVel * influence * 0.5` plus the swirl term never fire. Cursor motion does nothing (measured: moving == idle). Fix: critically-damped spring (omega 10, HEAD's constant) state in A texels (0,0) = (pos.xy, vel.xy), (1,0) = (fract(lastTime), 0, 0, 0.7371). Every thread integrates the same step; C reads at those two texels are masked (and inside `load_bilinear`). Idle cursor: spring sits on the raw cursor with zero velocity → default look unchanged.
- **R2 fake vorticity.** A.z was `vel.x - vel.y` (not a curl, and never read back). It becomes the real scalar curl ω = ½((v_r.y − v_l.y) − (v_b.x − v_t.x)) of the previous velocity field (same 4 taps used for the confinement gradient). Packing line + JSON `feedbackPacking` updated truthfully.

### digital-haze
- **R1 invisible haze.** `STEP_SIZE = 0.03` is the *entire* ray path, so τ = σ·0.03·(1+0.5·noise) ≈ 0.045, T ≈ 0.956: the haze layer carries ≈ 4% in-scatter and `finalHaze·(1−T)·0.3` ≈ 1.3% of the pixelated/hex layer. At HEAD the shader is an ACES identity filter; all four sliders are visually dead. Fix: a real slab path length (`HAZE_PATH`) with σ values and slider roles unchanged (haze_density still 0.4×..1.6× around the default), and the transmitted-haze weight restored to the comment's own formula. **Default look changes a lot** (documented, expected for a rescue).
- **R2 dead spring.** Same extraBuffer cause: window follows raw cursor with zero lag while comments claim a sprung wipe. Fix: same A-texel spring + sentinel (omega = 2·sqrt(40) damping, HEAD's K). C.r reads masked on the two state texels.
- **R3 dead per-cell FFT.** `plasmaBuffer[(cell%8)+1].x` is never uploaded (always 0) → noise multiplier is exactly 1. Replace with live `plasmaBuffer[0].z` (treble) gated per cell by the cell hash, so static flickers cell by cell with the highs; JSON/description updated ("per-cell FFT" → "per-cell treble static").
- **R4** `hazeColor`/`finalHaze` both carry the iridescent tint; the comment's formula `transmitted_haze * (1-T)` had a stray ×0.3. Reconciled as part of R1.

## Idea Cards

```
SHADER: cyber-ripples-coupled
IDENTITY: a photo displaced by a fluid-coupled digital ripple field — stepped rings round the cursor, a
  velocity/density field that carries chromatic aberration and warm tint, a cyan packet streak, click rings
  with crest doubling and orbiting charge halos.
KEEP VERBATIM: 4 param roles (speed / viscosity = decay mix 0.92–0.99 / aberration / frequency); fp128 phase
  maths; stepped quantizedDist wave around the cursor; vortex_packet; semi-Lagrangian advection through exact
  C with bilinear load; outward click impulse + dens; crest doubling; orbital charge ring; ACES; semantic
  alpha formula; A = raw (vel.xy, vorticity, density).
ADD:
  1. Vorticity confinement (§12.2D) — the swirl the cursor/click wake already carries is re-injected as
     f = ε·(N × ω), N = ∇|ω|/(|∇|ω||+ε) from the stored curl in C.z, instead of dying to the multiplicative
     viscosity decay. Native: the shader is a fluid-coupling sim and already has a "vorticity" slot.
  2. Dispersive ring train (§12.2D deep-water dispersion) — behind each click's ring front a trailing
     wave train with deep-water phase φ = g·t²/(4r) (stationary-phase point-impulse solution: wavelength
     shrinks toward the origin and over time), amplitude falling behind the front. It refracts the image
     radially and feeds crestPhaseSum, so the existing crest doubling now sees trains, not single bands.
FORMULA ADMISSION: both rows are in the D table for a sim that stores velocity + a vorticity slot; (1)
  consumes C.xy/C.z already read, (2) consumes ringRadius/elapsed/rDist/frequency already computed.
  Deleting either leaves exactly HEAD's ripples; keeping (2) alone is not a ripple effect without the front.
FORBID: a new spring/ripple/IQ overlay, touching the packet, replacing the solver, new params.
A PACKING: raw sim state (vel.xy, curl ω, density). Texels (0,0) = pointer spring (pos.xy, vel.xy) and
  (1,0) = (fract(lastTime), 0, 0, 0.7371) are STATE, not pixels (corner texels; their C read is masked).
```

```
SHADER: digital-haze
IDENTITY: foggy glass over the photo — a pixelated, noisy, hex-latticed, iridescent veil that is thick
  outside a clear window which follows the cursor; clicks wipe holes.
KEEP VERBATIM: pixel_strength → pixelation grid; clear_radius → window (smoothstep r..r+0.2, held ×1.3);
  noise_amount → hash jitter on the quantised uv; haze_density → 0.4×..1.6× extinction; hexEdge lattice and
  hexScale; iridescentHaze palette; bass pulses density, mids pump hex + noise; click clear-pulses
  (PULSE_RADIUS/DECAY/LIFE); Beer–Lambert composition; ACES; alpha form; A = (fog mask, alpha, 0, 1).
ADD:
  1. Re-fogging wipe memory (history, tactic 6) — the fog mask in C.r now persists: a wiped path and click
     holes re-fog over seconds, fastest where surrounding fog is close (condensation creeps in from the
     edges), slowest in the middle of a big cleared patch. This is the shader's own metaphor ("a hand
     wiping fogged glass") given a physical memory; HEAD's mix(…, 0.08) hysteresis lasted ≈ 1 frame.
  2. Chromatic Beer–Lambert (§12.2F) — extinction per channel σ·(0.80, 1.00, 1.35): thick fog transmits
     warm and its in-scatter veil is cool, Rayleigh-ish, so haze density has a colour, not just a gain.
  3. Forward-scatter glare (§12.2F, Henyey–Greenstein) — 8 taps around each pixel gather source
     highlights weighted by the HG phase (g = 0.6) of the scatter angle at the tap radius; added to the
     veil by (1−T)·fog, so lights glow through the haze. (Idea 2 + 3 are the same §12.2F row on this file.)
FORMULA ADMISSION: all three consume what the shader owns — C.r mask history, the extinction τ it already
  computes, the source taps it already samples. Deleting any leaves exactly this foggy-glass filter.
FORBID: new params, springs beyond fixing the existing one, ripples-as-shockwaves, IQ palettes, changing
  the hex/pixel look, replacing the veil with a fog sim.
A PACKING: display-adjacent field: A.x = fog mask (persisting history, read back as C.r), A.y = alpha.
  Texels (0,0) = window spring (pos.xy, vel.xy) and (1,0) = (fract(lastTime), 0, 0, 0.7371) are STATE.
```

## Mechanism interrogation (§12.1)

**cyber-ripples-coupled**
- T1 deepen the kernel: advection is first-order semi-Lagrangian with decay and no force other than the mouse (dead) and click impulses; the missing term of the same operator is vorticity confinement (small swirls the grid damps).
- T2 follow the physics: a point impulse on deep water leaves a dispersive train (chirp), not a single Gaussian ring; HEAD draws only the front.
- T3 promote an intermediate: the stored "vorticity" slot already exists; a true curl costs the 4 taps the confinement gradient needs anyway. `ringRadius`, `elapsed`, `rDist` are already computed per ripple.
- T6 use the history: C is read as FIELDS (vel, ω, dens). Extra continuity without changing packing: ω itself (z) feeds the next frame's confinement.
- Same-noun test: "vortex / swirl / wave train" are all fluid nouns. Deletion test: fine both ways. Expert test: a fluids author recognises vorticity confinement; a water-wave physicist recognises the dispersive chirp.

**digital-haze**
- T1 deepen the kernel: Beer–Lambert with one scalar σ → per-channel σ (the same operator, chromatic).
- T2 physics one step further: fog on glass does not vanish when the hand moves on — it condenses back from the surrounding fog; and fog scatters light forward around bright points (glare).
- T3 promote an intermediate: `transmittance`/`opticalDepth` and `colClear` already exist; the source taps for glare reuse `readTexture`; `prevHaze` already reads C.r.
- T6 use the history: C.r is read as the fog mask; the one extra piece of continuity is the regrowth of that mask itself.
- Same-noun: fog, glass, condensation, glare, extinction. Deletion: each removable, leaves this filter.

## AMENDMENT (after implementation + measurement) — cyber-ripples-coupled Idea 1 replaced

The card's Idea 1 **vorticity confinement was implemented, measured and CUT.** Evidence (288 px, app-style zeroed extraBuffer, circling cursor and an arc-then-hold cursor):
- K = 0.35, ε = 0.002: grid-scale speckle in the wake (alpha-panel high-frequency energy 0.86 vs 0.36 without it); ε = 0.02 removes the speckle but then the effect is only 22 px > 8/255 different from "off" (K = 0.15: 2 px).
- Persistence test (cursor sweeps an arc for 1 s, then holds; render 1.3 s and 1.6 s after): wake with confinement 0.35 is indistinguishable from off; 0.8 only adds edge speckle.
- Cause: the cursor stir is a divergent push plus a small swirl term; there is no coherent vortex for confinement to preserve, so it amplifies grid noise. Fails the "visible, native" admission, so it is not shipped.

Replacement Idea 1 (now numbered 3 in the WGSL, after HEAD's two): **refractive density lens** — the density bump that clicks raise (`dens += rInfluence*0.5`) is the fluid's surface; the slope of the *stored* density (the 4 axial taps already loaded for the curl) bends the photo like a droplet. Tactic 3 (promote an intermediate) + tactic 2 (a bump in a fluid surface refracts). Not a §12.2 row. Deletion test: removing it leaves HEAD's click look (speckle + dens tint). Measured: zero effect under cursor-only stirring (density is only raised by clicks), strong effect on clicks (0.0025 gave glass-bubble rims → halved to 0.0012).
Final cyber-ripples ideas: (3) density lens; (4) deep-water ring train. §12.2 rows used by Fork C: Deep-water dispersion (D) on cyber-ripples; Beer–Lambert/HG (F, one row) on digital-haze. Vorticity confinement / damped wave / 9-pt Laplacian: unused (budget returned).
R2 stays: A.z is a true curl (4 taps shared with the lens), documented, though nothing reads it yet.

digital-haze constants tuned after rendering: HAZE_PATH 0.55; SIGMA_RGB (0.60, 1.00, 1.70) (first try 0.80/1.35 was a ~4/255 shift; Rayleigh λ⁻⁴ would be 0.5/1/2.2); GLARE_AMT 2.0; HAZE_VEIL 0.85.
