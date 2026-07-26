# gen_fluffy_raincloud — Batch 17 Upgrade Notes (Kimi / Algorithmist)

## Line delta
- **Before:** 215 lines → **After:** 286 lines (**+71**, within target 265–305)

## Changes per technique

### 1. Storm gusts on click (ripples → sim velocity)
- Added ripple loop guarded by `min(u32(u.config.y), 50u)`.
- Each click (`u.ripples[ci]`, age window `0..4.0s`) injects a radial Gaussian
  velocity impulse (`exp(-d²·260) · exp(-age·1.6) · 0.028`) into the sim state
  velocity before the vorticity-confinement pass, so gusts get naturally
  swirled into eddies by the existing confinement.
- Also accumulates `gustDensity` which feeds small density/moisture bumps
  (`+0.05` / `+0.04`) so gusts condense a puff of cloud at the click point.

### 2. Per-bin rain audio
- `midBins = avg(plasmaBuffer[3..5].x)` micro-modulates rain intensity:
  `rainAudio = saturate(rainIntensity * (1 + (midBins - 0.5) * 0.35))`,
  used in the rain-core gate and the above-cloud sampling offset.
- `trebleBins = avg(plasmaBuffer[6..8].x)` raises the rain-sheet streak
  threshold: `streakLo = clamp(0.42 + trebleBins * 0.22, 0.42, 0.78)`
  replaces the hardcoded 0.42 — hi-hats now read as rain texture breakup.
- Existing broadband `bass` (confinement boost, pulse, lightning gate) untouched.

### 3. Long-session precision fix
- Added `noiseTime = mod(time, 3600.0)`; all procedural noise coordinates
  (cloud fbm, curl-noise field + stream-function time, rain streak noise,
  lightning gate sin + shape fbm) now use `noiseTime`. Raw `time` is kept
  only for ripple age and the cold-start check (both need absolute time).

### 4. Spring-damped mouse gust center (extraBuffer[133..136])
- `[133..134]` = eased gust center (uv), `[135..136]` = spring velocity.
- Damped spring (`springK=34.0`, `springDamp=9.0`, dt=1/60) integrated only by
  invocation (0,0); every pixel reads the eased value. Cold start
  (`time < 0.1`) snaps to the raw mouse to avoid a startup swoop.
- The eased center drives `mouseMask` (buoyant updraft + horizontal shear),
  replacing the raw `u.zoom_config.yz` read.

## Slider wiring (contract preserved — same ids/names/defaults/min/max/step)
- `param1` Coverage (0.6) → `zoom_params.x`: cloud threshold `0.48 - coverage*0.22`, density blend rate, curl field scale `mix(1.5, 4.8, coverage)`.
- `param2` Turbulence (0.65) → `zoom_params.y`: curl forcing gain `0.0015 + turb*0.0095`, vorticity confinement `0.001 + turb*0.014`.
- `param3` Rain (0.55) → `zoom_params.z`: base rain intensity (feeds `rainAudio` + moisture generation).
- `param4` Wind (0.5) → `zoom_params.w`: `windX = (w*2-1)*0.014` — horizontal drift of cloud fbm, velocity forcing, rain streak slant, above-cloud sampling.
- All 4 sliders drive real algorithm constants (no generic boilerplate remap needed; wiring was already shader-specific and kept).

## Binding compliance
- Canonical 13-binding layout preserved verbatim (0–12, no renumber, no binding 13).
- `@workgroup_size(16, 16, 1)` preserved.
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` (and `dataTextureB`) every frame.
- `textureSampleLevel(..., 0.0)` for sampler reads; `textureLoad` for storage reads.
- **Channel packing preserved VERBATIM:** dataTextureA = `(density, velocity.x, velocity.y, moisture)`, dataTextureB = `(rain, omega*0.5+0.5, silverEdge, lightning)`; sim state stays raw (tonemap applied only to `writeTexture`).
- extraBuffer writes confined to `[133..136]` (safe zone); no writes to [0..132]. No reserved WGSL keywords used as identifiers.

## QA flags
- `wgsl_precommit_gate.py`: **PASS** (0 warnings; naga binary unavailable in this VM — bindgroup + workgroup checks ran clean).
- `audit_extrabuffer.py`: **AUDIT PASS** (0 violations, 0 dynamic writes).
- `audit_dead_sliders.py`: **AUDIT PASS** (0 dead sliders).
- Caveat: headless VM has no GPU adapter — visual/audio behavior verified by code inspection + static gates only, not by live render.
- Spring state race (single-writer at (0,0), read by all) matches the established pattern used by supernova-core et al.; one-frame convergence lag is intentional.
