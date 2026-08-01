# Agent Notes: reactive-glass-grid (Batch 19)

**Agent:** Kimi swarm agent (Visualist role)
**Date:** 2026-07-31
**Brief:** swarm-tasks/kimi-briefs-2026-07-31-b19/reactive-glass-grid.md

## Line Counts

- **Before:** 100 lines
- **After:** 163 lines
- **Delta:** +63 (target +50 to +90 ✅; final 163 within 150–190 ✅)

## Per-Slider Mapping (saved-preset contract preserved — no renames/re-defaults)

| Slider | JSON id | Default | WGSL source | Drives |
|---|---|---|---|---|
| 0 — Tile Density | `tile_size` | 0.5 | `u.zoom_params.x` | `cellDensity = mix(4.0, 40.0, x) * bass_env(...)` — tile grid density |
| 1 — Refraction | `refraction` | 0.5 | `u.zoom_params.y` | `refractionAmount = y * (1.0 + mids*0.3)` — refraction bend + chromatic aberration magnitude |
| 2 — Glow Intensity | `glow` | 0.5 | `u.zoom_params.z` | `glowIntensity = z * bass_env(...)` — influence radius weight + gridGlow brightness |
| 3 — Edge Smoothness | `edge_smooth` | 0.2 | `u.zoom_params.w` | `edgeSmooth = mix(0.12, 0.48, w)` — tile edge falloff smoothstep |

The existing mapping was already shader-specific (each slider drives a real constant of the glass-tile algorithm), so it was kept verbatim per the saved-preset contract.

## Techniques Implemented

1. **Spring-damper influence center (priority 1):** Critically-damped spring (ω=12, semi-implicit Euler) integrated by invocation (0,0) into `extraBuffer[133..136]` (pos.xy, vel.xy); `extraBuffer[137]` stores prev-frame time for stable dt (clamped [0, 0.1]). Raw clamped mouse (`springGoal`) is the spring target; all invocations read the smoothed center as `mousePos`, so the glass bulge trails the cursor with weight. First-frame init snaps the spring to the goal.
2. **Click glass shockwaves:** Loop over `u.ripples[]` guarded by `min(u32(u.config.y), 50u)`. Each live ripple (age ∈ (0, 1.5s)) contributes an expanding smoothstep ring (radius = age·0.55, width 0.10, quadratic fade) that boosts `influence` (+0.9·ring·fade²) and accumulates `shockSparkle`, which feeds both the caustic term and a cool glass ring-flash color add.
3. **Per-tile FFT voices:** `tileBin = u32(hash21(floor(gridUV)) * 8.0) % 8u + 1u` (exact brief formula); `tileVoice = plasmaBuffer[tileBin].x` modulates that tile's caustic sparkle amplitude (replacing pure global-treble drive with `treble*0.8 + tileVoice*1.4 + shockSparkle*1.2`) and the green-channel glow term, so different tiles listen to different frequency bins.

## VERBATIM-Preserved Structures (CAUTION list)

- `bass_env(bass, mids)` helper — unchanged
- `hash21(p)` helper — unchanged
- Refraction + chromatic dispersion tap structure (`rUV`/`gUV`/`bUV` clamps + three `textureSampleLevel(readTexture, u_sampler, ..., 0.0)` reads into r/g/b) — unchanged
- Fresnel rim block (`pow(1.0 - abs(dot(normal, vec3(0,0,1))), 2.0)` + color add) — unchanged
- `ior = mix(1.1, 1.5, depth)` depth mapping — unchanged
- `dataTextureA` written with raw DISPLAY `finalPixel` (never tonemapped) — unchanged
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, all three output textures written every frame
- extraBuffer writes confined to [133..137] ⊂ [133..255] only

## JSON Changes

`shader_definitions/interactive-mouse/reactive-glass-grid.json`: added **only** the `updatedParams` array (indices 0–3, names/defaults/min/max/step exactly per brief) and `"updated": true`. No other keys touched. Validated with `json.load`.

## Deviations from Brief

- Used `extraBuffer[137]` for prev-frame time in addition to the brief-named [133..136]. Still within the allowed [133..255] shader-state range; needed for a frame-rate-independent spring dt. No engine-reserved ([0..4]) or FFT-bin ([5..132]) slots touched.
- Renamed local `mousePos` → `rawMouse` and rebound `mousePos` to the smoothed spring center (required by priority 1; not a VERBATIM-listed line).

## Gate Result

```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/reactive-glass-grid.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ public/shaders/reactive-glass-grid.wgsl — naga OK, bindgroup compatible
```

**GREEN — 0 warnings, 0 extraBuffer violations.**
