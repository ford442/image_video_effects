# chromatic-ghost-tunnel — Batch 17 Upgrade Notes (Kimi)

**Date:** 2026-07-26
**Line delta:** 202 → 272 (+70, target 252–292 ✅)

## Changes per technique

### 1. Per-bin ring voices
- Inside the ghost-echo ring loop, ring `i` now reads
  `let binVoice = plasmaBuffer[1 + (i % 8)].x;` (verbatim pattern from brief).
- `binVoice` drives: `voiceBoost = 1.0 + binVoice * 1.2` (ring brightness),
  ring width widening `(1.0 + binVoice * 0.6)`, additive chromatic R/G/B
  offsets (`binVoice * 0.02` each), and a hue shift `binVoice * 0.15`.
- Global bands (bass/mids/treble) are retained — the bin voice augments,
  does not replace.

### 2. Click tunnel shockwaves
- New loop over `u.ripples[]` guarded by `min(u32(u.config.y), 50u)`.
- Each click (valid for `age in (0, 4)`) computes its own tunnel depth
  `clickZ = 1/(clickDist + 0.01)` and emits a wavefront racing down the
  z-axis at `waveZ = clickZ + age * 4.0`.
- Brightness band: `exp(-|z - waveZ| * 0.45) * exp(-age * 1.2)` → added via
  an OkLab-mixed cool↔warm `shockCol` scaled by `(0.35 + treble * 0.3)`.
- Chromatic fringe: a red/blue split (`±shockChroma * 0.10`) trailing the
  wavefront at `waveZ * 0.85`; shockwave also feeds `alpha`.

### 3. Inertial flight
- Critically damped spring-damper on the mouse tunnel offset.
- Persistent state: `extraBuffer[133]`/pos.x, `[134]`/pos.y, `[135]`/vel.x,
  `[136]`/vel.y — all in the [133..255] safe zone, static literal indices.
- `springOmega = 7.0`, damping term `2·ω·vel` (ζ = 1, critical), fixed
  `dt = 0.016`. Only invocation (0,0) writes state; all threads read.
- `mouseOffset` is now the spring position instead of raw mouse, so tunnel
  steering carries momentum.

### 4. Slider wiring (zoom_params, unchanged contract)
Existing JSON param ids/names/defaults/min/max/step preserved verbatim;
each slider already drove a real constant of this shader's algorithm and
still does (no re-defaulting, no renaming):
- `zoom_params.x` → Tunnel Speed → `tunnelSpeed = mix(0.2, 2.0, x)` (z travel rate)
- `zoom_params.y` → Spiral Twist → `spiralTwist = mix(0.0, 3.0, y)` (twist per depth)
- `zoom_params.z` → Ghost Echo Count → `echoCount = mix(2.0, 8.0, z)` (ring count)
- `zoom_params.w` → Flash Intensity → `flashIntensity = mix(0.0, 1.0, w)` (treble strobe)
`updatedParams` indices 0–3 present in the JSON (written verbatim from brief).

## Binding compliance
- Canonical 13-binding compute layout preserved exactly (0–12, no renumber,
  no additions; binding 13 historyTexture not declared — was not used).
- `@workgroup_size(16, 16, 1)` unchanged.
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame.
- `textureSampleLevel(..., 0.0)` for sampler reads; no storage texture reads.
- No WGSL reserved keywords as identifiers.
- extraBuffer: only literal writes at [133..136]; nothing in [0..4] reserved
  or [5..132] FFT zone. 0 dynamic-index writes.
- Signature chain preserved verbatim and in order: OkLab mix + blackbody
  temperature palette → `hue_preserve_clamp(col, 5.0)` → `aces` → IGN dither
  → gamma (`pow(col, 1/2.2)`) output.

## QA flags
- `wgsl_precommit_gate.py`: PASS, 0 warnings (naga binary unavailable in
  this VM — bindgroup + workgroup checks ran; pre-existing env limitation,
  same as baseline).
- `audit_extrabuffer.py`: AUDIT PASS (0 out-of-range, 0 dynamic writes).
- `audit_dead_sliders.py`: AUDIT PASS (all 4 sliders read their mapped fields).
- JSON parses cleanly (`json.load` OK).
- Visual/GPU verification not possible in headless VM (no WebGPU adapter);
  validated statically via gates + naga-free bindgroup checks.
