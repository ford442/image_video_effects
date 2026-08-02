# Swarm Notes: fireworks-edge-ignite (Batch 21)

## Result
- **Lines:** 106 → **175** (+69, inside target 156–196)
- **Gate:** `python3 scripts/wgsl_precommit_gate.py --files public/shaders/fireworks-edge-ignite.wgsl` — ✅ PASSED, naga OK, bindgroup compatible, 0 warnings, 0 extraBuffer violations (extraBuffer never written)

## Bugs fixed (family diseases)
1. **Mouse coord units bug (Priority 1):** held-click burst used `(u.zoom_config.yz - res*0.5)/min(res.x,res.y)` — treating normalized [0,1] mouse coords as pixels, so bursts landed off-screen. Fixed to `(u.zoom_config.yz * res - res * 0.5) / min(res.x, res.y)`; burst now centers on the cursor.
2. **Flat-0.0 depth clobber (Priority 2):** `writeDepthTexture` stored `vec4(0.0)` despite the `depth-aware` feature tag. Now writes honest depth: `clamp(dot(col, lumWeights)*0.9 + edge*0.2, 0.0, 1.0)` — luminance of the tonemapped color plus edge term, so sparks/contours sit forward in chains.

## Slider map (roles preserved exactly, ids/defaults untouched)
- `u.zoom_params.x` — Edge Sensitivity → `edgeSens = mix(0.1, 0.8, x)` (edge/probe thresholds)
- `u.zoom_params.y` — Launch Power → `power = mix(0.35, 1.6, y)` (shell velocity/burst energy)
- `u.zoom_params.z` — Trail Glow → `trail = mix(0.88, 0.96, z)` (temporal feedback persistence)
- `u.zoom_params.w` — Color Boost → `boost = mix(0.5, 1.5, w)` (contour glow + spark brightness)

## Techniques added
- `normToCentered()` helper for normalized→centered-UV conversion (used by ripple loop).
- **Click shell launches:** ripple loop guarded `min(u32(u.config.y), 50u)`; each live ripple (age = time − ripple.z, culled outside [0, 4.2]) fires a one-shot shell at its click point: ascent phase (age < 0.6) with rising comet head + warm 4-node trailing streak, burst phase (age ≥ 0.6) reusing the verbatim `sparkPos`/`softGlow` pipeline (16+energy·18 sparks, gravity 0.85, apex flash).
- Held-click block gained an ignition flash hugging the cursor contour.
- Bass-driven ambient contour glow (deepens edge bursts on kicks).
- Edge-localized treble crackle (white-hot micro-sparks walk strong contours), complementing the existing global treble crackle.

## Verbatim preserved
`acesToneMap`, `hash1`, `softGlow`, `sampleImg` (centered-UV convention `uv*0.5+0.5`), `edgeAt`, `sparkPos`, the 8-probe ignition loop with both `continue` guards (unchanged constants), temporal feedback `mix(prev*trail, col, 0.32)`, global treble crackle line, `acesToneMap(col*1.05)`, `dataTextureB` write (`col*0.5+prev*0.4`), A = display color / C = prev, all writeTexture/alpha math. 13-binding layout and `@workgroup_size(16, 16, 1)` unchanged; `writeTexture`, `writeDepthTexture`, `dataTextureA` written every frame.

## JSON changes
`shader_definitions/image/fireworks-edge-ignite.json`: added ONLY `updatedParams` (indices 0–3, exact names/defaults/min/max/step from brief) and `"updated": true`. Params untouched.

## Deviations
None.
