# Batch 3A Chromatic Upgrade — 2026-06-06

## Shaders Upgraded (4/4)

| Shader | Change | dataTextureA | Notes |
|--------|--------|--------------|-------|
| gen-translucent-nebula | Added chromatic before ACES, moved depth read before chromatic block | Stores pre-ACES color (temporal feedback) | 292L |
| gen-alpha-aurora | Added chromatic before ACES, moved depth read before chromatic block | Stores pre-ACES color (temporal feedback) | 302L |
| gen-ghost-flame | Added chromatic before ACES, moved depth read before chromatic block; `let finalColor` → `var finalColor` | Stores simulation state (temp, fuel, vel, age) | 323L |
| gen-prismatic-crystal-growth | Added chromatic before ACES, moved raymarch depth before chromatic block | Stores state (thickness, growth, 0, alpha) | 356L |

## Chromatic Pattern Used

```wgsl
let caStr = 0.003 * (1.0 + bass) + depthVal * 0.001;
color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);
```

- For simulation shaders (ghost-flame, crystal-growth): chromatic applied only to writeTexture color, dataTextureA state unchanged.
- For temporal-feedback shaders (nebula, aurora): dataTextureA stores pre-ACES color; chromatic + ACES applied only to writeTexture output.

## Validation Results

- **naga 29.0.3**: All 4 shaders pass ✅
- **generate_shader_lists.js**: Pass ✅
- **check_duplicates.js**: Pass ✅ (1126 unique IDs, 0 duplicates)
- **buildMultipassRegistry.js**: Pass ✅ (25 entries)

## Metadata Updates

All 4 JSON definitions updated with `chromatic-aberration` feature flag.

## Unblocks

Batch 3A completion unblocks Claude **3E polish pass** on E1–E3.
