# gravito-phononic-accretion — Swarm Notes (Kimi, b14)

**Date:** 2026-07-22
**Brief:** `swarm-tasks/kimi-generative-briefs-2026-07-22-b14/gravito-phononic-accretion.md`
**Role:** Optimizer

## Line Delta

- Before: 179 lines
- After: 248 lines
- Delta: **+69** (target +50–90 ✅, within 229–269 range ✅)

## Key Changes Per Technique

### 1. Honest 'Lensing Strength' (p2) — true gravitational lensing
- New `lens_pull()` helper: deflection toward each accretor =
  `dir * clamp(p2 * mass / dist^2 * LENS_AMP, 0.0, LENS_MAX)`
  (`LENS_AMP = 0.0035`, `LENS_MAX = 0.05`).
- The three pulls (g1, g2, mouse rogue body) accumulate into `luv`, clamped to
  [0,1], and **all** `dataTextureC` density reads (center tap, 6 hex taps,
  flow-advection sample) now sample at the lensed uv — mass visibly warps the
  background field before density estimation.
- Mouse pull is branchless-honest too: it scales with `mass3`, which already
  zeroes on mouse-up, so the lensing warp vanishes with the rogue body.
- Removed the old dishonest wiring: tone gain is now the constant
  `acesToneMap((col + bloom) * TONE_GAIN)` — `p2` no longer touches tone gain.

### 2. Diffusion-controlled persistence (p3)
- `let persist = mix(0.90, 0.99, p3);` then
  `density = mix(flowed * persist + density * (1.0 - persist), density, 0.3) + …`.
- Material Diffusion now drives both the hex-kernel spread (`h_uv`, unchanged)
  and advected-trail longevity — one slider, two coupled meanings as briefed.

### 3. Treble relativistic jet (~0.5 s fade)
- Persistent envelope in the sanctioned `extraBuffer[133..255]` window:
  `[133]` = previous treble, `[134]` = jet envelope; single-thread write
  (`gid == (0,0)`), same convention as other upgraded shaders (e.g.
  holographic-crystal bass env).
- Transient detection: `max(treble - prevTreble, 0.0) * JET_KICK`, decay
  `prevJetEnv * 0.88` per frame (0.88³⁰ ≈ 0.02 @ 60 fps ≈ 0.5 s fade).
- Beam: thin vertical glow from the primary accretor g1, perpendicular to the
  orbital plane — `fast_exp(-|uv.x-g1.x| * 220) * fast_exp(-|uv.y-g1.y| * 3.2) * jetEnv`,
  added to bloom as blue-white (`JET_COLOR * JET_GAIN`), plus small
  contributions to `temp` (+0.25) and `alpha` (+0.35) so the jet heats and
  composites consistently.

### 4. Slider wiring (all 4, via existing zoom_params mapping)
- p1 Accretion Speed → mass1/mass2 boost + flow-advection speed (unchanged, already real).
- p2 Lensing Strength → **real uv deflection** (was tone gain).
- p3 Material Diffusion → kernel spread **and** trail persistence (was spread only).
- p4 Mouse Gravity Power → rogue-body mass multiplier (unchanged, already real).
- JSON: `updatedParams` (index 0–3, same names/defaults/min/max/step as
  `params`) + `"updated": true` added; nothing else in the JSON touched.

## Preserved Optimizations / Contracts (verified)

- 7-tap hex kernel loop (`for i in 1..7`, HEX_TAPS const) untouched structurally.
- `fast_exp` clamp (`exp(clamp(x, -80.0, 0.0))`) unchanged; jet falloffs reuse it.
- Branchless mouse-mass zeroing (`mass3 * mouseDown`) preserved; new lensing pull
  for the mouse is also branchless via mass3.
- `dataTextureA` = SIM STATE `(density, temp, shock, 0.0)` written every frame,
  no clamping of the stored state.
- Output remains PREMULTIPLIED ALPHA `vec4(tone * alpha, alpha)`; ACES tonemap
  happens **before** premultiply (as before) — no tonemap added after.
- `min(u32(u.config.y), 50u)` ripples guard kept.
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`,
  `textureSampleLevel(..., 0.0)` for all sampler reads; no bindings
  added/renumbered; no reserved WGSL identifiers.

## QA / Validation

- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/gravito-phononic-accretion.wgsl`
  → **PASS, exit 0, 0 warnings** (naga OK, bindgroup compatible).
- `json.load(...)` on the definition JSON → **OK** (`updated: true`, 4 updatedParams).
- QA flags:
  - Jet decay is frame-rate based (0.88/frame assumes ~60 fps), matching the
    codebase's bass-envelope convention; on high-refresh displays the fade is
    shorter than 0.5 s. Cosmetic only.
  - Lensing adds one ALU-light helper per pixel (3 `lens_pull` calls, no extra
    texture taps) — the 7-tap kernel cost is unchanged.
- **No-GPU caveat:** this Cloud VM has no WebGPU adapter, so visual QA
  (lensing warp look, jet brightness/envelope feel, slider sweeps) is deferred
  to real hardware. Validation here is naga + gate + bindgroup compatibility.
