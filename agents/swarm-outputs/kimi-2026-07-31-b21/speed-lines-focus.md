# Batch 21 Notes: speed-lines-focus (Visualist)

**File:** `public/shaders/speed-lines-focus.wgsl`
**JSON:** `shader_definitions/artistic/speed-lines-focus.json`
**Lines:** 106 → 172 (+66, target 156–196 ✅)

## Slider map (unchanged contract — same ids/defaults, wired via u.zoom_params)

| index | id | JSON name | WGSL wiring |
|---|---|---|---|
| 0 | blur_strength | Blur Strength | `u.zoom_params.x * 0.1 * (1.0 + bass * 0.2)` — zoom-blur reach |
| 1 | line_density | Line Density | `u.zoom_params.y * 50.0 + 10.0` — angular noise frequency (also drives click-burst streaks at 0.5×) |
| 2 | line_speed | Line Speed | `u.zoom_params.z * 10.0 + 2.0` — temporal scroll of line noise |
| 3 | contrast | Contrast | `(u.zoom_params.w + 0.5) * (1.0 + treble * 0.2)` — line/burst intensity gain |

No renames, no re-defaults, mapping order preserved exactly.

## Techniques implemented

1. **Spring-damped focus point (priority 1):** critically damped spring (`omega = 9.0`, stiffness = ω², damping = 2ω) integrated once per frame by thread (0,0). State in extraBuffer[133..136] (sprung pos + velocity), [137] = last update time. First touch seeds at cursor (`prevTime <= 0.0`) so no snap. All geometry (uvCenter, zoom blur, dist/angle, vignette) now uses the SPRUNG focus — the 16-tap blur smears naturally during fast cursor moves. Raw mouse (`u.zoom_config.yz`) remains the spring target only.
2. **Click action bursts:** ripple loop guarded `min(u32(u.config.y), 50u)`. Each live ripple (age ≤ 1.0s) adds an expanding ring (`burstRadius = age * 0.9`) of angular streaks (`noise1(rpAngle * (lineDensity*0.5) - age*12.0)`, smoothstep 0.45–0.75) emanating from the click angle, fading linearly over ~1.0s, scaled by `contrast` — manga impact frames per click.
3. **Angular FFT voices:** 8 sectors around the focus, `sector = u32((angle / 6.28318 + 0.5) * 8.0)`, voice gain from `plasmaBuffer[(sector % 8u) + 1u].x` (clamped, ×1.5 boost) multiplies `lineEffect` so lines pulse around the spectrum.
4. **Depth write normalized:** `vec4(depth, 0.0, 0.0, 1.0)` → `vec4(depth, 0.0, 0.0, 0.0)` (stray alpha removed).
5. **Header fix:** `Category: image` → `Category: artistic` (comment-only) + Batch-21 line.

## Verbatim preserved (CAUTION list)

- `hash11` / `noise1` helpers — untouched, byte-identical.
- 16-tap zoom blur loop (`let samples = 16;` … `blurColor / f32(samples)`) — structure identical; only the focus variable it references is now sprung.
- Line construction `noise1(angle * lineDensity + time * lineSpeed)` and `smoothstep(0.6, 0.8, n)` — identical; `lineEffect` base kept as `lines * centerMask * contrast` before voice/burst additions.
- `centerMask = smoothstep(0.2, 0.5, dist)` — identical.
- Vignette `finalColor *= (1.0 - dist * 0.5);` — identical.
- 13-binding layout, `@workgroup_size(16, 16, 1)`, early-return guard, alpha blend logic (`effectIntensity` / `finalAlpha`) — all preserved.
- `dataTextureA` = DISPLAY color (same as writeTexture). extraBuffer writes only [133..137].

## JSON changes

Added ONLY `"updatedParams"` (4 entries, index 0–3, brief's pre-computed values) and `"updated": true`. Validated with `json.load`.

## Deviations

None. Gate passed on first attempt.

## Gate result

```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/speed-lines-focus.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ public/shaders/speed-lines-focus.wgsl — naga OK, bindgroup compatible
```
