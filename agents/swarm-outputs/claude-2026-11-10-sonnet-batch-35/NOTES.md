# sonnet/batch-35 — NOTES (per shader: kept verbatim, packing, where each idea lives)

Header date `2026-11-10`. Idea numbers match `BRIEFS.md`; grep `Idea n` in the WGSL. Infrastructure commit `798d840` (4 prelude migrations, no `Upgraded:` bump) is separate from the idea commit.

| # | id | Ideas actually in the diff | §12.2 rows | Rescue (not an idea) |
|---|---|---|---|---|
| 1 | fiber-optic-weave | chromatic pulse dispersion; macrobend leakage | F Cauchy dispersion | — |
| 2 | biomimetic-scales | circuli growth ridges; imbricate contact shadow | — | **unit mismatch: scales effectively never rendered** |
| 3 | breathing-kaleidoscope-morph | mirror-seam bevel; white top-hat re-injection | — | — |
| 4 | gen-magnetic-liquid-glyphs | meniscus bevel normal (true SDF gradient); Rosensweig spikes | — | (the old normal was a one-axis bump; replaced by idea 1) |
| 5 | mouse-wormhole-lens | Doppler-beamed photon ring; gravitational redshift (ideas 3–4, second pass) | — | clamp before ACES |
| 6 | gen-cymatic-void-glass-geode | Chladni nodal sand-lines; step-count AO | E Step-count AO | **audio read from a never-written texel** → `plasmaBuffer[0].x`; truthful depth |
| 7 | gen-mushroom-mandala-garden | striate translucent margin; hyphal anastomosis nodes (ideas 5–6, second pass) | — | — |
| 8 | optical-illusion-spin | asymmetric 4-step luminance ramp; peripheral gain / fixation dead-zone | — | — |
| 9 | glass-wipes | inverted drop-lens; squeegee residue line | F thin-lens inversion | — |
| 10 | steampunk-gear-lens | Brown–Conrady barrel magnification; turned-brass anisotropic rim | B Brown–Conrady | — |

No §12.2 row appears on more than one file. No spring, ripple, IQ palette, conveyor or new param was added anywhere. Saved `params` are byte-exact in every JSON; JSON edits are additive only (`x-meta.upgrade.params` on 4 files, honest feature tags on 2).

---
## 1. fiber-optic-weave
- **Kept verbatim:** 4 params/roles; strip + odd/even weave; pluck gate; click pulses; repulsion; `glowFactor` edge glow; golden-ratio pulse position and palette; peak limiter; alpha; depth; A = display RGBA.
- **Idea 1** (`// ── Idea 1: chromatic pulse dispersion`): `cauchyDelay(0.02)` = n(λ)/n(550)−1 at 650/550/450 nm; per-channel pulse centre `pulsePos − delay·pulsePos` (red leads, blue trails); width ∝ √distance; sharp leading / long trailing edge; amplitude normalised by 1/√spread. `pulseGlow` is now the green channel so alpha is unchanged in meaning.
- **Idea 2** (`// ── Idea 2: macrobend leakage`): the pluck/click bends were already sinusoids; their curvature is `amp·k²·|sin|` (closed form), normalised by 60. Red-biased `(1,0.38,0.12)` glow in the cladding band of the strip, amplitude `0.35 + 0.65·Mouse Force`.
- **Packing:** display RGBA (HEAD's).

## 2. biomimetic-scales
- **RESCUE (read this):** HEAD's `distVec = scaleUV − cellCenter·gridSize` subtracts a grid-unit centre from a UV-unit position. A CPU re-implementation of the hit test gives **0.28 % of pixels inside a scale in HEAD vs 100 % after the fix**; HEAD therefore rendered essentially the "gap" branch (`source·0.2`, alpha 0.14) — consistent with the committed thumbnail, which is a washed-out photo. The fix is the one line `baseGrid − cellCenter·gridSize`. This visibly changes the output (the scales now actually appear); it is the intended effect per the shader's own comments, but it is a behaviour change reviewers should look at on a GPU.
- **Kept verbatim:** 4 params/roles; 3×3 loop; stagger; radius 0.65; layer stacking; dome normal; pointer tilt; refraction `0.02·(1−roughness)`; diffuse/spec; gap branch.
- **Idea 1** (circuli): radial `sin(dist·40)` ridge, faded at the nucleus, perturbing the dome normal along `dirR`; amplitude `0.05 + 0.12·Roughness`.
- **Idea 2** (contact shadow): second 9-cell pass over scales with `y > maxLayer`; shadow = `smoothstep(0.89, 0.65, dist to caster centre + (0.10, 0.10))`; darkens diffuse (−55 %) and removes spec.
- ACES added to display RGB (hit branch). **Packing:** A = (diff, spec, 1, alpha), raw lighting terms, unchanged.
- JSON: `audio-reactive` (bass/mids/treble modulate density/lift/spec) and `upgraded-rgba` (ACES + ideas) added.

## 3. breathing-kaleidoscope-morph
- **Kept verbatim:** 4 params/roles; `ping_pong` breath; fold; ripple distortion; golden-ratio per-segment blend; disk kernel with pointer anisotropy; `gradient·0.3`; alpha = top-hat luma.
- **Idea 1** (mirror seam): `min(m, 1−m)·segmentAngle/2` angular distance to the nearest reflecting edge × radius × `resolution.y` = pixel arc length; `exp(−px·0.7)`, faded at the apex, gated by `blend`.
- **Idea 2** (top-hat): `clamp(topHat,0,1)·morphBlend·(0.2 + 0.3·breath)` added to `finalRGB`.
- **Packing:** display RGB + top-hat luma alpha (unchanged). No ACES added (HEAD did not claim it).

## 4. gen-magnetic-liquid-glyphs
- **Kept verbatim:** 4 params/roles; domain warp; glyph wheel (moved into `wheelD()` unchanged); `mask`/`edge`; palette, spec, fresnel, aurora; envelopes in C.rg; ACES + hue-preserve + IGN; transmission alpha.
- **Idea 1** (meniscus bevel): forward-difference gradient of `wheelD` (2 extra evaluations: 3 wheel evaluations per pixel in total, was 1), `tilt = exp(−inside·38)`, normal `(gScreen·tilt·1.6, 1)`, gradient rotated back with `rot(−fieldAngle)`.
- **Idea 2** (Rosensweig): lattice across the field (`p.y`), period 0.05–0.07; facing term `smoothstep(0.55,0.95,|∂d/∂p.x|/|∇d|)`; height `0.004 + 0.013·√((bassEnv−0.12)/0.88)`; the lattice slope is added to the gradient so the shading follows the flanks.
- **Packing:** A = (bassEnv, trebEnv, **pre-spike** d, alpha) — documented packing preserved.

## 5. mouse-wormhole-lens (second pass)
- **Kept verbatim:** 4 params/roles; velocity stretch; spiral mapping; mirror; edge ring; the two shipped ideas (inverse-square lensing; exact-C throat ghost); click mini-portals; alpha.
- **Idea 3** (photon ring): ring at normalised radius 0.52, width 0.045; `(1 + 0.65·cos(φ + 0.5t))³ / 4.49` (spiral samples at `+0.5t`, so the pattern turns at −0.5).
- **Idea 4** (redshift): `redshift = (1−nd)²·LensStrength·1.2`; multiplies `(1, 1−0.5r, 1−0.8r)·(1−0.4r)`.
- Floor: `max(color, 0)` before ACES. **Packing:** ACES display RGBA (unchanged).

## 6. gen-cymatic-void-glass-geode
- **Kept verbatim:** 4 params/roles; Apollonian fold; `base_sdf + disp`; camera; palette; vein glow; step SSS; gamma.
- **RESCUE:** `audio_sample` was `dataTextureC(0,0).x`; this file never writes A, so audio never reached it. Now `plasmaBuffer[0].x`, with the modulation **0.8** (was a nominal 2.0 that never ran) so a loud bass cannot make the displacement overstep the march.
- **Idea 1** (nodal lines): `cymaticWave()` factored out (the same function in `map()` and in the shading); line = `exp(−(wave/(slope·0.035))²)` with a closed-form slope; gated by Cymatic Amp/Freq so lines exist only while the plate vibrates.
- **Idea 2** (AO): `aoFive()` — five `map()` taps along the normal.
- Depth written (`1 − d/MAX_DIST`, 0 for sky). Alpha stays 1.0 on purpose: this is an opaque scene; changing it would change the identity. **Packing:** display RGB only.
- JSON: `features` added (`audio-reactive`, `mouse-driven`) + `x-meta.upgrade.params`; saved params untouched (including their 0.1–5 ranges).

## 7. gen-mushroom-mandala-garden (second pass)
- **Kept verbatim:** 4 params/roles; the four shipped ideas; sinusoidal mycelium lines; fairy ring; history mix; ACES; alpha.
- **Idea 5** (striate margin): `capShade = cap·(1 − 0.45·smoothstep(0,0.16,ringCoord)·lamella)`.
- **Idea 6** (anastomosis): crossing hypha family `hyphaPhaseB`; `fusionNode = lineA⁵·lineB⁵`; nutrient pulses `pow(0.5+0.5 sin(p·7 − t·rate), 4)` along each family; rides mids; adds 0.2·node to `structure`.
- **Packing:** ACES display RGBA in A (unchanged).

## 8. optical-illusion-spin
- **Kept verbatim:** 4 params/roles; `snakePattern`; packet pulse; Fraser whip; click twist; hold spin; afterimage; exact-C history mix; ACES; alpha.
- **Idea 1** (`snakeRamp`): black 0.05 → dark 0.35 → white 1.0 → light grey 0.70, mirrored on alternating rings (`alt`); weighted by `patA/patB` into `driftCue = mix(1, 0.45+1.1·ramp, 0.75·periph)`.
- **Idea 2** (`fixation`): `smoothstep(0.04, 0.32, radius)` → `mix(0.35, 1, ·)` multiplies both patterns.
- **Packing:** ACES display RGBA (unchanged).

## 9. glass-wipes
- **Kept verbatim:** 4 params/roles; raw A (wetness, flow, thickness, coverage); beads/tails; splashes; pointer wiper; elastic sweep; gradient refraction; fresnel/spec/absorption; thin-film hue; ACES; alpha.
- **Idea 1** (drop-lens): bead centre `(cell + (0.18+0.64·seed, fall)) / (rainScale, 0.62·rainScale)`; sample mirrored about it ×2.6; weight `0.7·smoothstep(0.35,0.85,drop)`.
- **Idea 2** (residue): direction from `sweepT`; line at `sweepX − dir·0.97·wiperRadius/aspect`, σ = max(0.08·R, 0.004); deposited into `wetness` before the A store.
- **Packing:** raw A unchanged; ACES only on writeTexture.

## 10. steampunk-gear-lens
- **Kept verbatim:** 4 params/roles; gear shape; rotation + kick; mask/rim; sepia; click flares; depth relief; alpha.
- **Idea 1** (barrel): `p·(1+(M−1)ρ²)/M`, `M = 1 + 1.2·(1 − Gear Size)`; `k1 = M−1` makes the lens meet the picture seamlessly at ρ = 1.
- **Idea 2** (turned brass): grooves `0.88 + 0.12·hash(floor(r·520))`; world-fixed highlight `pow(|cos(a − 2.35)|, 8)` on the un-rotated angle.
- **Packing:** display RGBA (unchanged).

---
## Reported, not fixed (out of scope for an idea batch)
- `extraBuffer[133..138]` springs (`fiber-optic-weave`, `optical-illusion-spin`, `glass-wipes`, `steampunk-gear-lens`) do not persist: `writeExtraBuffer` re-uploads the whole buffer each frame. Behaves as the raw cursor. A(0,0) rescue (see batch-29 R1) would fix it.
- `plasmaBuffer[1..]` is not audio (`fiber-optic-weave` per-fibre voices, `glass-wipes` per-band hue) — those terms are silent.
- `biomimetic-scales` thumbnail is stale/wrong (HEAD never rendered scales). Regenerate on a GPU.

## Gates (Cloud VM, structural only)
`wgsl_precommit_gate.py` 10/10 · naga-wasm 10/10 valid · `audit:extrabuffer` PASS (0 new) · `audit:dead-sliders` 0 new dead sliders on all 10 · see the PR for catalogs / Vitest / build.
**Real-GPU visual QA: external and still required.** Nothing here claims the ideas "look right"; in particular the biomimetic-scales unit fix, the 3× SDF cost in the glyph shader, the cymatic AO (the Apollonian estimator is not a true distance, so AO strength may need tuning) and the glass-wipes residue visibility at small wiper sizes need a look.
