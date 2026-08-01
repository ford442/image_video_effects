# Swarm Output: neon-edge-reveal (Batch 20, Algorithmist)

**Date:** 2026-07-31
**Shader:** `public/shaders/neon-edge-reveal.wgsl`
**JSON:** `shader_definitions/visual-effects/neon-edge-reveal.json`

## Line counts

- Before: **104** lines
- After: **177** lines (+73, target +50 to +90, final range 154–194 ✓)

## Slider mapping (old role → new role, saved-preset contract preserved)

| Slider (id/name/default) | Old WGSL role | New WGSL role | Default 0.5 look check |
|---|---|---|---|
| x `param1` "Intensity" 0.5 | revealRadius (`0.2 + x*0.3`) | emission/glow intensity (`x * 2.0`) | = 1.0, same as old `glowIntensity` (z*2.0 @ 0.5) ✓ |
| y `param2` "Speed" 0.5 | edgeBoost (`y*2.0*(1+treble*0.3)`) | neon hue-cycle speed (`mix(0.0, 4.0, y)`) | = 2.0, bit-identical to old hardcoded `time * 2.0` ✓ |
| z `param3` "Scale" 0.5 | glowIntensity (`z * 2.0`) | reveal radius (`0.2 + z*0.3`) | = 0.35, exactly as before ✓ |
| w `param4` "Detail" 0.5 | occlusionBalance (alpha term only) | Sobel smoothstep window `smoothstep(mix(0.10,0.02,w), mix(0.5,0.15,w), edgeStrength)` | = 0.06/0.325 window (brief's formula; old window was 0.05/0.3 — see deviations) |

- Old `edgeBoost` role folded into the emission chain as a constant `1.0` factor; its `(1.0 + treble * 0.3)` audio term moved onto the emission (`trebleBoost`), keeping the default emission chain numerically identical.
- **occlusionBalance choice:** its alpha role *rides along* on w (`glowStrength * 0.1 * detail`), so at default w=0.5 the alpha term is the same 0.05 factor as before. Detail now widens/narrows both the edge window and the glow-driven alpha contribution.

## Techniques implemented

1. **Slider rewiring (priority 1)** — all four generic labels now drive honest, shader-specific constants per the brief mapping; ids/names/defaults/min/max/step untouched.
2. **Hue-preserving soft-knee HDR taming** — `softKnee(c, knee)`: compresses the per-channel max above knee 1.5 via `peak / (1 + max(peak - knee, 0) * 0.5)` (asymptotic cap ~2.0) and rescales the whole vec3 by `mapped/peak`, so hue/saturation survive instead of clipping to white. Tames the old ~19.8x emission peak.
3. **Click flare bursts** — loop over `u.ripples[]` guarded by `min(u32(u.config.y), 50u)`; each ripple adds a local reveal boost at its click point with a ~1.2s linear fade (`clamp(1.0 - age/1.2, 0, 1)`), branchless via `max()` accumulation; flares feed both `glow` and `alpha` through `reveal`.
4. **Spring-damped flashlight** — critically-damped spring (`springStep`, omega=8.0, dt=0.016) on the beam position, state in `extraBuffer[133..136]` (pos.xy, vel.xy) with init flag `[137]`; written only by invocation (0,0); first-contact snap avoids the (0,0) lurch.

## VERBATIM-preserved structures

- 9-tap Sobel: full `vec4` neighbor samples with clamped UVs, luminance gx/gy kernels, `sqrt(gx*gx + gy*gy)` — unchanged.
- Neon palette: `neonColor1 (1.0, 0.0, 0.8)` / `neonColor2 (0.0, 1.0, 1.0)` + `mixFactor = 0.5 + 0.5*sin(... + uv.x*3.0)` + `mix()` cycling — unchanged except the hardcoded `2.0` speed became `hueSpeed` (= 2.0 at default).
- Branchless emission style: `neonColor * glow * edge * 1.0 * glowIntensity * trebleBoost` — single branchless product chain.
- 13-binding canonical layout, `@workgroup_size(16, 16, 1)`, `textureSampleLevel(..., 0.0)`, writes to `writeTexture`/`writeDepthTexture`/`dataTextureA` every frame (dataTextureA stays DISPLAY color).
- No reserved-word identifiers; no binding additions/renumbering; binding 13 not declared.

## JSON changes

- Added **only** `updatedParams` (4 entries, index 0–3, names/defaults/min/max/step exactly per brief) and `"updated": true`. Original `params` block untouched.

## Deviations

- The brief states "default 0.5 = current 0.05/0.3 window", but its own formula `mix(0.10, 0.02, 0.5)` / `mix(0.5, 0.15, 0.5)` yields **0.06 / 0.325**. I used the brief's formula verbatim (authoritative), so the default edge window is negligibly wider than the old 0.05/0.3 — visually indistinguishable, slightly more permissive edges.
- `glowStrength` for the alpha term is now computed from the *tonemapped* emission (post-soft-knee), keeping alpha stable; at default the alpha difference vs. old code is small and intended (blowout no longer inflates alpha).
- Stale header comment fixed: `Category: lighting-effects` → `visual-effects` (comment-only, per CAUTION).

## Gate result

```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/neon-edge-reveal.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ public/shaders/neon-edge-reveal.wgsl — naga OK, bindgroup compatible
```

GREEN — 0 warnings, 0 extraBuffer violations.
