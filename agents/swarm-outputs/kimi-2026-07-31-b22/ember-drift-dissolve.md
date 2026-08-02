# Swarm Notes: ember-drift-dissolve (Batch 22, Visualist)

## Lines
- Before: 110 → After: 166 (+56, within target 160–200)

## Slider map (unchanged ids/ranges — saved-preset contract kept EXACT)
- index 0 `rise` (Rise Speed, 0–1.6, def 0.7) → `u.zoom_params.x` → `riseSpeed = x * (0.7 + bass * 0.4)` — drives vertical heat advection
- index 1 `spark` (Spark Density, 0–1.8, def 0.75) → `u.zoom_params.y` → `sparkDensity = y * (0.6 + treble * 1.1)` — drives birth rate
- index 2 `heat` (Heat Turbulence, 0–1.0, def 0.6) → `u.zoom_params.z` → `heat` — curl/turbulence term in heatField
- index 3 `decay` (Ember Decay, 0.4–0.98, def 0.82) → `u.zoom_params.w` → `decay = w * 0.9 + 0.1` — ember age persistence

## Techniques added
1. **Click ignition (priority 1):** ripple loop guarded `min(u32(u.config.y), 50u)`. Each live ripple (`rAge` in [0, 1.5s)) adds a birth burst: aspect-corrected `smoothstep(0.2, 0.0, rDist) * (1 - rAge/1.5)`, weighted by emberMask (bright areas catch fire more readily), fed into `age` so the normal advection/state loop carries the click-fire upward. Fresh ignitions also render a white-hot flash core (`ignite²` gated by age cool-off) on top of the ember palette.
2. **Mouse heat plume (optional flavor):** aspect-corrected `smoothstep(0.3, 0.0, dist)` mouseMask; `heatFlow.y *= 1.0 + mouseMask * 0.8` plus a small lateral stir, and a faint `emberCol` glow lift near the cursor.
3. **Per-region FFT crackle:** 8 vertical bands (`band = min(u32(uv.x * 8.0), 7u)`), each riding `plasmaBuffer[(band % 8u) + 1u].x`; band-localized hash spark term feeds age and adds a palette-colored flash, so crackle dances across the spectrum.

## Preserved VERBATIM
- hash21 helper
- emberMask (`smoothstep(0.35, 0.82, luma)`)
- heatField construction (kept as-is; plume applied to a derived `heatFlow` copy)
- birth and spark steps
- age/decay/turb/intensity math (original lines byte-identical; new terms appended after)
- emberCol ramp, glow
- haze, semantic alpha
- State contract: `dataTextureA` written every frame as `(age, lateral, intensity, glow)` — no tonemap; `dataTextureC` read as prev state + advection source
- All 13 bindings, `@workgroup_size(16, 16, 1)`, `textureSampleLevel(..., 0.0)`

## JSON changes
- `shader_definitions/image/ember-drift-dissolve.json`: added ONLY `updatedParams` (4 entries, index 0–3, names/defaults/min/max/step exactly per brief) and `"updated": true`. `params` untouched.

## Deviations
- `prevUV` advection line now uses `heatFlow` (heatField + mouse plume) instead of `heatField` — required by the brief's plume instruction; heatField construction itself is verbatim and advection magnitude/clamp unchanged.
- extraBuffer declared but unused (as before) → 0 violations.

## Gate result
`python3 scripts/wgsl_precommit_gate.py --files public/shaders/ember-drift-dissolve.wgsl`
→ **GREEN**: 1 passed / 0 failed, 0 warnings, 0 extraBuffer violations (naga OK, bindgroup compatible).
