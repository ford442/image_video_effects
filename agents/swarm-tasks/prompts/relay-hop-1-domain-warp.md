# Relay Hop 1 — Domain Warp (`gen-relay-psychedelia`)

## Metadata
- **Shader ID**: gen-relay-psychedelia
- **Hop**: 1
- **CHUNK**: `domain-warp`
- **Agent Role**: Domain-Warp Specialist
- **Status**: pending
- **Protocol**: [`agents/RELAY_PROTOCOL.md`](../../RELAY_PROTOCOL.md)

## Immutable Rules
1. Edit **only** `applyDomainWarp` inside the `CHUNK: domain-warp` block.
2. Do NOT modify bindings, `Uniforms`, `main()`, utilities, or other CHUNKs.
3. Function signature stays: `fn applyDomainWarp(p: vec2<f32>, time: f32, strength: f32) -> vec2<f32>`
4. Max **6 fbm octaves per call site** (framerate budget).
5. Return bounded coordinates — avoid `p * 1000` blowups.
6. Run gate before marking complete:
   ```bash
   python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-relay-psychedelia.wgsl
   ```

## Task

Upgrade the spine warp to **recursive domain warping**:

```
q = p + strength * fbm(p)
r = p + strength * fbm(q)
s = p + strength * fbm(r)
return s  // (or blend organicDrift into the chain)
```

Goals:
- Organic flowing motion — Inigo Quilez-style domain warp
- Mouse bias optional: pull warp toward `(u.zoom_config.yz - 0.5) * 2` when `u.zoom_config.w > 0.5`
- `strength` param already scales warp — respect it, don't bypass
- Visible improvement over spine at default params (Warp Depth ~0.55)

## Reference pattern (from `WGSL_BUILTINS_GENERATIVE.md`)

```wgsl
fn domainWarp(p: vec2<f32>, strength: f32, octaves: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, octaves), fbm(p + vec2<f32>(5.2, 1.3), octaves));
    return p + strength * q;
}
```

Chain 2–3 levels. You may keep `organicDrift` as a pre-warp or post-warp layer.

## Current CHUNK (replace body only)

```wgsl
fn applyDomainWarp(p: vec2<f32>, time: f32, strength: f32) -> vec2<f32> {
    // Spine: single-level warp. Hop 1: recursive fbm(p + fbm(p + fbm(p))).
    let drift = organicDrift(p, time, 6.0) * strength;
    let q = p + drift;
    let field = fbm(q * 1.8 + vec2<f32>(time * 0.04, -time * 0.03), 3);
    return q + vec2<f32>(field - 0.5, fbm(q * 2.1 - time * 0.02, 2) - 0.5) * strength * 0.35;
}
```

## On completion

1. Add comment: `// OWNER: <agent> <date>`
2. Set `relay-queue.json` hop 1 `status` → `completed`, hop 2 → `pending`
3. Do not touch hop 2+ chunks
