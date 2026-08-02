# Swarm Output: kinetic-dispersion (Batch 21, Role: Optimizer)

## Lines
- Before: 107 → After: 186 (+79, within target 157–197)

## Slider map (roles preserved, no renames/re-defaults)
- `u.zoom_params.x` — Sensitivity (min 0.1 kept): `* 50.0 * bass_env(bass, mids)` → dispersion field strength (unchanged mapping)
- `u.zoom_params.y` — Scatter Amount: `* 0.1 * voiceGain` → per-block displacement kick, now FFT-voice modulated ±30%
- `u.zoom_params.z` — Aberration: `* 0.05 * (1.0 + treble * 0.5)` → r/g/b split width (unchanged mapping)
- `u.zoom_params.w` — Block Size: `max(1.0, * 50.0)` → blockUV quantization cell (unchanged mapping)

## Techniques applied
1. **Spring-damped influence center (priority 1):** critically-damped spring (omega=8.0, stiffness=ω², damping=2ω) in `extraBuffer[133..137]` (133/134 = sprung center, 135/136 = velocity, 137 = last time; written only by invocation (0,0)). Raw mouse is the spring target; first touch seeds at cursor so it never snaps. Spring velocity magnitude boosts intensity: `velBoost = min(length(springVel) * 2.0, 0.5)` — makes "mouse-velocity dispersion" literally true.
2. **Click shatter bursts:** ripple loop guarded `min(u32(u.config.y), 50u)`; each live ripple (age 0–1.0s) adds a decaying local intensity spike (`crack²`, 0.25-radius falloff) plus a radial displacement kick (`burstKick.x * 0.05`) and a brief click flash on color.
3. **Per-block FFT voices:** `voiceBin = u32(hash12(blockUV * 7.0) * 8.0) % 8u + 1u`; reads engine FFT at `extraBuffer[4u + voiceBin]` (read-only, [5..132] range, bounds-checked via `arrayLength`); `voiceGain = 1.0 + (clamp(voice,0,1) - 0.5) * 0.6` → ±30% scatter modulation per block.
4. **Stale-comment fixes (comment-only):** header `Category: distortion` → `interactive-mouse`; struct comments `y=ClickCount` → `y=RippleCount`, `w=Generic2` → `w=MouseDown`, zoom_params labeled with actual slider roles.

## Verbatim preserved
- `hash12`, `bass_env`, `curl2D` helpers — untouched
- blockUV quantization line — untouched
- displacement + curl composition formula `(rnd - 0.5) * intensity * scatter * depthScatter + curl.x` — kept as initializer (`let`→`var` so the click kick can augment it on the next line)
- r/g/b split taps (3 `textureSampleLevel(..., 0.0)` lines) — untouched
- bass shockwave (`shock` + color add) — untouched
- 13-binding layout, `@workgroup_size(16, 16, 1)`, writes to writeTexture/writeDepthTexture/dataTextureA every frame, dataTextureA = DISPLAY color

## JSON changes
- Added ONLY `updatedParams` (index 0–3, exact brief values) + `"updated": true` to `shader_definitions/interactive-mouse/kinetic-dispersion.json`. params block untouched. Validated with `json.tool`.

## Deviations
- `displacement` changed from `let` to `var` (formula itself verbatim) so the click-burst displacement kick required by the brief could be added without altering the verbatim r/g/b tap lines.
- extraBuffer writes: only [133..137] (within [133..255]); reads of FFT bins [5..12] are read-only.

## Gate result
```
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ public/shaders/kinetic-dispersion.wgsl — naga OK, bindgroup compatible
```
