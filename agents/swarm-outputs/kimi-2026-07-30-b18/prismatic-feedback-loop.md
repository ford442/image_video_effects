# Agent Notes — prismatic-feedback-loop (Batch 18, Algorithmist)

## Lines
- Before: 97
- After: 176 (+79, within the +50..+90 target band; brief target 147–187 ✅)

## Gate result
```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/prismatic-feedback-loop.wgsl
✅ public/shaders/prismatic-feedback-loop.wgsl — naga OK, bindgroup compatible
Passed: 1 | Failed: 0 | Workgroup errors: 0
```

## Slider rewiring (priority 1 — all 4 labels were lies, now honest)
| Slider | id / default (unchanged) | Old (dishonest) role | New honest role |
|---|---|---|---|
| x "Feedback" | `feedbackAmount` / 0.5 | accumulation rate | temporal feedback mix: `mix(prev.rgb, prismColor, x)`, clamped to [0,1] |
| y "Blur Radius" | `blurRadius` / 1 | prism strength | prism tap spread magnitude; `y * 0.1` so default 1 reproduces the legacy ~0.1 offset scale (reads as chromatic soften/blur); audio-modulated by bass/treble as before |
| z "Glow Intensity" | `glowIntensity` / 0.8 | rotation | real glow term: soft-knee luminance of the accumulated trail (`max(lum-0.25,0)²`) lifted additively onto the output; exactly 0 at slider 0; mids-modulated |
| w "Chromatic Spread" | `chromaticSpread` / 0.02 | feedback mix | r/b separation fan-out angle: r and b tap directions rotate apart by `±w*PI`; tiny default 0.02 = subtle fringe |

- ids/names/defaults/min/max kept EXACTLY (saved-preset contract). `updatedParams` (index 0–3) and `"updated": true` added to the JSON verbatim from the brief; no existing param touched.
- The old z-driven rotation became a slow constant drift (`time * 0.1`), per the brief.

## Techniques implemented
1. **Honest slider rewiring** (above) — every slider now drives a real, label-matching constant of this shader's algorithm.
2. **Click prism bursts** — ripple loop guarded with `min(u32(u.config.y), 50u)`; each live ripple (age in `[0, 1.5s)`, `RIPPLE_LIFE = 1.5`) adds a decaying radial chromatic kick (`exp(-dist*9) * exp(-age*2)` falloff, radial outward direction) that pushes the r and b taps apart locally — clicks shatter the prism.
3. **Glow term** — trail-luminance halo applied to the visible output only (see deviation note), driven by z.
4. **Feedback blowout guard** — feedback mix t clamped to [0,1]; `blended` and `newAlpha` clamped to [0,1]; runaway feedback is impossible.
5. Stale header comment fixed (`Category: image` → `interactive-mouse`), comment-only.

## Stability / contract compliance
- `accumulativeAlpha()` preserved **VERBATIM**, including the select-based zero-guard.
- dataTextureA treated as pure accumulation state: the **raw** `accumulated` value (capped only by accumulativeAlpha's internal `min(...,1.0)`) is written to A; no glow or extra tonemap baked into state, keeping the A-write / C-read loop symmetric.
- Canonical 13-binding layout unchanged, `@workgroup_size(16, 16, 1)` kept.
- writeTexture, writeDepthTexture, dataTextureA written every frame; all sampler reads use `textureSampleLevel(..., 0.0)`; no reserved keywords; no extraBuffer usage.
- Engine uniform truth followed: `config = [time, rippleCount, resW, resH]`, ripples = `(x, y, clickTime, _)` (verified against UniformBuffer.ts + other shaders).

## Deviations
1. **accumulativeAlpha's rate is now a constant** (`ACCUM_RATE = 0.5`). The brief requires x to drive the feedback mix, which orphaned the accumulation rate; 0.5 matches the old default so out-of-box behavior is preserved. accumulativeAlpha itself is untouched.
2. **Glow applied to output only, not to accumulation state.** Baking glow into dataTextureA would feed the lift back into the loop (blowout risk) and violate the "never tonemap/clamp state beyond existing caps" caution. The slider still drives a "brightness lift of the accumulated trails" — it lifts the trail signal on screen, exactly 0 at 0.
3. **Depth-aware attenuation kept/extended**: prism spread is attenuated by depth (`mix(1.0, 0.35, depth)`) to honor the `depth-aware` feature tag; depth passthrough write unchanged.
