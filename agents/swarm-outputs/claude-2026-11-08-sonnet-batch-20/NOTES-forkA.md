# sonnet/batch-20 — Fork A notes

Files edited (uncommitted, per instructions): `public/shaders/gen_grokcf_interference.wgsl`, `public/shaders/gen-void-harmonic-cymatic-resonator.wgsl`,
`public/shaders/gen-stellar-acoustic-resonance-manifold.wgsl`, and their three `shader_definitions/generative/*.json` (description / feedbackPacking / one features tag only — `params` byte-exact).
Test tool added: `agents/minirender_fa.mjs` (gitignored) = minirender_img + `RIP=x,y,t0` click injection + `FFT=v[,..]` extraBuffer bins.
All stats: minirender 192px / 24 frames / t_end 2.0, JSON defaults passed explicitly, audio 0.3/0.2/0.1, black source (same args as the baselines).
PNGs: `agents/swarm-outputs/claude-2026-11-08-sonnet-batch-20/forkA/` (`*_before.png`, `*_after.png` are rgb | over-white | alpha).
Gates: `wgsl_precommit_gate.py --files` on all three → naga OK, bindgroup OK, 0 extraBuffer violations, 0 pasted headers; Tint (`verr`) null on every render; all four sliders read in each file.

## gen-grokcf-interference — `gen_grokcf_interference.wgsl`
| | meanL | stdL | meanA |
|---|---|---|---|
| before (black src) | 0.027 | 0.052 | 0.141 |
| after (black src) | 0.134 | 0.134 | 0.362 |
Over a photo (`grokcf_photo_before/after.png`): before = barely visible ring; after = clear hue-coded disc with the photo still visible between nodes.

**KEPT VERBATIM:** J0–J3, 6-mode table + modeCount gates, slider roles, mouse re-centring, Dirichlet rim, HEAD Ideas 1–4 (tint, Lambert, antinode disks, radial beat), hue map, ACES on display.
**A PACKING (changed, stated):** A = (u_total raw, **leaky |u| sand energy** (was write-only `r`), φ/2π, blendAlpha). C is read only for `.r` (damped u), `.g` (sand), `.a` (valid) — no other reader of A.g existed.
**Rescues (floor-level bugs found by reading, each measured):**
1. `fftModeWeight` read `plasmaBuffer[1..8]`, which the engine never uploads (audioDepth.ts:62-70) → constant 0.6, FFT selection dead. Now reads real bins `extraBuffer[5+i]` (fftBand, L91–101), floor 0.6→0.85. Verified with `FFT=` injection (figure changes with bins).
2. Clicks gated on `rp.w > 0.001` (padding, always 0) → dead. Gate removed (L249–251). Verified with `RIP=` injection.
3. Overlay brightness `|u|·1.5` → `sqrt(2.2|u|)` (L310): silent drum covered ~0.2 alpha.
4. uv not aspect-corrected → ellipse on non-square canvas (L176–179, hit point uses the same frame). NOT verified on a 16:9 render (minirender is square); derivation only. One line to revert (`frameScale`).
**Ideas added:**
- Idea 5 sand on the plate (L290–299, composite L≈330 `sandDust`, A.g write at the final textureStore): leaky average (0.03/frame) of |u|, sand = exp(−E·(8+1.2·nodeSharp)), static 2-texel grain. Node-sharpness slider sets band width. Converged 6 s render: sand on the clamped rim and on stationary quiet zones; instantaneous gold node lines still sweep. Inherited C: g clamped [0,2], converges ≈1.5 s.
- Idea 6 modal strike response (L245–275): Σ_k S_k(hit)·S_k(p)·e^(−(0.55+0.22α_k)·age)·cos(1.8α_k·age) over active modes; HEAD's contact packet kept as the transient. Max 8 simultaneous strikes. Centre click → concentric (0,n) rings only; off-centre → azimuthal structure (see `grokcf_strike_centre/offcentre_age0.5.png`).
**Formulas:** none from §12.2 (tactic 2/3/6).
**Not verified:** real-GPU look; strike amplitude 0.55 and sand tuning judged on SwiftShader at 192 px; thumbnail harness inherits previous shader's C (sand haze lasts ~1.5 s).
**Noticed, not changed:** the 0.72 persistence mix is frame-rate dependent (dim at 24 fps, fine at 60).

## gen-void-harmonic-cymatic-resonator
| | meanL | stdL | meanA |
|---|---|---|---|
| before | 0.593 | 0.204 | 0.521 |
| after | 0.521 | 0.197 | 0.499 |

**KEPT VERBATIM:** standingWave/splitModes, 5-octave `disp`, `|p|−thickness` SDF, 4 slider roles, nodal/seam/antinode/throat integrals, fresnel, fog, ACES display RGBA in A, 6 % history. A packing unchanged.
**Rescues:**
1. Camera basis: `cu=(−1,0,0)`, texture-down=+uv.y ⇒ screen-right = world −x and screen-up = world −y; `mouse_pos=(mx,−my)` assumes the opposite, so the mouse warp sat at the point-mirror of the cursor and the key light lit from below. `rd` now built from (−uv.x·cu − uv.y·cv) (L152). Derived, not measured — a quadrant-diff test was inconclusive because the warp is global. Net effect: image rotates 180°.
2. Exposure: the nodal sheets (the identity) were buried. Isolated terms at default: seam haze meanL 0.38, nodal 0.21, shell shading 0.20, surfaceGlow 0.08. Seam weight 0.045→0.018 (L207), shell shading ×0.65 (L225), nodal weight 0.075→0.105 (L198). These three constants are the look change besides the flip; revert individually if unwanted. The shell base palette is still pastel (HEAD).
**Ideas added:**
- Idea 5 radial breathing mode (L87–97): p += (0.22+0.95·bass)·sinc(1.4977·freq·r)·cos(3t) (rigid-sphere first radial eigenmode, antinode at the wall); wall radius flexes by 0.06·breath. Measured: bass 0.9 vs bass 0 → concentric shell structure appears (`resonator_breath_off_on_diff_bass0_vs_0.9.png`); at bass 0 it is a modest shift.
- Idea 6 knife-edge schlieren (L178–206, L234–236): sign of the pressure slope between consecutive nodal-integral steps picks cyan (falling) vs coral (rising); colour is near-weighted (exp(−0.15j)) so the nearest sheet decides (plain averaging gave white). Amount is HEAD's sum. Isolated it is clearly two-tone (`resonator_schlieren_isolated_vs_composite.png`); in the composite it survives as blue/coral tinted filaments over the pastel base — subtle, not dramatic.
**Formulas:** none from §12.2.
**Not verified:** real-GPU look; mouse orientation visually; default (freq 1) frame is still mostly a few large soft sheets — the cells only appear at freq ≳2 (HEAD behaviour).

## gen-stellar-acoustic-resonance-manifold
| | meanL | stdL | meanA |
|---|---|---|---|
| before | 0.448 | 0.237 | 0.361 |
| after | 0.427 | 0.218 | 0.350 |

**KEPT VERBATIM:** stellarField cell repeat/fbm body, pMode/gMode, phaseSlip seams, mouse lens, compression-antinode heating, coronal arcs, 4 slider roles, ACES display RGBA + 5 % history. A packing unchanged. No rescue needed (compiles, visible, sliders live, audio from plasmaBuffer[0]).
**Ideas added (comment labels in the file):**
- Idea 5 limb darkening (L206–210): ×(1 − (0.35,0.55,0.80)(1−μ)), μ = n·(−rd), on the surface emission only.
- Idea 6 p/g-mode Dopplergram: `stellarField().w` now returns the exact d/dt of acousticPressure (L113–117; `.w` radialDistance was unread); tint `(1−0.55v, 1−0.15|v|, 1+1.1v)` with v = velocity·(0.35+0.65μ) (line-of-sight projection) (L211–217).
- Idea 7 stochastic excitation (L106–111): per-cell envelope 0.45+1.2·(½+½sin(0.45t+7·cellPhase))² (mean ≈ 0.9) scales pressure → emboss, heating, velocity together.
**Formulas:** none from §12.2. Variants rendered separately (`stellar_variants_head_env_limb_dopp_all.png`): each idea individually visible.
**Not verified:** real-GPU look; tiny distant stars read as speckle at 192 px (rings at full res).

## Batch notes for the coordinator
- Fork A uses no §12.2 row. No spring/ripple/IQ overlay on any file; the only pointer-related change is the dead-click fix on the drum.
- JSON: grokcf gained `mouse-driven` (the drum is pointer-centred and now strikable), `feedbackPacking` text updated, three descriptions got one added sentence each — if the search-index test recomputes embeddings, these three descriptions are the changed inputs.
- `reports/*` were dirtied by gate runs (mine and others'); not touched deliberately.
