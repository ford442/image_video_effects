# gen_quantum_foam — Batch 18 Upgrade Notes (Kimi / Visualist)

## Line delta
- Before: 216 lines → After: 287 lines (+71; target 266–306 ✅)

## Changes per technique

### 1. Fake audio fix (priority 1)
- Removed `audioPulse = u.zoom_config.z` (mouse-Y proxy) and its comment.
- Bass: `plasmaBuffer[0].x` (clamped 0..2) now drives:
  - `pairRate = 1.0 + bass * 1.5` — scales `time * evolutionSpeed` fed into `quantumFoam()` (faster virtual pair production on bass hits), used in both the base pass and the glow accumulation pass.
  - `burst = 1.0 + bass * 1.2` — multiplicative vacuum burst on `generatedColor`.
  - Glow term additionally scaled by `(0.8 + bass * 0.4)`.
- Per-bin FFT: screen column `uv.x` selects bin 0..7 → `plasmaBuffer[1u + binPos].x`; modulates web density via `localDensity = clamp(webDensity * (0.45 + fftLocal * 1.1), 0, 1)` so the entanglement web thickens spatially with its frequency band.

### 2. Entanglement strikes (click shockwaves)
- Loop over `u.ripples[ri]`, guarded by `min(u32(u.config.y), 50u)`.
- Each strike (xy = position, z = start time) emits an expanding ring `exp(-((dist - age*0.55)*14)^2)` with `exp(-age*1.4)` decay, valid for age in (0, 5).
- `shock` both boosts web density (`strikeDensity = clamp(localDensity + shock*0.5, 0, 1)`) and adds a cool-blue strike flash `(0.6, 0.8, 1.2) * shock * 0.6`.

### 3. Spring-dampered mouse warp (extraBuffer safe zone)
- Slots 133–137 only: WARP_POS_X/Y, WARP_VEL_X/Y, WARP_TIME ([0..4] reserved, [5..132] engine FFT untouched).
- Invocation (0,0) integrates a spring-damper (stiffness 42, damping 9, dt clamped to 0.1, cold-start snap guard for time < 0.1); all pixels read the eased `warpPos`.
- Polarity offset `(warpPos - 0.5) * (0.15 + mouseDown * 0.25)` bends the domain (`warpedUV`) used by foam, web, and glow — vacuum polarity eases instead of snapping; mouse-down deepens the warp.

### 4. Dead code / dataTextureA cleanup
- Deleted dead `n` variable in `noise()`.
- dataTextureA now stores the **clean display color** (`finalColor, finalAlpha`) instead of the unread biased `finalColor*0.5+0.5`.
- Wired `dataTextureC` feedback: `textureLoad(dataTextureC, coordI, 0)` mixed into `generatedColor` at 0.08 (≤ 0.1 bound) for temporal coherence before the input blend.

### 5. Slider wiring (4 params, preset contract preserved)
- Same ids/names/defaults/min/max/step/mappings; `updatedParams` index 0–3 added in JSON.
- `zoom_params.x` Foam Scale → `foamScale = 3.0 + x*9.0` (fbm domain scale of quantumFoam).
- `zoom_params.y` Web Density → base density feeding `localDensity` → `strikeDensity` → `entanglementWeb()` connection count.
- `zoom_params.z` Glow Intensity → `glowGain = z*1.4` scaling volumetric glow accumulation.
- `zoom_params.w` Evolution Speed → `evolutionSpeed = 0.2 + w*1.3` time rate for foam + web.

## Preserved verbatim
- `quantumFoam()`, `entanglementWeb()`, `acesToneMap()` — untouched (fbm correlation math = visual identity).
- Canonical 13-binding layout (0–12, no binding 13), `@workgroup_size(16, 16, 1)`.
- Writes every frame to `writeTexture`, `writeDepthTexture`, `dataTextureA`.
- `textureSampleLevel(..., 0.0)` for sampler reads; `textureLoad` for storage reads.

## Binding compliance
- extraBuffer writes: indices 133–137 only (safe zone [133..255]).
- plasmaBuffer: read-only, bins 0–8 (within engine range).
- Ripple loop guarded `min(u32(u.config.y), 50u)`.
- No WGSL reserved keywords as identifiers.

## Gate / audit results (all green)
- `wgsl_precommit_gate.py`: Passed 1/1, 0 warnings, 0 extraBuffer violations (naga unavailable in VM — skipped by gate, not a failure).
- `audit_extrabuffer.py`: AUDIT PASS (0 violations, 0 out-of-range, 0 unresolved dynamic).
- `audit_dead_sliders.py`: AUDIT PASS (0 dead sliders).

## QA flags
- `PHI` constant retained (unused but pre-existing in header block; harmless const, gate-clean).
- GPU/WebGPU not exercisable in headless VM — validated via gates/audits only.
- dataTextureC feedback assumes engine routes dataTextureA → dataTextureC next frame (standard in this codebase); mix bounded at 0.08 so worst case is a faint one-frame echo.
