# cosmic-web — Batch 17 Upgrade Notes (kimi)

## Line delta
- Before: 206 lines → After: **266 lines** (+60, within target 256–296)

## Changes per technique

### 1. Void feedback gap fix (priority 1)
- Removed the `if (density < VOID_CUTOFF) { ...store...; return; }` early-exit.
- Replaced with branchless `let isVoid = density < VOID_CUTOFF; color = select(color, voidColor, isVoid);`
  placed BEFORE the temporal feedback mix, so void pixels flow through the exact
  same `mix(prev.rgb * DECAY, color, FEEDBACK)` path as filament pixels →
  whole-frame temporal coherence, no more void shimmer at filament edges.
- Void alpha is unchanged (voidColor luma ≈ 0.018 → compositeAlpha lumaKey = 0 → α = 0).
- Void depth output preserved exactly via `select(density, 0.0, isVoid)` in the
  writeDepthTexture store.

### 2. Per-octave spectrum filament stack
- Single Voronoi density evaluation → 3-octave loop (`FILAMENT_OCTAVES = 3`).
- Octave `o` reads `plasmaBuffer[(u32(o) % 8u) + 1u].x` per the brief: octave 0
  (large structure) follows low/bass bins, octave 2 (fine structure) follows
  higher/treble bins.
- Per-octave gain `(OCTAVE_BIN_BASE + binLevel * OCTAVE_BIN_GAIN)` = 0.75 + bin·0.5,
  so silence still renders full structure (floor 0.75).
- Amplitudes 1 / 0.5 / 0.25, renormalized by `OCTAVE_AMP_SUM = 1.75` and clamped
  to [0,1] so VOID_CUTOFF / core smoothstep thresholds keep their tuning.
- Base-octave F1 captured (`f1base = select(f1base, vo.x, o == 0)`) to keep the
  cluster-node metric on the large-scale structure.

### 3. Spring-damper gravity well
- Critically-damped spring eases the well center toward the cursor:
  `accel = w²·(target − pos) − 2w·vel` with `SPRING_FREQ = 6.0`, fixed
  `SPRING_DT = 0.016` (config.y is rippleCount per engine truth, not delta time).
- State in safe zone only: extraBuffer[133/134] = position, [135/136] = velocity.
- First-frame snap init (`u.config.x < SPRING_DT`) avoids a corner swoop from
  zero-initialized state.
- Only invocation (0,0) commits state (avoids write races; benign 1-frame lag).
- Gravity well math itself (0.3 pull, smoothstep falloff, branchless normalize)
  unchanged — it now reads `wellPos` instead of the raw mouse.

## Slider wiring (saved-preset contract preserved)
- `u.zoom_params.x` → warpStrength (param1 "Warp Strength", 0.5) — domain warp amplitude.
- `u.zoom_params.y` → densityScale (param2 "Filament Density", 1.0) — filamentDensity scale arg (all octaves).
- `u.zoom_params.z` → time multiplier (param3 "Flow Speed", 0.2) — flow speed of the 3D Voronoi domain.
- `u.zoom_params.w` → colorShift (param4 "Color Shift", 0) — hue rotation of filament color.
- Same ids/names/defaults/min/max/step; updatedParams index 0–3 added per brief.

## Binding compliance
- Canonical 13-binding layout preserved verbatim (sampler, readTexture,
  writeTexture, Uniforms, readDepthTexture, non_filtering_sampler,
  writeDepthTexture, dataTextureA/B/C, extraBuffer, comparison_sampler,
  plasmaBuffer). No binding 13 added (was not used before).
- `@workgroup_size(16, 16, 1)` kept.
- Writes to writeTexture, writeDepthTexture, dataTextureA every frame on all paths.
- extraBuffer writes only to literal indices 133–136 (safe zone; [0..4] reserved,
  [5..132] FFT untouched). Reads of [133..136] also safe zone.
- voronoi3 branchless F1/F2, FILAMENT_SHARP=10 / FILAMENT_BIAS=0.05, and
  compositeAlpha preserved verbatim. No clamp added to dataTextureA (still
  pre-ACES HDR `temporal`).

## QA flags
- `wgsl_precommit_gate.py`: PASS, 0 warnings (naga binary unavailable in this
  environment — bindgroup + workgroup checks ran and passed).
- `audit_extrabuffer.py`: AUDIT PASS (0 new violations, 0 dynamic writes).
- `audit_dead_sliders.py`: AUDIT PASS (0 dead sliders).
- GPU visual check not possible here (headless VM, no WebGPU adapter).
- Note: brief's uniform-truth correction applied — Uniforms comments updated to
  config = [time, rippleCount, resW, resH], zoom_config = [time, mouseX, mouseY, mouseDown].
