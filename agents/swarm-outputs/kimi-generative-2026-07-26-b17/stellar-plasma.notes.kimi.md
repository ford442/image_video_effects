# Batch 17 Notes — stellar-plasma (Visualist)

## Line delta
- **206 → 264 lines** (+58, within the +50..+90 / 256–296 target window).

## Changes per technique

### 1. Lying comments fixed (docs-only, code unchanged)
- `config`: was `x=Time, y=AudioLow, z=AudioMid, w=AudioHigh` → corrected to
  `x=Time, y=rippleCount, z=resW, w=resH` (verified engine truth, UniformBuffer.ts).
- `zoom_config`: was `x=MouseX, y=MouseY, z/w=unused` → corrected to
  `x=time, y=MouseX, z=MouseY, w=MouseDown`.
- `zoom_params` comment already correct; names aligned to JSON
  (`x=HueShift, y=FlowSpeed, z=ZoomScale, w=MouseGravity`).

### 2. Real chromatic aberration
- Removed the fake additive tint (`color.r + caStr`, `color.b - caStr*0.5`).
- Added 3 true spectral samples of the final fbm field: `fR = fbm(q_pos + 4.0*r + caOff)`,
  `f` (center, reused), `fB = fbm(q_pos + 4.0*r - caOff)`. Offset direction is the
  normalized warp coord (`caDir`), magnitude `0.004 * (1.0 + audioLow)` — sub-pixel,
  bass-reactive. The domain-warp vectors `q`/`r` are reused verbatim, so the cost is
  only one extra fbm loop per fringe channel.
- The cubic glow curve now runs per-channel over `vec3(fR, f, fB)`, giving true
  prismatic fringing on nebula filament highlights.

### 3. IQ cosine palette
- Added `iqPalette(t, huePhase) = a + b*cos(2π*(c*t+d))` with coefficients tuned so
  `huePhase = 0` reproduces the legacy ramp (cyan → magenta → deep blue → gold).
- Replaced the 4 hardcoded base colors with 4 palette taps at `t = 0.05 / 0.35 / 0.55 / 0.90`
  mixed with the exact legacy layer factors (`f²·4`, `|q|`, `|r.x|`), preserving the look.
- Legacy audio color tilts kept as brightness-weighted channel mixes.
- `hueShift()` retained, now driven only by time drift + audio rotation (slider hue
  moved into palette phase per brief).

### 4. Spring-damper mouse gravity
- extraBuffer slots (safe zone, named consts): `[133]=sm_pos.x, [134]=sm_pos.y,
  [135]=sm_vel.x, [136]=sm_vel.y`.
- Only invocation (0,0) integrates (stiffness 90, damping 12, dt 0.016,
  exponential velocity decay) to avoid races; all invocations read the smoothed pos.
- Gravity well `exp(-dist·3) * mouse_influence` now targets the smoothed cursor —
  organic trailing motion instead of rigid 1:1 tracking.

### 5. Domain-warp preservation
- Nested double warp `q → r → f` kept **verbatim**, including `4.0 * q`, `4.0 * r`,
  offsets `(1.7, 9.2)` / `(8.3, 2.8)`, and time factors `0.2 / 0.15 / 0.126`.
- Early-exit, LOD octaves, temporal feedback (dataTextureC→A), ACES, semantic alpha
  all preserved.

## Slider wiring (saved-preset contract unchanged)
| Slider | Mapping | Drives |
|---|---|---|
| Hue Shift (0) | `zoom_params.x` | IQ palette phase (full spectral rotation at 0→1) |
| Flow Speed (0.2) | `zoom_params.y` | time multiplier `mix(0.5, 2.0, y)` (+ audio reactivity) |
| Zoom / Scale (0.3) | `zoom_params.z` | nebula zoom `mix(1.0, 4.0, z)` into `q_pos` |
| Mouse Gravity (0.5) | `zoom_params.w` | gravity-well strength on spring-smoothed cursor |

All four fields read in WGSL — dead-slider audit clean. JSON params/ids/defaults/
min/max/step/mapping unchanged; `updatedParams[0..3]` added per brief (written verbatim).

## Binding compliance
- Canonical 13-binding layout (0–12) untouched, no binding 13 (not previously used).
- `@workgroup_size(16, 16, 1)` preserved.
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame (both the
  early-exit and main paths).
- `textureLoad` for storage reads (dataTextureC); no sampler reads needed.
- extraBuffer writes confined to `[133..136]` (named u32 consts, statically resolved
  by the auditor). No reads/writes in reserved `[0..4]` or FFT `[5..132]` zones.
- No WGSL reserved keywords used as identifiers; no ripple loops (n/a — `min(u32(u.config.y), 50u)` guard not applicable).

## QA flags
- `wgsl_precommit_gate.py`: **PASS** (0 warnings, bindgroup compatible).
  Note: `naga` binary unavailable in this VM — naga step skipped by the gate itself
  (environmental, not a shader issue); bindgroup + workgroup checks ran green.
- `audit_extrabuffer.py`: **AUDIT PASS** (0 new violations, 0 dynamic-index writes).
- `audit_dead_sliders.py --files stellar-plasma`: **AUDIT PASS** (0 dead sliders).
- Not visually verifiable here (headless VM, no GPU adapter); algorithm/constants
  preserved so legacy look at default sliders should match modulo palette math.
