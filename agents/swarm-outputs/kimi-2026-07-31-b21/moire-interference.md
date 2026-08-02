# Swarm Notes: moire-interference (Batch 21, Visualist)

## Lines
- Before: 105 → After: 174 (+69, within +50..+90 target; 155–195 range ✅)

## Bugs fixed
- Removed dead `var dir = normalize(uv - vec2<f32>(0.5));` (never used).
- Depth write normalized: `vec4(depth, 0.0, 0.0, 1.0)` → `vec4(depth, 0.0, 0.0, 0.0)`.
- Header fixed (comment-only): `Category: image` → `interactive-mouse`.
- Struct comment fixed: `config.y` = MouseClickCount → RippleCount.

## Slider map (roles preserved exactly, ids/defaults untouched)
- index 0 / zoom_params.x — **Frequency** (def 0.5): `mix(20.0, 200.0, x) * (1 + bass*0.1 + mids*0.05)`.
- index 1 / zoom_params.y — **Distortion** (def 0.5): `y * 0.05 * (1 + treble*0.1)` displacement strength.
- index 2 / zoom_params.z — **Aberration** (def 0.2): `z * 0.02` r/b channel split scale.
- index 3 / zoom_params.w — **Complexity** (def 0 = third wave off): third-wave branch weight.

## Techniques
- **Priority 1 — spring-damper mouse emitter:** critically-damped spring (`springStep`, omega=6.0, dt=0.016) in uncorrected uv space; state in extraBuffer[133..136] (pos.xy/vel.xy), init flag [137], written only by thread (0,0). Aspect correction applied to the SPRUNG position (`mouse = vec2(sprung.x * aspect, sprung.y)`). Raw cursor stays the spring target.
- **Click interference bursts:** ripple loop guarded `min(u32(u.config.y), 50u)`; each live ripple (age 0..2s) is a temporary third emitter using the same `sin(dR * freq - time * 2.0)` form, weight `exp(-age * 2.0)`.
- **Per-emitter FFT gain:** helper `fftBin(i)` reads engine bins at slot `i + 5` (reads only, no writes outside [133..255]); center emitter × `(1 + bin1*0.8)`, mouse emitter × `(1 + bin5*0.8)` — the two sources listen to different bands.

## Verbatim preserved
- Two-point sin core: `let w1 = sin(d1 * freq - time * 2.0);` / `let w2 = sin(d2 * freq - time * 2.0);` (gain applied at summation, sin forms untouched).
- Complexity third-wave branch (`if (complexity > 0.0) { ... mix(center, mouse, 0.5) ... sin(d3 * freq * 1.5 + time) ... }`) — exact.
- Displacement vector: `vec2<f32>(cos(interference * 3.14), sin(interference * 3.14)) * strength` — exact.
- r/g/b aberration tap structure (`r_uv/g_uv/b_uv` + three `textureSampleLevel(..., 0.0)` channel taps) — exact.
- 13-binding layout, `@workgroup_size(16, 16, 1)`, writes writeTexture/writeDepthTexture/dataTextureA every frame, dataTextureA = DISPLAY color.

## JSON changes
- Added ONLY `updatedParams` (indices 0–3, same names/defaults/min/max, step 0.01) and `"updated": true` to `shader_definitions/interactive-mouse/moire-interference.json`. No renames, no re-defaults. Validated with json.load.

## Deviations
- FFT gain multiplies w1/w2 at the interference summation (`w1 * gain1 + w2 * gain2`) rather than inside the sin lines, to keep the sin() core byte-verbatim per the CAUTION list.

## Gate
- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/moire-interference.wgsl`
- ✅ GREEN: 1 passed / 0 failed, 0 workgroup warnings, 0 extraBuffer violations, naga OK, bindgroup compatible.
