# gen_hyper_warp — Kimi Optimizer Notes (2026-07-22, batch b13)

## Line Delta
- Before: 173 lines → After: 223 lines (**+50**, within the +50–90 brief target; final range 223–263 ✓)

## Validation
- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen_hyper_warp.wgsl` → **exit 0, 0 warnings** (naga OK, bindgroup compatible)
- `json.load` on `shader_definitions/generative/gen_hyper_warp.json` → **OK** (`updated: true`, `updatedParams` has exactly 4 entries, index 0–3, names/defaults/min/max/step mirror `params`)

## Key Changes Per Technique

### 1. Feedback stabilization (priority 1)
- Extracted a `stabilizeHistory()` helper that replaces the bare `clamp(history * 1.1 - 0.05, 0, 1)`:
  1. **Hard pre-tint ceiling at 1.2** on the sharpened history (luma-echo-warp lesson) — the `* 1.1` gain can never run away before tinting.
  2. **Luma soft-knee** (`smoothstep(0.9, 1.2, luma)`) desaturates overshooting highlights toward grey instead of hard-clipping into flat color.
  3. **0.995 decay** makes the closed feedback loop strictly dissipative.
- Post-mix `clamp(generatedColor, 0, 1)` retained ahead of ACES.
- Added a **cold-start guard**: while history luma ≈ 0 (first frames), the loop seeds from the freshly generated color instead of damping to black.

### 2. Flow-advected history
- The `dataTextureC` sample position is now offset by the `r` warp vector: `flowVec = (r - 0.5) * (2.0 + 6.0 * intensity)`, clamped to texture bounds before `textureLoad`. Feedback smears along the liquid flow instead of sharpening a static frame. History sampling was moved after the `r` computation accordingly.

### 3. Boilerplate killed — real slider wiring
- Deleted `applyGenerativePrimaryControls()` entirely (generic intensity/speed/contrast helper); `writeTexture` now receives the ACES output directly.
- **Intensity (zoom_params.x)** → warp amplitude: `warpAmp = mix(1.0, 3.2, x)` scales the `q` weight feeding the `r` warp layer (default 0.5 ≈ old fixed `q * 2.0`).
- **Speed (zoom_params.y)** → time multiplier: `time = u.config.x * mix(0.05, 0.45, y)` (default 0.5 ≈ old fixed 0.2).
- **Scale (zoom_params.z)** → palette frequency `mix(0.6, 1.6, z)` + hue offset `mix(0.0, 0.33, z)` between the two palettes.
- **Detail (zoom_params.w)** → feedback mix `mix(0.85, 0.98, w)` (was fixed 0.95; default 0.5 ≈ 0.915).
- JSON ids/names/defaults/min/max/step untouched (saved-preset contract).

### 4. Secondary additions (soul preserved)
- Fuller audio reactivity: `mid` (plasmaBuffer[1]) adds slow hue drift, `treble` (plasmaBuffer[2]) nudges the second warp layer; bass now also gently pulses the radial burst.
- Gentle vignette before ACES to focus the radial-burst composition.
- Triple domain-warp structure, octave counts (3/4/5), warp weights, radial burst, and both palettes preserved exactly.

## Contract Compliance
- Canonical 13-binding layout unchanged (0–12; no binding 13 declared — not used).
- `@workgroup_size(16, 16, 1)` kept.
- `writeTexture`, `writeDepthTexture`, `dataTextureA` all written every frame.
- All sampler reads use `textureSampleLevel(..., 0.0)`; storage reads use `textureLoad`.
- No new/renumbered bindings; no WGSL reserved identifiers (checked: no `target`, etc.).

## QA Flags
- Default slider values (all 0.5) were chosen to land close to the old fixed constants (warpAmp 2.1 vs old 2.0, time scale 0.25 vs 0.2, feedbackMix 0.915 vs 0.95) so the default look is near-identical; extremes are new expressive territory.
- `histPx` uses `vec2<i32>(flowVec)` truncation — fine for a sub-pixel smear offset.
- **No-GPU caveat:** the headless Cloud VM has no WebGPU adapter, so visual QA (feedback blowout behavior, flow-smear aesthetics, slider feel) is **deferred to real hardware**. Validation here was static only: naga compile, bindgroup compatibility, workgroup convention, and JSON parse.
