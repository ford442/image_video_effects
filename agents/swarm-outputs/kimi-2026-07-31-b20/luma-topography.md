# Batch 20 Notes: luma-topography

**Agent:** Kimi (Visualist) — 2026-07-31
**Brief:** `swarm-tasks/kimi-briefs-2026-07-31-b20/luma-topography.md`

## Line counts

- **Before:** 103 lines
- **After:** 170 lines (+67, target was +50..+90 / 153–193 — inside range)

## Slider mapping (saved-preset contract — ids/names/defaults unchanged)

| Index | JSON id    | Name           | Default | WGSL wiring (`u.zoom_params`) | Drives |
|-------|------------|----------------|---------|-------------------------------|--------|
| 0 | `height`    | Relief Height  | 0.5 | `.x` | `heightScale = x*20 + 1` — terrain normal slope magnitude |
| 1 | `intensity` | Light Intensity| 0.8 | `.y` | `lightIntensity = y*2*(1+bass*0.4)` — diff/spec strength |
| 2 | `shininess` | Shininess      | 0.4 | `.z` | `shininess = z*32 + 1` — Blinn-Phong spec exponent (mouse + click lights) |
| 3 | `ambient`   | Ambient Light  | 0.2 | `.w` | `ambient` — flat ambient term in litColor |

All 4 were already honestly wired; mapping kept EXACTLY.

## Techniques implemented

1. **Critically-damped spring on the light source (priority 1).** Raw mouse (`u.zoom_config.yz`) is the spring goal; the light position is integrated with stiffness k=48, damping c=2√k (critical), dt clamped to [1e-4, 0.05]. State in `extraBuffer[133..136]` (pos.xy, vel.xy) plus `[137]` last-time and `[138]` init flag — all inside [133..255]; [0..4] reserved and [5..132] engine FFT untouched. The attenuation falloff is computed from the SPRUNG position (`lightUV`).
2. **Click fill-light flashes.** Loop `u.ripples[]` guarded by `min(u32(u.config.y), 50u)`; each live ripple (age in 0..1.5s) adds a decaying warm point light (`vec3(1.0, 0.75, 0.45)`) on the same Blinn-Phong path (L/H/diff/spec + same attenuation curve), quadratic fade, contributing additively to diffuse and specular (scaled 0.8 in litColor) plus a small alpha energy term.
3. **Depth-aware lighting.** Depth is now sampled BEFORE lighting and biases relief height: `pixelPos3D.z = luma * 0.2 + depth * 0.1` — near geometry catches more specular. The depth read is no longer dead.
4. **Comment fixes (comment-only).** Header `Category: image` → `interactive-mouse`; struct comments corrected to `config.y=RippleCount`, `zoom_params = ReliefHeight/LightIntensity/Shininess/Ambient`; ripples layout documented.

## VERBATIM-preserved structures

- `getLuma` helper (`dot(color, vec3(0.299, 0.587, 0.114))`)
- 2-tap luma gradient normal (lumaRight/lumaTop, dX/dY, `normalize(vec3(-dX*heightScale, -dY*heightScale, 1.0))`)
- Blinn-Phong math: `diff = max(dot(normal, L), 0.0)`, `H = normalize(L + V)`, `spec = pow(max(dot(normal, H), 0.0), shininess)`
- Attenuation curve `1.0 / (1.0 + dist * 5.0)` (same formula, now from sprung pos; click lights reuse it)
- Warm lightColor mids shimmer `vec3(1.0, 0.95 + mids * 0.05, 0.8)`
- All 13 bindings, `@workgroup_size(16, 16, 1)`, `textureSampleLevel(..., 0.0)` sampler reads
- `writeTexture` / `writeDepthTexture` / `dataTextureA` written every frame; `dataTextureA` = DISPLAY color
- Slider ids/names/defaults/min/max and zoom_params mapping order

## JSON changes

`shader_definitions/interactive-mouse/luma-topography.json`: added ONLY `updatedParams` (4 entries, index 0–3, names/defaults/min/max/step exactly per brief) and `"updated": true`. Validated with `json.load`.

## Deviations

- Alpha formula gained a small `clickEnergy` term (`(clickSpecular.r + clickDiffuse.r) * 0.25`) so click flashes read in the alpha channel too; the original spec/diff/colorSample.a/bass terms are unchanged in weight. Alpha was not on the VERBATIM list.
- Spring state uses [137]/[138] (last-time, init flag) in addition to the brief-specified [133..136]; still within the allowed [133..255] window.

## Gate result

```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/luma-topography.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ public/shaders/luma-topography.wgsl — naga OK, bindgroup compatible
```

GREEN on first run — 0 warnings, 0 extraBuffer violations.
