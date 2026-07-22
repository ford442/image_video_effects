# Notes: spec-analytic-noise-flow (b13, Optimizer role)

## Line delta
- Before: 175 lines → After: 231 lines (**+56**, inside the +50–90 target; total within 225–265 band).

## Key changes per technique

1. **Iso-contour ridges (free analytic gradient)** — Added `contourRidge(value, gradMag, count, sharpen)` helper. Ridge mask from `fract(noise1.x * count)` with line width adapted to `length(noise1.yz)` (hairline in steep regions, feathered in flats — only possible because the gradient is a free byproduct, no finite differences). Contour density rides the Detail-adjacent Curl slider (`mix(4.0, 20.0, u.zoom_params.w)`); treble sharpens lines (`(1.0 - treble * 0.60)`, clamped min width 0.02). Ridge tint modulated by mids and scaled by curlAmount.

2. **Bass surge** — `bassEnv = clamp(bass * 1.5, 0.0, 1.8)`; advection distance now `velocity * advectionStr * (1.0 + bassEnv)` so kicks visibly surge the flow field.

3. **Temporally coherent streamlines** — Separate read path: `prevVel = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rg` (dataTextureA velocity resurfacing via dataTextureC), exponential smoothing `velocity = mix(velocity, prevVel, velSmooth)` with `velSmooth = clamp(0.65 - bassEnv * 0.25, 0.15, 0.75)` (bass briefly reopens the filter so kicks don't lag). The legacy light color feedback (`prev.rgb * 0.9` at ~0.03 mix) is kept intact as its own read.

4. **Slider wiring** — All 4 existing params wired via zoom_params.x/y/z/w with the saved-preset contract untouched (ids/defaults/min/max/step identical). x→noise frequency (flowScale), y→time rate (flowSpeed), z→advection distance (+ bass surge), w→curl vector + contour density. Added in-code comment documenting the mapping.

5. **Preservation** — `noiseWithDerivative` kept byte-identical (quintic k0/k1/k2/k4 form). Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, all three stores (writeTexture/writeDepthTexture/dataTextureA) every frame, `textureSampleLevel(..., 0.0)` for sampler reads. No new/renumbered bindings, no reserved identifiers, extraBuffer untouched. Legacy streamline band kept (fades as Curl rises); added small speed-glow vignette from velocity magnitude.

## JSON
- Added `updatedParams` (exactly 4 entries, index 0–3, mirroring existing params names/defaults/min/max/step) and `"updated": true`. Nothing else changed. `json.load` passes.

## QA flags
- None blocking. Minor note: first frames read uninitialized dataTextureC for `prevVel` — the exponential filter self-corrects within a few frames (standard for this engine's temporal shaders).
- **No-GPU caveat:** this Cloud VM has no WebGPU adapter; visual QA (contour crispness, bass surge feel, shimmer reduction) is deferred to real hardware. Validated statically via naga + bindgroup gate only.

## Gate result
- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/spec-analytic-noise-flow.wgsl` → exit 0, Passed: 1, **0 warnings**, naga OK, bindgroup compatible.
