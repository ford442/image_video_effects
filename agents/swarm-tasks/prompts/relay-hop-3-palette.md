# Relay Hop 3 — Palette (`gen-relay-psychedelia`)

## Metadata
- **Shader ID**: gen-relay-psychedelia
- **Hop**: 3
- **CHUNK**: `palette`
- **Agent Role**: Color / Palette Specialist
- **Status**: completed (kimi-hop-3 2026-07-19)
- **Protocol**: [`agents/RELAY_PROTOCOL.md`](../../RELAY_PROTOCOL.md)

## Immutable Rules
1. Edit **only** `sampleField` and `applyPalette` inside the `CHUNK: palette` block.
   A chunk-local helper (e.g. `iqPalette`) may be added between the CHUNK banner and
   the next chunk banner — nothing outside the banners changes.
2. Do NOT modify bindings, `Uniforms`, `main()`, utilities, or other CHUNKs.
3. Function signatures stay:
   - `fn sampleField(p: vec2<f32>, time: f32) -> f32`
   - `fn applyPalette(field: f32, time: f32, saturation: f32, hueShift: f32) -> vec3<f32>`
4. **This is the sole RGB assignment site** — no other chunk may introduce hue sources;
   do not move color assignment elsewhere.
5. Return bounded values (field ~0–1, color ~0–1.2). `finalComposite` is the only
   ACES + exposure site.
6. Max **6 fbm octaves per call site** (framerate budget).
7. `zoom_params.y` (Saturation) and `zoom_params.z` (Hue Shift) belong to this chunk.
   Do **not** steal `zoom_params.x` (warp, hop 1) or `zoom_params.w` (feedback, hop 4).
8. Run gate before marking complete:
   ```bash
   python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-relay-psychedelia.wgsl
   ```

## Task

Upgrade color while respecting the hops before you: hop 1 warps the domain, hop 2 folds
it into a 6-fold mandala — your field + palette must make that structure *sing*.

### `sampleField` — richer scalar field
Keep it bounded (~0–1). Blend the base layer with a finer ridged layer so the
kaleidoscope folds pick up vein-like detail:
- base: `fbm(p * 2.4 + slowDrift, 4)` (existing)
- ridge: `1.0 - abs(2.0 * fbm(p * 4.8 - flow, 3) - 1.0)`, mixed in at ~0.3

### `applyPalette` — hybrid palette (approved direction)
Keep `psychedelicPalette(t)` as the base hue source (the spine was tuned against it),
then layer an **IQ cosine palette** `a + b * cos(TAU * (c * t + d))` sampled at a slower
phase (`t * 0.5 + field * 0.7`) mixed at ~0.45 for interference-band richness.

Must preserve:
- `t` includes the `hueShift` phase offset and slow time scroll (`time * 0.06`)
- final luma↔color mix driven by `saturation` (existing Rec.709 luma pattern)
- output clamped to a bounded range before return

Goals:
- Visible enrichment over spine palette at default params — bands of complementary hue
  riding the warped folds, not mud and not saturated white
- Clean degradation to gray as `saturation` → 0
- `hueShift` still sweeps the full hue circle

## Reference pattern (IQ cosine palette)

```wgsl
fn iqPalette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(TAU * (c * t + d));
}
```

## Current CHUNK (replace bodies only)

```wgsl
fn sampleField(p: vec2<f32>, time: f32) -> f32 {
    return fbm(p * 2.4 + vec2<f32>(sin(time * 0.07), cos(time * 0.05)) * 0.3, 4);
}

fn applyPalette(field: f32, time: f32, saturation: f32, hueShift: f32) -> vec3<f32> {
    let t = field + time * 0.06 + hueShift * TAU;
    var color = psychedelicPalette(t);
    let gray = vec3<f32>(dot(color, vec3<f32>(0.2126, 0.7152, 0.0722)));
    return mix(gray, color, clamp(saturation, 0.0, 1.0));
}
```

## On completion

1. Add comment: `// OWNER: <agent> <date>`
2. Set `relay-queue.json` hop 3 `status` → `completed`, hop 4 → `pending`
3. Do not touch hop 4+ chunks
