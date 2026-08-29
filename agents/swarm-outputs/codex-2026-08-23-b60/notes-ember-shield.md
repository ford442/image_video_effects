# Batch 60 notes — ember-drift-dissolve + energy-shield

**Branch:** `upgrade/batch-60-heat-echo-elastic`  
**Date:** 2026-08-23  
**Trackers:** #529 ember-drift-dissolve · #530 energy-shield

## Files changed

- `public/shaders/ember-drift-dissolve.wgsl`
- `shader_definitions/image/ember-drift-dissolve.json`
- `public/shaders/energy-shield.wgsl`
- `shader_definitions/interactive-mouse/energy-shield.json`
- `swarm-outputs/codex-2026-08-23-b60/notes-ember-shield.md` (this file)

## Critical fixes

### ember-drift-dissolve (#529)

| Issue | Fix |
|-------|-----|
| Filtered `textureSampleLevel(dataTextureC, …)` for prev + advection | Exact `textureLoad` at `pixel`; advected sample via `round(prevUV * res)` clamped to `[0, res-1]` then `textureLoad` |
| Depth also filtered | `textureLoad(readDepthTexture, pixel, 0)` |
| No held furnace | `u.zoom_config.w > 0.5` → stronger rise, denser birth, white-hot core under cursor |
| Flat orange palette | White-hot → amber → ash ramp; secondary ash-wisp crackle |
| No display tonemap | `acesToneMap` on `writeTexture` RGB only |
| A state risk | A packing left raw — never tonemapped |

### energy-shield (#530)

| Issue | Fix |
|-------|-----|
| Uncapped `u32(u.config.y)` ripple loop | `min(u32(u.config.y), 50u)` |
| Filtered C trail `textureSampleLevel` | Exact `textureLoad(dataTextureC, pixel, 0)` for trail `.r` |
| Flat cyan-only grid | Oil-slick iridescent hex edges (`cos` phase film) |
| Weak Fresnel | Stronger rim (`pow` 2.2, higher amount; held bumps further) |
| No held response | Held scales hex denser (~1.35×) + sharpens edge thresholds |
| No real audio | `plasmaBuffer[0]` bass pulse / mid film / treble edge crackle |
| Junk header ("COPY PASTE THIS HEADER") | Proper Batch 60 header + A packing docs |
| Alpha = input alpha only | Semantic alpha from trail + glow + fresnel + impact |
| Sparse JSON | Full description, features, tags, aligned `updatedParams` |

## A packing

### ember-drift-dissolve

```
dataTextureA = (age, lateral, intensity, glow)
```

- Engine copies A → C between frames.
- Advection reads C at rounded UV texel — simulation state, **never** ACES'd.
- Display RGB is ACES'd; semantic alpha from glow/intensity/furnace.

### energy-shield

```
dataTextureA.r = trail activation (persistent shield energy)  ← primary
dataTextureA.g = mouse intensity
dataTextureA.b = impact flare residual
dataTextureA.a = semantic activation mirror
```

- Trail persistence: `newTrail = max(prev.r * decay, activation)`.
- Display RGB is ACES'd; A channels stay linear activation state.

## Contract checklist (both)

- Source `params` ids/names/defaults/min/max preserved exactly (ember non-0–1 ranges kept).
- `updatedParams` aligned 1:1 with `params`.
- 13 bindings, `@workgroup_size(16, 16, 1)`, unused B, no `extraBuffer` writes.
- Click loops: `min(u32(u.config.y), 50u)`.
- Held via `u.zoom_config.w > 0.5`.
- Audio: `plasmaBuffer[0].xyz` (+ ember bins 1–8 for band crackle).
- Exact `textureLoad` for C state/advection and depth.
- Structural validation local; visual QA needs a real GPU.
