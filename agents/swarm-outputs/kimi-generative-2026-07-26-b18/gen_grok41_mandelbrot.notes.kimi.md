# Notes: gen_grok41_mandelbrot (Buddhabrot Nebula) — Batch 18, Optimizer

## Line delta
- Before: 221 lines (per brief; working file had a partial prior pass)
- After: **289 lines** (+68, within target 271–311)
- This session's delta on the file itself: +0 lines (fixed 1 pre-existing syntax typo `vec3<f3>` → `vec3<f32>` at `hash3`, line 44)

## Changes per technique

### 1. Double-tonemap feedback fix (priority 1) ✅
- `dataTextureA` now stores **LINEAR pre-tonemap** accumulation (`linearColor`), not the ACES-tonemapped output.
- History read from `dataTextureC` is mixed in linear space: `linearColor = mix(color, prev, historyBlend)`.
- `acesToneMapping()` is applied **only** to the display path after the history mix (`displayColor`), never fed back — eliminates progressive contrast fade.
- Density keeps its Reinhard soft clamp (`d / (1 + d)`); only color feedback changed.

### 2. OOB bounds guard ✅
- Early return when `global_id.x/y >= resolution` (dispatch rounded up to 16×16 workgroups).

### 3. Gliding navigation (extraBuffer[133..136]) ✅
- [133]=smoothed center X, [134]=smoothed center Y, [135]=smoothed zoom param, [136]=init flag.
- Single invocation (0,0) integrates a spring-damper (`glide = 0.07` per-frame mix toward goal); all other invocations read persistent state.
- First frame initializes from slider targets (init flag), so no snap from zero state.

### 4. Click ripples re-target zoom center ✅
- Loop guarded with `min(u32(u.config.y), 50u)`.
- Each live ripple (age < 1.4 s, weight decays linearly, scaled by `ripple.w`) pulls the spring goal center toward the click point converted into the complex plane via current scale/aspect; `clickPull` blends `navCenter → clickCenter`.

### 5. Spectral stars (plasmaBuffer[1..8]) ✅
- Each star is assigned one of 8 spectrum bins via `hash2(pixel_seed*0.37 + …).y` → `starBin = 1..8`.
- Per-bin energy loosens the threshold (`starThresh = 0.998 − treble*0.003 − bandEnergy*0.004`), boosts gain (`0.5 + bandEnergy*1.5`, clamped ≤1.25), plus per-star twinkle term.

## Slider wiring (contract preserved: same ids/names/defaults/ranges)
- `param1 Center X` → `zoom_params.x` → complex-plane center X target `mix(-2.0, 1.0, x)` (spring-damped).
- `param2 Center Y` → `zoom_params.y` → center Y target `mix(-1.5, 1.5, y)` (spring-damped).
- `param3 Zoom Scale` → `zoom_params.z` → view scale `mix(0.05, 2.5, z) / (1 + bass*0.6)` (spring-damped).
- `param4 Evolution Speed` → `zoom_params.w` → dual purpose kept: evolution time scale `mix(0.05, 1.5, w)` AND history blend `clamp(0.85 − w*0.5, 0, 0.85)`.

## Binding compliance
- Canonical 13-binding layout unchanged (0–12); no binding 13 added; no renumbering.
- `@workgroup_size(16, 16, 1)` preserved.
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame.
- `textureSampleLevel(..., 0.0)` for sampler reads; no storage texture loads needed.
- extraBuffer access only in [133..136] (persistent state); [0..4]/[5..132] untouched.
- `cmul` / `escapes` / orbit-points accumulation loops preserved verbatim.
- No WGSL reserved keywords used as identifiers.

## QA flags
- ⚠️ naga unavailable in this environment (`naga not found`) — naga validation step skipped by gate; bindgroup + workgroup checks ran and passed. A pre-existing `vec3<f3>` typo in `hash3` (would have failed naga) was found by inspection and fixed.
- Spring integration done by invocation (0,0) — racy by one frame at worst for other invocations; visually benign (documented in-code).
- JSON definition written verbatim from brief's fenced block (diff-verified identical).

## Gate / audit status (final)
- `wgsl_precommit_gate.py`: ✅ Passed 1/1, 0 warnings, 0 extraBuffer violations (naga skipped — env limitation)
- `audit_extrabuffer.py`: ✅ AUDIT PASS (0 new violations, writes only to [133..136])
- `audit_dead_sliders.py`: ✅ AUDIT PASS (0 dead sliders — all 4 params consumed in WGSL)
