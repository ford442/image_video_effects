# gen-abyssal-quantum-leviathan-skeleton — Upgrade Notes

**Batch:** 3B
**Agent:** Kimiclaw
**Date:** 2026-06-06

---

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| Lines | 203 | 209 |
| ACES | No | No |
| dataTextureA write | No | Yes |
| Chromatic aberration | No | No |
| Temporal (dataTextureC read) | No | Yes |

---

## What Changed

Added temporal plumbing to the leviathan-skeleton shader:
- Sample `dataTextureC` using a **screen-space UV** (`vec2<f32>(coords) / vec2<f32>(dimensions)`).
- Apply a 0.96-decay temporal blend: `mix(prev.rgb * 0.96, color, 0.25)`.
- Write the blended result to `dataTextureA`.
- The JSON `features` array was **previously empty**; it now contains `["temporal"]`.

---

## Parameters

| # | Name | WGSL Mapping | Default | Range |
|---|------|-------------|---------|-------|
| 1 | Bone Density | `zoom_params.x` | 0.5 | 0.1 – 1 |
| 2 | Marrow Glow | `zoom_params.y` | 0.8 | 0 – 2 |
| 3 | Current Turbulence | `zoom_params.z` | 0.6 | 0 – 1.5 |
| 4 | Audio Reactivity | `zoom_params.w` | 1 | 0 – 2 |

---

## Validation

```bash
naga public/shaders/gen-abyssal-quantum-leviathan-skeleton.wgsl
```

Result: ✅ Pass

---

## Audio / Mouse / Depth

- **Audio:** `u.config.y` (click count) multiplied by `zoom_params.w` drives `audio_react`, which bulges ribs and modulates the marrow glow pulse inside bones. No `plasmaBuffer` reads.
- **Mouse:** Yes. Mouse position from `zoom_config.yz` creates a gravity well that pulls skeleton vertices toward the cursor via `smoothstep` blend.
- **Depth:** No `readDepthTexture` sampling.

---

## Gotchas

- This was the **only shader in the batch whose JSON previously had an empty `features` array**.
- Uses centered raymarching UV; agent added a separate **screen-space `dataUV`** for the `dataTextureC` sample.
