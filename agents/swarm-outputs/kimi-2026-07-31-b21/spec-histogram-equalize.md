# b21 Notes: spec-histogram-equalize (Algorithmist)

**File:** `public/shaders/spec-histogram-equalize.wgsl`
**Lines:** 106 → **163** (+57, target range 156–196 ✓)
**Gate:** `python3 scripts/wgsl_precommit_gate.py --files public/shaders/spec-histogram-equalize.wgsl` → **GREEN** — Passed: 1, Failed: 0, workgroup errors/warnings: 0, extraBuffer violations: 0 (extraBuffer declared but never written).

## Bugs fixed (the "double agent" cleanup)

1. **`clip_limit` was dead** — computed a `clippedCount` that was never used; no clipping ever happened. Now implements the real CLAHE clip-and-redistribute (see math below).
2. **`tile_blend` was dead** — read from `zoom_params.z` and never referenced. Now softens 16×16 tile seams via a 4-tap neighbor blend.
3. **A slot was poisoned** — `dataTextureA` got the debug quad instead of display color. Display color `(outColor, color.a)` now goes to `dataTextureA`; the debug quad `(equalizedLuma, luma, scaleFactor, cdfNorm)` moved to `dataTextureB` (write-only storage, fine).
4. Removed dead `PI`/`TAU` consts and the dead `clippedCount` line.
5. Fixed stale "8x8" doc comment → 16×16 workgroup.

## Slider map (u.zoom_params, ids/defaults unchanged)

| idx | id | WGSL mapping |
|-----|----|--------------|
| x (0) | clip_limit | `clipLimit = mix(1.0, 8.0, x) * (1.0 + bass*0.3)` counts-per-bin clip height; ripples loosen it further. |
| y (1) | strength | `strength` in [0,1]; mouse lens adds `+0.3*smoothstep(0.3,0.0,dist)` → `strengthEff`; drives `scaleMix = mix(1.0, scaleFactor, strengthEff)`. |
| z (2) | tile_blend | `mix(outColor, neighborAvg * scaleMix, tileBlend * 0.5)` — 0 = crisp per-tile, 1 = spatially smoothed. |
| w (3) | color_preserve | `> 0.5` → hue-preserving `color.rgb * scaleMix`; else plain `mix(color.rgb, color.rgb*scaleFactor, strengthEff)`. |

### Clip redistribution math (per thread, one 256-iteration sweep after Phase-2 barrier)

```
clipU   = max(u32(clipLimitEff), 1u)
cdfClip = Σ_{i≤bin} min(count[i], clipU)
excess  = Σ_{all i} (count[i] − min(count[i], clipU))
cdfNorm = (cdfClip + excess * (bin+1) / 256) / 256u      // uniform redistribution
equalizedLuma = clamp(cdfNorm, 0, 1)
```

Chosen mapping documented: existing `mix(1.0, 8.0, x)` clip-height range kept (slider was dead, so any wiring changes the look — that is the fix, not a regression). `clipU` floored at 1 to avoid a degenerate all-zero histogram at slider 0.

## Techniques

- **Real CLAHE clip+redistribute** — single fused 256-bin sweep computes both the clipped prefix sum and total clipped excess; excess redistributed uniformly (`excess*(bin+1)/256`).
- **Tile seam softening** — 4-tap (L/R/U/D, 1 texel, edge-clamped) neighbor average remapped with the same `scaleMix`, blended by `tileBlend * 0.5`.
- **Mouse contrast lens** (flavor, not tagged) — aspect-corrected distance to `zoom_config.yz`, `+0.3` strength boost with smoothstep 0.3-radius falloff.
- **Ripple clip pulses** — loop guarded `min(u32(u.config.y), 50u)`; each live ripple (`age < 1.5s`) loosens the local clip limit via `clipPulse` (smoothstep 0.25-radius × linear fade), popping tonal range at click points.
- **Slot fix** — display color → `dataTextureA`; debug quad → `dataTextureB`.

## Kept verbatim (SACRED)

- Both `workgroupBarrier()` calls remain outside all conditionals; cooperative clear (`atomicStore` strided by `lidx`), atomic vote (`atomicAdd`), luma binning (`0.299/0.587/0.114`, `bin = u32(luma*255.0)`), `totalPixels = 256u`, `@workgroup_size(16, 16, 1)`, and the `inBounds` write guard all structurally unchanged. No new barriers added (clip sweep runs after the Phase-2 barrier; all votes complete).
- Immutable 13-binding layout; `writeTexture`, `writeDepthTexture`, `dataTextureA` written every frame under the inBounds guard; all sampler reads use `textureSampleLevel(..., 0.0)`; no reserved words; extraBuffer untouched.

## JSON changes

`shader_definitions/image/spec-histogram-equalize.json`: added ONLY `"updatedParams"` (indices 0–3, names/defaults/min/max/step verbatim from the brief) and `"updated": true`. Params block untouched — no renames, no re-defaults.

## Deviations

- `equalizedLuma` is now clamped to [0,1] (unclipped CDF could previously leave it ≤1 anyway; redistribution guarantees the same, clamp is belt-and-braces).
- Ripple loop and mouse lens are the brief's optional flavor; both implemented per spec (1.5s fade, 0.3 lens radius).
- `lid` builtin param remains unused (as in the original); naga does not warn.
