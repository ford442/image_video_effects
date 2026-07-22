# coral-growth — Swarm Notes (Kimi, b13)

**Date:** 2026-07-22
**Brief:** `swarm-tasks/kimi-generative-briefs-2026-07-22-b13/coral-growth.md`
**Role:** Algorithmist

## Line Delta

- Before: 175 lines
- After: 241 lines
- Delta: **+66** (target +50–90 ✅, within 225–265 range ✅)

## Key Changes Per Technique

### 1. Second-order sub-branching (mids-driven)
- Inside the existing first-order branch block (`proj > currentLen * 0.5`), added a
  second branching level ("twigs") anchored at the first-order sub-branch point.
- Probability gate: `twigGate < bushChance` where
  `bushChance = clamp(mids * 1.15 + branchComplexity * 0.25, 0.0, 0.9)` — mids
  (`plasmaBuffer[0].y`) drive bush-out as required, with the Complexity slider raising the cap.
- Twig geometry: angle offset from parent (`angle + 0.8 - (0.5 + twigGate) * 1.1`),
  length `subLen * 0.55 * (0.6 + mids * 0.6) * (0.7 + growthSpeed * 0.4)`, tapered
  width `branchWidth * 0.45`, composited as `max(branch, twig * 0.55)`.

### 2. Spectral tip lighting (per-bin)
- New helper `spectralBandEnergy(branchIndex)` reads `plasmaBuffer[1 + (bi % 8)]`
  (.x * 0.6 + .z * 0.8, clamped to 1.5) so each branch index lights to its own FFT band.
- Main tip term changed from `* treble * 2.0` to `* (treble * 0.6 + bandEnergy * 1.4)`
  — global treble kept as a floor, per-band energy dominates.
- Twig tips also glow on the branch's own band (`* bandEnergy * 0.9`, tighter falloff 260.0).
- Band energy nudges branch hue (`+ bandEnergy * 0.05`) so different bands bloom different colors.

### 3. Luminous growth residue
- **Sim-state contract preserved verbatim:** `bass_env(prev.r, rawBass, 0.8, 0.15)` untouched;
  `dataTextureA` store layout unchanged: `(bass, glow, tipGlow, finalAlpha)` —
  .r = bass envelope, .a = trail age. Not converted to color storage.
- New trail term after temporal accumulation: `trailRaw = min(prev.rgb * 0.9, vec3(1.2))`
  (~0.9 decay, clamped pre-tint at 1.2), tinted by `trailTint` (Color Shift rotates it)
  and scaled by `(0.3 + growthSpeed * 0.25)` so faster growth leaves stronger residue.

### 4. Slider wiring (existing ids/defaults kept — preset contract intact)
- `zoom_params.x` Cell Density: grid frequency (unchanged) **+ branch thickness**
  (`branchWidth` scaled by `1.0 + x * 0.35`).
- `zoom_params.y` Branch Complexity: first-order branch count (unchanged) **+ bush-out cap**.
- `zoom_params.z` Growth Speed: growth rate (unchanged) **+ twig length + residue persistence**.
- `zoom_params.w` Color Shift: hue offset (unchanged) **+ trail tint rotation**.

## Contract Compliance

- Canonical 13-binding layout preserved; no bindings added/renumbered; no binding 13.
- `@workgroup_size(16, 16, 1)` kept.
- `writeTexture`, `writeDepthTexture`, `dataTextureA` written every frame.
- `textureSampleLevel(..., 0.0)` for sampler reads; no storage `textureLoad` added.
- No WGSL reserved identifiers used (checked: no `target`, etc.).
- `extraBuffer` untouched.
- Core algorithm (cell grid + hashed branch segments + gravity well + shockwave +
  luma spawn + ACES) preserved — upgrade, not rewrite.

## QA

- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/coral-growth.wgsl`
  → **PASS, exit 0, 0 warnings** (naga OK, bindgroup compatible).
- `shader_definitions/generative/coral-growth.json` → valid JSON; added exactly 4
  `updatedParams` entries (index 0–3, same names/defaults/min/max, step 0.01) and
  `"updated": true`. Nothing else changed.

## QA Flags / Caveats

- **No-GPU caveat:** this VM has no WebGPU adapter, so visual QA is deferred to real
  hardware. Validation here is naga + bindgroup gate only.
- `spectralBandEnergy` indexes `plasmaBuffer[1..8]` — assumes engine FFT bins occupy
  those slots per the brief; runtime storage reads of unwritten bins yield 0.0 (safe,
  tips just fall back to the treble floor).
- The `mouse` var (`zoom_config.yz * 2.0 - 1.0`) was already unused pre-upgrade; left
  as-is to keep the diff minimal (naga raises no warning).
