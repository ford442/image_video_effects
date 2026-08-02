# Swarm Output: interactive-emboss (Batch 21)

**Role:** Interactivist
**Result:** ✅ Gate green (naga OK, bindgroup compatible, 0 warnings, 0 extraBuffer violations)

## Lines
- Before: 107 → After: 176 (+69, target +50..+90, range 157–197 ✅)

## Slider map (unchanged — same ids/defaults, wired via zoom_params)
- x = Strength (default 0.5) → `strength = x * 5.0 * (1.0 + bass * 0.5)` (verbatim mapping)
- y = Intensity (default 1.0) → `mix_amt`, composites emboss vs original (full effect at 1.0)
- z = Color Mode (default 0, step switch) → `step(0.5, color_mode)` gray/color select
- w = Emboss Depth (default 0.5) → `reliefContrast = 0.5 + w * 1.5`, then depth-scaled

## Techniques added
1. **Spring-damper light source (priority 1):** critically-damped spring (omega=8, stiffness=ω², damping=2ω) integrated by invocation (0,0) into extraBuffer[133..137] (pos.xy, vel.xy, prevTime), guarded by `arrayLength(&extraBuffer) > 137u`; first touch seeds at cursor. All pixels read the sprung position — raw mouse stays the spring target, `mouse` var reused so downstream light_dir code is untouched.
2. **Click relief stamps:** ripple loop guarded `min(u32(u.config.y), 50u)`; each live ripple (age ≤ 1.2s) adds a Gaussian core dent + expanding ring (radius = age*0.5, Gaussian profile) with linear 1.2s fade; stamp sum boosts `diff` scaled by strength and reliefContrast.
3. **Depth-aware relief (earns the tag):** depth sampled once (non_filtering_sampler, level 0.0); `reliefContrast *= mix(0.7, 1.3, depth)`; same sample reused for the pass-through writeDepthTexture store.
4. **Soft-knee hue-preserving clamp:** `emboss_soft = result_emboss / (1.0 + max(peak - 1.0, 0.0))` (peak-channel ratio-preserving compression, no hue shift), then low-side clamp to [0,1]. Applied between the gray/color step and the mix_amt composite.

## Verbatim preserved
- 13-binding layout, struct Uniforms, `@workgroup_size(16, 16, 1)`
- 4-tap gradient (l/r/t/b `textureSampleLevel(..., 0.0)`) + luminance dots
- `light_dir` normalize-with-zero-guard block + dot-product emboss core line
- gray/color step: `mix(gray_emboss, color_emboss, step(0.5, color_mode))`
- mix_amt compositing structure + ALL dev thinking-out-loud comments ("Left is higher? Or Right?", "Wait, I said param y is mix_amt...", "If Intensity = 1.0, we see full emboss.", Sobel kernel ASCII, audio comment)
- alpha formula, writeTexture/dataTextureA stores (dataTextureA = DISPLAY color), depth pass-through store

## JSON changes
- Added ONLY `"updatedParams"` (4 entries, index 0–3, exact brief values) + `"updated": true`. Params/features/tags untouched. JSON validates.

## Deviations
- Depth sample moved earlier in main (was at end next to its store) so it can scale reliefContrast; the `// Pass depth` comment + store line remain verbatim at the end using the same value.
- `reliefContrast` changed `let` → `var` (required for depth scaling); mapping line text preserved.
- `diff` changed `let` → `var` (required for click-stamp accumulation); core emboss line text preserved.
- Final composite mixes `emboss_final` (soft-knee clamped) instead of raw `result_emboss` — required by the brief's clamp mandate; mix structure + trailing comments verbatim.
- extraBuffer writes confined to [133..137] (⊂ [133..255]); no reserved-word identifiers; no binding changes; binding 13 not declared (not previously used).

## Gate result
```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/interactive-emboss.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ public/shaders/interactive-emboss.wgsl — naga OK, bindgroup compatible
```
