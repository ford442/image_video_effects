# Batch 22 Notes: directional-blur-wipe

**Agent role:** Algorithmist
**Date:** 2026-07-31

## Lines

- Before: **110** → After: **191** (+81, target +50..+90, final range 160–200 ✅)

## Bugs fixed (Priority 1)

1. **Dead `Split Pos` slider wired.** `split_pos_param` was read and never used — the wipe
   line was pinned to the cursor. Now:
   `p_line = mouse + normal * (split_pos_param - 0.5) * 0.6` (aspect-consistent, offset
   applied along the line's own normal). Default `0.5` → factor `0.0` → `p_line = mouse`,
   bit-identical to pre-upgrade behavior.
2. **Dead `chroma` var put to work.** Previously computed per loop iteration and discarded.
   Now each loop tap accumulates `r` from `sampleUV + dir * chroma` and `b` from
   `sampleUV - dir * chroma` (g stays center), so the per-sample treble-driven chromatic
   offset actually disperses.
3. **Stale header fixed** (comment-only): `Category: post-processing` → `Category: image`.

## Slider map (u.zoom_params, unchanged ids/defaults/order)

| Slot | Param (id) | Default | Drives |
|---|---|---|---|
| x | Split Pos (`split_pos`) | 0.5 | Wipe-line offset along normal, ±0.3 around cursor |
| y | Angle (`angle`) | 0.0 | Blur/wipe axis angle (`angle_param * 6.28` + sprung-y lean) |
| z | Strength (`strength`) | 0.5 | Blur radius (`* 0.05 * depthScatter * bass_env`, + click/spring kick) |
| w | Samples (`samples`) | 0.5 | Tap count (`i32(samples_param * 50.0) + 5`) |

## Techniques added

- **Critically-damped spring wipe** (extraBuffer[133..137]: sprung pos, velocity, last
  time; single-thread update at invocation (0,0); seeded at cursor on first touch;
  omega = 10.0). The `(mouse.y - 0.5) * 3.14` angle lean rides the SPRUNG y. Spring
  velocity magnitude (`springEnergy`) adds a subtle blur-strength swell while settling.
- **Click wipe flashes:** `ripples[]` loop guarded by `min(u32(u.config.y), 50u)`,
  ~1.0s decay. Each live ripple near the line (normal-distance proximity) boosts a
  widening glow band hugging the wipe line (blur side) plus a faint clean-side echo,
  and `clickKick` locally multiplies blur strength around the click point.
- extraBuffer writes: indices **133–137 only** (within [133..255]; [0..4] reserved,
  [5..132] engine FFT untouched).

## VERBATIM preserved

- `bass_env` helper (character-for-character)
- angle/dir/normal construction (`angle_param * 6.28 + (mouse.y - 0.5) * 3.14`)
- `dist < 0.0` branch split (clean side passthrough)
- `num_samples` loop structure (same `t`, `offset`, `chroma` computations, clamp pattern)
- Per-channel 1.1/0.9 dispersion taps (`rUV`/`bUV` + 0.3 mixes)
- `line_width = 0.005` mids/treble line-glow block (ripple flash is an additional block after it)
- Bass brightness pulse line, depth/depthScatter, all three texture stores, binding layout,
  `@workgroup_size(16, 16, 1)`, all `textureSampleLevel(..., 0.0)` reads

## JSON changes

`shader_definitions/image/directional-blur-wipe.json`: added **only** `updatedParams`
(4 entries, index 0–3, exact names/defaults/min/max/step from the brief) and
`"updated": true`. No other keys touched. Validated with `json.load`.

## Deviations

- None from mandatory requirements. Spring constant chosen as omega = 10.0
  (kinetic-dispersion uses 8.0; 10.0 gives a slightly snappier wipe sweep).

## Gate result

```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/directional-blur-wipe.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0
extraBuffer violations: 0
✅ naga OK, bindgroup compatible
```

GREEN — 0 warnings, 0 extraBuffer violations.
