# Swarm Output: sonar-pulse (Batch 20)

**Role:** Interactivist
**File:** `public/shaders/sonar-pulse.wgsl`
**JSON:** `shader_definitions/interactive-mouse/sonar-pulse.json`

## Line counts

- Before: 103 lines
- After: 169 lines (+66, within target range 153–193 / +50 to +90)

## Slider mapping (saved-preset contract preserved — no renames/re-defaults)

| Index | zoom_params | Param id | Name | Default | WGSL wiring |
|-------|-------------|----------|------|---------|-------------|
| 0 | x | speed | Wave Speed | 0.5 | `waveSpeed = mix(1.0, 10.0, x) * bass_env(bass, mids)` — main ring sweep rate |
| 1 | y | freq | Frequency | 0.5 | `waveFreq = mix(10.0, 100.0, y) + mids * 10.0` — radial ring density |
| 2 | z | intensity | Intensity | 0.5 | `intensity = clamp(z + treble * 0.1, 0, 1)` — pulse/ping strength + distortion amplitude |
| 3 | w | width | Wave Width | 0.3 | `waveWidth = max(mix(0.1, 0.5, w), 0.001)` — pulse smoothstep band, reused by click-ping ring profile |

Roles kept EXACTLY as the existing mapping (already shader-specific, not boilerplate).

## Techniques implemented

1. **CLICK PINGS (priority 1):** Ripple loop guarded by `min(u32(u.config.y), 50u)`. Each live ripple (`age = time - rp.z`, 0–2s life) is a sonar emitter: expanding ring at radius `age * 0.6`, ring profile reuses the shader's own `smoothstep(1.0 - waveWidth, 1.0, ...)` pulse shape, envelope `exp(-age * 2.0)`. Pings accumulate into `pingStrength` (added to `pulseStrength` → `totalPulse`, which feeds the chromatic echo via `chromaOffset` and alpha) and into `pingOffset` (added to the UV distortion). Every click fires a visible ping that sweeps and distorts the image.
2. **Spring-damper sonar origin:** Critically damped spring (omega=8.0, stiffness=omega², damping=2·omega) integrated by writer thread (0,0) only; state in `extraBuffer[133..137]` (pos.xy, vel.xy, lastTime). First touch seeds at cursor (no snap from origin). dt clamped to [0.001, 0.05]. Aspect correction applied to the SPRUNG position; raw mouse stays the spring target.
3. **Per-ring spectral shimmer:** `ringIdx = u32(floor(abs(phase) / 6.28318))`; `plasmaBuffer[(ringIdx % 8u) + 1u].x` (FFT bins 1–8) drives `shimmer`, tinting `pulseColor = mix(sonarGreen, beatViolet, shimmer)` between the green sonar `(0,1,0.5)` and violet beat `(0.5,0.2,0.8)` colors.
4. **Stale comment fixes (comment-only):** `config.y` = RippleCount (was ClickCount), `zoom_config.w` = MouseDown (was Generic2).

## VERBATIM-preserved structures

- `bass_env` helper (unchanged)
- phase/pulse/falloff core: `phase`, `wave`, `pulse`, `falloff` lines
- Interference beat construction: `phase2`, `beat`, `beatMask` lines, and the violet beat add line
- `pulseStrength = pulse * intensity * falloff * audioBoost` (pings added via separate `totalPulse` so the original line stays intact)
- `safeDist` normalize guard
- r/g/b chromatic echo taps (`rUV`/`gUV`/`bUV` + three `textureSampleLevel(..., 0.0)` channel reads)
- Full 13-binding layout, `@workgroup_size(16, 16, 1)`, all three writes (writeTexture, writeDepthTexture, dataTextureA — dataTextureA stays DISPLAY color), depth attenuation + alpha tail

## JSON changes

- Added ONLY `updatedParams` (indices 0–3, names/defaults/min/max/step exactly as brief) and `"updated": true`. Existing `params` block untouched.

## Deviations

- `ringIdx` uses `abs(phase)` before the u32 cast — phase goes negative (time term), and `u32()` of a negative float is out-of-range; abs keeps the bin selection well-defined while preserving the `floor(phase / 6.28318)` derivation and `(ringIdx % 8u) + 1u` indexing from the brief.
- Spring uses one extra slot, `extraBuffer[137]`, for last update time (still within the [133..255] persistent-state window; [0..4] reserved and [5..132] engine FFT untouched).

## Gate result

```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/sonar-pulse.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ public/shaders/sonar-pulse.wgsl — naga OK, bindgroup compatible
```

GREEN — 0 warnings, 0 extraBuffer violations.
