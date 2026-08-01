# Batch 20 — spectral-rain (Visualist)

## Line counts
- **Before:** 104 lines
- **After:** 172 lines (**+68**, target +50..+90 ✓; absolute range 154–194 ✓)

## Gate result
```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/spectral-rain.wgsl
Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ naga OK, bindgroup compatible — green on first pass
```

## Slider mapping (contract preserved — no renames/re-defaults)
| index | id | mapping | role in WGSL |
|---|---|---|---|
| 0 | density | zoom_params.x | `density = x*20+5` — rain column grid density |
| 1 | chromatic_strength | zoom_params.y | `chromaticStr = y*0.05*(1+bass*0.4)` — chromatic displacement amplitude |
| 2 | trail_length | zoom_params.z | `trailLenBase = z*0.5+0.1`, then per-column ±20% FFT modulation |
| 3 | rain_angle_scale | zoom_params.w | `angle = angleVal * mix(0.0, 1.5, w)` — 0–1.5 range honored |

## Techniques implemented
1. **Per-column FFT voices (priority 1):** `colBin = plasmaBuffer[(u32(gridID.x) % 8u) + 1u].x` — each column gets its own bin (1..8). `colBin` modulates trail length ±20% (`trailLenBase * (1.0 + (colBin-0.5)*0.4)`, clamped) and drop brightness (`bright = drop*0.1*(0.6+colBin*1.2)`). Streaks now shimmer across the spectrum.
2. **Dead mids/treble reads killed:** mids → click splash gain (`splash *= 1.0 + mids*0.6`); treble → brightness shimmer lift (`*(1.0+treble*0.4)`). bass role unchanged.
3. **Spring-damper rain controls:** critically-damped spring helper `spring_step` (~2.5 Hz settle, semi-implicit). extraBuffer[133..137]: 133/134 angle pos/vel, 135/136 speed pos/vel, 137 prev time (dt clamp 0.001–0.05). Branchless first-frame snap via `stateZero`. Raw mouse is the spring goal; `angleVal`/`speedVal` now come from spring state.
4. **Click splash bursts:** ripple loop guarded by `min(u32(u.config.y), 50u)`; each ripple with `0 ≤ age < 1.0s` adds a radial chromatic kick: `smoothstep(0.25,0,rDist) * fade² * 0.03` along the aspect-corrected radial direction (mapped back to uv space), accumulated into `splash` and added to `displace`.

## VERBATIM-preserved structures
- `hash12` helper — byte-identical
- Rotated-grid rain construction: `rotMat`/`rotUV`/`gridUV`/`gridID`/`gridOffset`/`colSpeed`/`yPos`/`dropNoise`/`drop` — all lines byte-identical (drop still `smoothstep(1.0 - trailLen, 1.0, dropNoise)`; the per-column trail value is bound to the `trailLen` name before it)
- `displace = vec2<f32>(s, c) * drop * chromaticStr` structure — kept, splash appended additively
- r/g/b `samplePos`/`sampleNeg` clamp + `textureSampleLevel(..., 0.0)` tap lines — byte-identical
- 13-binding layout, `@workgroup_size(16, 16, 1)`, writes to writeTexture/writeDepthTexture/dataTextureA every frame, dataTextureA = DISPLAY color
- extraBuffer writes only at literal indices 133–137 (⊂ [133..255]); no reserved-word identifiers

## JSON changes
`shader_definitions/visual-effects/spectral-rain.json`: added ONLY `updatedParams` (index 0–3, exact names/defaults/min/max/step from the brief, incl. Rain Angle Scale max 1.5) and `"updated": true`. Existing params block untouched.

## Deviations
- extraBuffer usage is [133..137] (5 slots) within the brief's allotted [133..138]; slot 137 stores prev-frame time for a stable spring dt instead of a fixed timestep.
- `trailLen` per-column value is clamped to [0.02, 0.95] so the `smoothstep(1.0 - trailLen, 1.0, ...)` window can never invert.
