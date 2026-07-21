# Relay Hop 4 — Temporal Feedback (`gen-relay-psychedelia`)

## Metadata
- **Shader ID**: gen-relay-psychedelia
- **Hop**: 4
- **CHUNK**: `temporal-feedback`
- **Agent Role**: Echo / Trail Specialist
- **Status**: completed (cursor-hop-4 2026-07-19)
- **Protocol**: [`agents/RELAY_PROTOCOL.md`](../../RELAY_PROTOCOL.md)

## Immutable Rules
1. Edit **only** `applyTemporalFeedback` inside the `CHUNK: temporal-feedback` block.
2. Do NOT modify bindings, `Uniforms`, utilities, or other CHUNKs.
3. **No new hue sources** — blend/mix passed `color` with history RGB only.
4. **Decay must stay < 1.0** — feedback stable after ~30s (protocol checklist).
5. `zoom_params.w` = Trail Echo — respect the `strength` argument (already scaled in `main()`).
6. Run gate before marking complete:
   ```bash
   python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-relay-psychedelia.wgsl
   ```

## Task

Upgrade spine feedback to **self-advecting echo trails** via `dataTextureC`:

```
uv01 → organicDrift UV warp → bilinear sample dataTextureC → decay → luminance-weighted mix
```

Goals:
- **UV warp** on history sample so trails smear organically (not static stacking)
- **Decay** mapped from Trail Echo slider + subtle bass lift
- **Dual-tap** bilinear sample for softer phosphor echo
- Luminance-weighted mix so bright regions leave longer trails
- Use `textureSampleLevel(dataTextureC, u_sampler, …)` for filtered history reads

## Wiring note

`main()` passes `coord`, `res`, `strength`, `bass`, `time` instead of pre-sampled `prevRgb` so the chunk owns the warped history fetch. No other `main()` logic changes.

## Reference pattern (from `gen-acid-lissajous.wgsl`)

```wgsl
let drift = organicDrift(uv01, time, 5.0) * (0.015 + bass * 0.015);
let fbUV = clamp(uv01 + drift, vec2<f32>(0.0), vec2<f32>(1.0));
let prev = textureSampleLevel(dataTextureC, u_sampler, fbUV, 0.0).rgb;
let fbMix = feedback * 0.82;
let decay = 0.88 + feedback * 0.11;
totalColor = mix(totalColor, prev * decay, fbMix);
```

## Current CHUNK (replace body + signature)

```wgsl
fn applyTemporalFeedback(color: vec3<f32>, prevRgb: vec3<f32>, strength: f32, bass: f32) -> vec3<f32> {
    let fb = clamp(strength + bass * 0.04, 0.0, 0.85);
    let decayed = prevRgb * 0.94;
    return mix(color, decayed, fb);
}
```

## On completion

1. Add comment: `// OWNER: <agent> <date>`
2. Set `relay-queue.json` hop 4 `status` → `completed`, hop 5 → `pending`
3. Do not touch hop 5+ chunks
