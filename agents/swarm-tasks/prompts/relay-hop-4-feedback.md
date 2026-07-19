# Relay Hop 4 — Temporal Feedback (`gen-relay-psychedelia`)

## Metadata
- **Shader ID**: gen-relay-psychedelia
- **Hop**: 4
- **CHUNK**: `temporal-feedback`
- **Agent Role**: Feedback Specialist
- **Status**: pending
- **Protocol**: [`agents/RELAY_PROTOCOL.md`](../../RELAY_PROTOCOL.md)

## Immutable Rules
1. Edit **only** `applyTemporalFeedback` inside the `CHUNK: temporal-feedback` block.
2. Do NOT modify bindings, `Uniforms`, `main()`, utilities, or other CHUNKs.
3. Function signature stays:
   `fn applyTemporalFeedback(color: vec3<f32>, prevRgb: vec3<f32>, strength: f32, bass: f32) -> vec3<f32>`
4. **Stability is non-negotiable**: effective history gain must stay < 1.0 in
   every channel or the frame saturates to white within seconds. Keep
   `decay * mixWeight` comfortably below 1 (≤ ~0.92 total).
5. History arrives pre-sampled at the current pixel (`main()` is frozen), so
   UV-warped history sampling is **out of scope for this hop** — sculpt the
   trail in color space instead. If you believe warped-history sampling is
   essential, flag it for human approval; do not edit `main()` yourself.
6. No new hue sources — tint by *rotating between existing channels* of
   `prevRgb`/`color`, don't introduce fresh RGB constants beyond subtle decay tints.
7. Run gate before marking complete:
   ```bash
   python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-relay-psychedelia.wgsl
   ```

## Task

Upgrade the flat `mix(color, prev * 0.94, fb)` into expressive **echo trails**:

- **Luma-shaped persistence**: bright pixels persist longer than dark ones —
  e.g. scale decay by `smoothstep` over `luma(prevRgb)` so highlights streak
  and shadows clear fast (keeps the field legible).
- **Chromatic decay**: decay each channel slightly differently
  (e.g. `vec3(0.90, 0.93, 0.95)`) so trails shift hue as they fade —
  classic psychedelic afterimage.
- **Bass pump**: `bass` (plasmaBuffer x) already arrives — let it push the
  feedback mix up transiently, clamped so rule 4 still holds.
- Use `max()`-style blending or soft-max for the brightest trails if plain
  `mix` looks muddy — but verify stability after 60s.

Goals:
- Obvious flowing trails at Trail Echo ≥ 0.5, near-clean image at 0
- No white-out or gray mud after running 60+ seconds
- Trails inherit and shift the palette's hues, not desaturate them

## On completion

1. Add comment: `// OWNER: <agent> <date>`
2. Set `relay-queue.json` hop 4 `status` → `completed`, hop 5 → `pending`
3. Do not touch hop 5+ chunks
