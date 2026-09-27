# Liquid Eight — Implementation Notes

**Agent:** spark · **Date:** 2026-09-21 · Cards: [`BRIEFS.md`](BRIEFS.md)

Grep `Idea 1` / `Idea 2` in each WGSL to land on the blocks. +295 / −31 across eight files.

### `liquid-rainbow-prismatic` (+21 / −4)
- **Kept:** HEAD slot roles; `surface()`; Cauchy nR/nG/nB; three refracted samples; film phase; history mix; Fresnel alpha.
- **Idea 1 — drainage + black film:** `swirl` / `drain` / `thickness = mix(swirl, drain, 0.45)` / `blackFilm`,
  and the film term is multiplied by `(1 - blackFilm)`. The original swirl is still 55 % of thickness.
- **Idea 2 — dispersed caustics:** the 6-tap caustic loop now gathers `.r` around `uvR`, `.g` around `uvG`,
  `.b` around `uvB`, ring radius scaled by each channel's own index. 18 taps where HEAD took 6.
- **A:** ACES display RGBA. Unchanged.

### `luma-velocity-melt` (+38 / −3)
- **Kept:** non-normalised param ranges used directly; hot mask; noise flow; swirl; click push; chroma split; HDR clamp 8.0.
- **Idea 1 — drip pinch-off:** `dripW` / `dripCol` / `colSeed` / `bead` / `pinch`; `flow.y` modulated by bead,
  `flow.x` pulled to column centre.
- **Idea 2 — depth-ledge pooling:** `depthBelow` / `ledge`; vertical flow cut, lateral spill from `nY`.
- **Fixed in my own first draft, before gating:** HEAD holds history only where `|flow|` is large. Slowing the
  flow at beads and ledges therefore *dropped* persistence exactly where material should pile up. Added
  `pileHold = max(ledge·0.9, pinch·bead·0.6)` into the gate. Result still clamped < 0.999.
- **A:** untonemapped HDR RGB + semantic alpha; B unwritten. Unchanged.

### `liquid` (+28 / −3)
- **Kept:** all four params; wave equation mixes; capillary noise; spring; main ring; refraction/Fresnel/caustic/tint.
- **Idea 1 — capillary precursor:** inside the ripple loop, `capFront` / `precursor`, faster (×1.45–1.9),
  narrower (95 vs 42), higher-frequency, and decaying 1.6–2.8 by viscosity.
- **Idea 2 — foam drainage:** `slope` / `uphillX` / `uphillY` / `drainW` / `drainedFoam`; semi-Lagrangian
  pull of B from the uphill neighbour, zero before initialisation.
- **A:** raw (height, velocity, foam, coverage). Unchanged.

### `kimi_liquid_glass` (+40 / −4)
- **Kept:** HEAD slot roles; modal drive; lens push; ring; ior 1.31..1.58; `refract()` offset; dispersion;
  Schlick from ior; absorption; interference.
- **Idea 1 — TIR:** `cosI` / `kTir` (Snell discriminant with the file's own `ior`) / `tir`; mixes to an
  inside reflection sampled at `uv - offset·2`.
- **Idea 2 — seed bubbles:** `bp` / `bCell` / `bSeed` / `bRadius` / `bubblePresent` (gated on thickness 0.1–0.3)
  / `bubbleRim` / `bubbleGlint`; rise speed rides the speed slot.
- `color` became `var` to take both ideas. **A:** raw (height, velocity, thickness, coverage). Unchanged.

### `liquid-oil` (+33 / −4)
- **Kept:** all four params; capillary/damping; curl; shear update (still uses `stir`); ring; specular; film formula terms.
- **Idea 1 — displacement wake:** `wakeRim`; acceleration is now `(wakeRim·0.55 − stir)·k` instead of `+stir·k`.
  **This inverts HEAD's pointer response (lift → part).** Stated, not silent — it is the idea.
- **Idea 2 — shear streaks:** `contour` / `streakDir` / four extra C height loads at ±2 and ±4 px /
  `streakH` / `streakAmt` (from |shear|) / `filmHeight` feeding `filmPhase`.
- **A:** raw (height, response, shear, coverage). Unchanged.

### `liquid-mirror` (+42 / −4)
- **Kept:** all four params; spring; ring; ambient; wave equation; `mirrorUV` flip; direct sample; Schlick; specular; steel.
- **Idea 1 — glitter path:** `hash21` added (file had none); `glintCell` / `jitter` / `flick` (12 Hz) /
  `facetRough` (from energy) / `microN` / `glint` with exponent 600 and a sub-cell dot.
- **Idea 2 — energy-roughened reflection:** `roughR` from B and `(1 − smooth)`; 4-tap `reflBlur` replaces
  `reflected.rgb` in both the steel tint and the Fresnel term. `reflected.a` still drives alpha.
- **A:** raw (height, velocity, energy, coverage). Unchanged.

### `ink-marbling` (+42 / −6)
- **Kept:** HEAD slot roles; spring stirrer; waveA/waveB; swirl; drop core/ring injection and dropColor;
  diffusion; thickness retention; existing `palette()` calls. `warpStrength` still drives the wave flow.
- **Idea 1 — Jaffer drop map:** `jaffer` accumulator; per-drop `dropR` / `dropRPrev` (1/60 s step) / `dR2`;
  added to `advectedUV`. **Replaces** HEAD's `flow += dir·ring·warp·1.5`, as the card said.
- **Idea 2 — comb rake:** `rakeCycle` / `rakePass` / `rakeActive` (~34 % of each cycle) / `tineSpacing` /
  `tineDist` / `tineLambda` / `rakeDir` alternating per pass; `flow.y += …·u.zoom_params.x·0.0012·λ/(d+λ)`.
- **A:** raw pigment.rgb + thickness. Unchanged.

### `liquid-displacement` (+51 / −3)
- **Kept:** all four params; divergence; lapV; height-gradient pressure; curl drive; spring; clicks; damping.
- **Idea 1 — vorticity confinement:** eight extra exact C loads (`vLD vLU vRD vRU vLL vRR vDD vUU`);
  `curlC` + four neighbour curls on **stored** velocity `vC`; `eta` / `etaN`; force
  `(etaN.y, −etaN.x)·curlC·turbulence·0.12`, then the existing damping and ±1.1 clamp.
- **Idea 2 — flow-line streaks:** 4-tap line integral along `velocity`, step from the flow-speed slot,
  mixed by `|velocity|·2.5` (max 0.8) before absorption.
- **A:** raw (velocity.xy, height, activity). Unchanged.

---

## Gates

| Gate | Result |
|---|---|
| `wgsl_precommit_gate.py --files` (8) | 8 passed, 0 workgroup errors, 0 extraBuffer violations |
| `verify-naga-wasm --all` | 1420 files — 1380 valid, 40 invalid, **40 known, 0 new** |
| `audit:extrabuffer` | PASS |
| `audit:dead-sliders -- --files …` | PASS, **8 definitions scanned**, 0 dead |
| Slider reads (manual) | all four `zoom_params` read in all 8 |
| `generate_shader_lists.js` + `verify:catalog-counts` | passed (1370) |
| `verify:wgsl-include` | green |
| Jest | 712 pass / 6 fail — same 4 WASM-bridge suites that fail on a clean tree (verified in the retro-glitch batch the same day) |
| `SKIP_WASM_BUILD=1 npm run build` | compiled successfully |
| `shader_definitions/` diff | 5 files × one line: `upgraded-rgba` appended; params asserted equal before/after in the edit script |

**Real-GPU visual QA: not done, required.** No adapter on this VM.
