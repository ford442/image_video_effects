# Batch 22 Notes: quantum-cursor

**Agent:** Kimi swarm agent (Visualist role)
**Date:** 2026-07-31
**Shader:** `public/shaders/quantum-cursor.wgsl`

## Lines

- Before: 107 → After: 177 (+70, target +50..+90 ✅, within 157–197 band)

## Slider map (unchanged ids/defaults/min/max/step — preset contract kept)

| index | zoom_params | id | name | default | drives |
|---|---|---|---|---|---|
| 0 | .x | radius | Field Radius | 0.3 | field radius `mix(0.05, 0.5, x)` + bass pulse |
| 1 | .y | mosaic_size | Block Size | 0.5 | mosaic block scale `mix(50.0, 5.0, y)` |
| 2 | .z | aberration | Aberration | 0.3 | chromatic r/b channel offset `z * 0.05` |
| 3 | .w | chaos | Chaos | 0.2 | base chaos level (audio-modulated), gates shuffle/invert |

## Techniques applied (brief priorities)

1. **Spring-damper field center (priority 1):** critically-damped spring
   (omega=14.0) in `extraBuffer[133..138]` = [posX, posY, velX, velY, prevTime, initFlag].
   Only invocation (0,0) integrates; all invocations read center. Raw mouse
   (`u.zoom_config.yz`) stays the spring target; `mouse` is now the trailing
   spring center. dt clamped to 0.1s. First frame snaps to cursor (init flag).
2. **Click decoherence bursts (priority 2):** ripple loop guarded by
   `min(u32(u.config.y), 50u)`. Each live ripple (age in (0, 1.2s)) adds a
   decaying `+0.5` chaos bump with ~0.3 radius smoothstep falloff and linear
   1.2s fade → local reality flicker via the existing shuffle/invert machinery.
   Bonus: expanding decoherence ring (`age * 0.35` radius, 0.04 band) tinted
   quantum-cyan, added inside the field mask.
3. **Per-block FFT voices (priority 3):** jitter amplitude multiplied by
   `(1.0 + plasmaBuffer[(u32(blockHash * 8.0) % 8u) + 1u].x * 0.5)` so each
   block vibrates to its own FFT bin.
4. **Stale comment fix (comment-only):** `config.y = RippleCount`,
   `zoom_config.w = MouseDown`, zoom_params annotated with real param roles.
5. **Spring-lag rim shimmer (visualist garnish):** field boundary
   (`mask*(1-mask)*4`) glows cyan proportional to spring velocity — motion smear
   feedback while the center trails the cursor.

## VERBATIM-preserved structures

- `hash12` helper (exact)
- Mosaic `blockUV` construction (`floor(uv*blocks)/blocks + 0.5/blocks`)
- Chaos jitter core `(blockHash - 0.5) * 0.1 * chaos` (extended only by `* (1.0 + blockVoice)`)
- Branchless shuffle/invert machinery: `activeChaos` / `shuffle1` / `shuffle2` /
  `doInvert` / `shuffled1` / `shuffled2` / `anyShuffle` / `chosenShuffle` (select) /
  `afterShuffle` (mix) / `inverted` / final `colEffect` mix — all exact
- `mask = smoothstep(radius, radius * 0.8, dist)` — exact
- Aberration rUV/bUV clamped-sample construction — exact
- 13-binding layout, `@workgroup_size(16, 16, 1)`, all three textureStore calls
  (writeTexture, dataTextureA=DISPLAY color, writeDepthTexture) every frame
- `textureSampleLevel(..., 0.0)` for all sampler reads

## JSON changes

- `shader_definitions/interactive-mouse/quantum-cursor.json`: added ONLY
  `updatedParams` (index 0–3, exact names/defaults/min/max/step from brief) and
  `"updated": true`. Existing `params` (ids/defaults) untouched. JSON parses OK.

## Deviations from brief

- None material. The two small garnish additions (decoherence ring highlight,
  spring-lag rim shimmer) are additive-only output terms layered on top of the
  verbatim `finalRGB` mix; they don't touch any preserved structure. `chaos`
  became `var` (was `let`) solely to add the click-decoherence bump — formula
  and range identical.

## Gate result

```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/quantum-cursor.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ public/shaders/quantum-cursor.wgsl — naga OK, bindgroup compatible
```

GREEN — 0 warnings, 0 extraBuffer violations (writes only [133..138]).
