# Relay Hop 2 — Symmetry Fold (`gen-relay-psychedelia`)

## Metadata
- **Shader ID**: gen-relay-psychedelia
- **Hop**: 2
- **CHUNK**: `symmetry-fold`
- **Agent Role**: Symmetry / Kaleidoscope Specialist
- **Status**: completed (cursor-hop-2 2026-07-19)
- **Protocol**: [`agents/RELAY_PROTOCOL.md`](../../RELAY_PROTOCOL.md)

## Immutable Rules
1. Edit **only** `applySymmetry` inside the `CHUNK: symmetry-fold` block.
2. Do NOT modify bindings, `Uniforms`, `main()`, utilities, or other CHUNKs.
3. Function signature stays: `fn applySymmetry(p: vec2<f32>) -> vec2<f32>`
4. **No RGB** — return folded `vec2<f32>` coordinates only.
5. Return bounded coordinates — polar fold preserves radius; avoid post-fold scaling blowups.
6. Run gate before marking complete:
   ```bash
   python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-relay-psychedelia.wgsl
   ```

## Task

Apply a **polar kaleidoscope fold** on warped UV before `sampleField`:

```
p → slow time rotation → optional mouse-center offset → N-fold polar mirror → return
```

Goals:
- Fixed **6-fold** mandala symmetry (hexagonal kaleidoscope)
- Slow time spin so the fold pattern breathes (`u.config.x`)
- Optional mouse bias: shift fold origin toward `(u.zoom_config.yz - 0.5) * 2` when `u.zoom_config.w > 0.5`
- Visible improvement over spine identity at default params
- Do **not** steal `zoom_params` — those belong to warp / palette / feedback hops

## Reference pattern (from `mouse-kaleidoscope-tunnel.wgsl`)

```wgsl
fn kaleidoscope(uv: vec2<f32>, segments: f32) -> vec2<f32> {
  let angle = atan2(uv.y, uv.x);
  let radius = length(uv);
  let segmentAngle = TAU / segments;
  let mirroredAngle = abs(fract(angle / segmentAngle + 0.5) - 0.5) * segmentAngle;
  return vec2<f32>(cos(mirroredAngle), sin(mirroredAngle)) * radius;
}
```

## Current CHUNK (replace body only)

```wgsl
fn applySymmetry(p: vec2<f32>) -> vec2<f32> {
    // Spine: identity. Hop 2: polar/kaleidoscope fold before field sampling.
    return p;
}
```

## On completion

1. Add comment: `// OWNER: <agent> <date>`
2. Set `relay-queue.json` hop 2 `status` → `completed`, hop 3 → `pending`
3. Do not touch hop 3+ chunks
