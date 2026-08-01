# Batch 22 — mirror-dimension (Visualist)

## Lines
- Before: 109 → After: 172 (+63, within target 159–199)

## Slider map (unchanged contract — same ids/defaults/order)
- `u.zoom_params.x` → Segments (default 0.5): `floor(mix(2.0, 12.0, x))` fold count
- `u.zoom_params.y` → Spin Speed (default 0.6): `mix(-1.0, 1.0, y)`, bass-modulated
- `u.zoom_params.z` → Shift (default 0): `uv_new += vec2(offsetVal * 0.1)` (verbatim)
- `u.zoom_params.w` → Zoom (default 0.5): `mix(0.5, 2.0, w)`, mids-modulated

## Techniques added
1. **Spring-damped symmetry center** (priority 1): critically-damped spring (omega=5.0, zeta=1) chases the RAW mouse; state in `extraBuffer[133..138]` (pos.xy, vel.xy, init flag, last time). Integrated once per frame by thread (0,0); all threads ride the sprung center. Branchless `mouseActive` gate kept on the RAW mouse; when the mouse leaves, the spring target falls back to (0.5, 0.5) so the fracture point drifts home.
2. **Click mirror spins**: ripple loop guarded `min(u32(u.config.y), 50u)`; each live ripple adds `sign(hash(clickPos)) * exp(-age * 2.0) * 2.0` radians of rotation kick to `a` (pre-fold), so clicks whirl the kaleidoscope one way and it relaxes over ~2 s.
3. **Per-segment FFT shimmer**: `segIdx` derived from the pre-fold angle via positive-modulo `u32(fract(floor(a/segmentAngle)/8.0)*8.0)`; `plasmaBuffer[segIdx + 1u].x` modulates sampled brightness ±8%, so segments pulse across the spectrum.
4. **Treble seam glow**: `pow(foldCloseness, 6.0) * treble * 0.45` cool-white glow on the mirror fold lines (also puts the previously-unused `treble` to work).
5. **Stale header fix**: `Category: kaleidoscope` → `Category: artistic` (comment-only), plus batch-22 upgrade note.

## Verbatim structures preserved
- Polar conversion: `let r = length(p); var a = atan2(p.y, p.x);`
- Fract segment modulo: `a = fract(a / segmentAngle) * segmentAngle;`
- Triangle fold: `a = abs(a - segmentAngle * 0.5);`
- Zoom/offset application: `uv_new += vec2<f32>(offsetVal * 0.1); uv_new *= zoom;`
- Aspect un-correction: `uv_new.x /= aspect; uv_new += 0.5;`
- Immutable 13-binding layout, `@workgroup_size(16, 16, 1)`, writes to writeTexture/writeDepthTexture/dataTextureA every frame, `textureSampleLevel(..., 0.0)`, dataTextureA = DISPLAY color.

## JSON changes
- `shader_definitions/artistic/mirror-dimension.json`: added ONLY `updatedParams` (4 entries, indices 0–3, exact names/defaults/min/max/step from the brief) and `"updated": true`. `params` block untouched.

## extraBuffer usage
- Writes/reads ONLY indices 133–138 (inside [133..255]). No writes to [0..132].

## Deviations
- None. Brief allowed extraBuffer[133..136]; used 137/138 for init flag + last-time (still within [133..255], matching the repo's established spring pattern in mouse-gravity.wgsl).

## Gate result
```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/mirror-dimension.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ naga OK, bindgroup compatible
```
