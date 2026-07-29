# Agent Notes — cursor-aura (Batch 17, role: Optimizer)

**Date:** 2026-07-30
**Files touched:** `public/shaders/cursor-aura.wgsl`, `shader_definitions/interactive-mouse/cursor-aura.json` (nothing else)

## Line count

- Before: 97 lines → After: 168 lines (**+71**, inside the +50..+90 target band)

## What each slider now drives (priority 1: honest rewiring)

| Slider | id | Before (LIE) | After (honest) |
|---|---|---|---|
| x — Aura Size | `size` | aura radius (bass-boosted) | unchanged: aura radius, now swollen by the *smoothed* bass envelope |
| y — Glow Intensity | `intensity` | glow strength (mids-lifted) | unchanged role: glow strength; also scales click-ring + spectral tint |
| z — Edge Softness | `softness` | secretly the base↔effect **mix** | now the aura edge feather width: `mix(0.01, 0.20, z)` in the mask smoothstep |
| w — Color Hue | `hue` | secretly the **pulse speed**, hue hardcoded blue | now hue-rotates the glow color via IQ cosine palette `0.5 + 0.5*cos(2π*(w + (0, 0.25, 0.5)))`; **w = 0.5 reproduces the original (0, 0.5, 1) blue exactly** |

Old mislabeled behaviors moved to fixed constants: `mixVal = 0.5`, `pulseSpeed = 2.5 * (1.0 + treble * 0.1)` (≈ the old default at w=0.5).

IDs/names/defaults/min/max untouched — saved-preset contract preserved. `updatedParams` (index 0–3, step 0.01) and `"updated": true` added to the JSON verbatim from the brief; existing `params` untouched.

## Techniques implemented

1. **Mislabeled-slider rewiring** — z → feather width, w → cosine-palette hue (default 0.5 = original blue), stale uniform comments fixed (`config.y` = RippleCount, `zoom_config.w` = MouseDown).
2. **Click aura rings** — ripple loop guarded by `min(u32(u.config.y), 50u)`; each live ripple (age < 1.5 s) spawns an expanding secondary aura ring at the click point (`radius = age*0.35`, quadratic decay, widening band), tinted by the hue slider. `mouseDown` (`zoom_config.w`) flares glow/ring strength via `downBoost`.
3. **Directional spectral edges** — per-bin mids `plasmaBuffer[2..5].y` weight the horizontal/vertical edge axes separately (`midL/midR` → L–R tap diff, `midT/midB` → T–B tap diff), plus a spectral tint; blended 60/40 with the verbatim `edges` term so the original look survives at silence.
4. Smoothed bass envelope in `extraBuffer[133]` (only slot used — inside [133..255]) driving radius/glow/ring instead of raw bass (less flicker).
5. Small extras for line/quality budget: treble shimmer fill inside the aura, hue-tinted ring with white core retained.

## Contract compliance

- 13-binding canonical layout unchanged (no binding 13); `@workgroup_size(16, 16, 1)` kept.
- `writeTexture`, `writeDepthTexture`, `dataTextureA` written every frame; `dataTextureA` stays DISPLAY color.
- All sampler reads use `textureSampleLevel(..., 0.0)`; no storage texture loads added.
- No reserved keywords as identifiers; extraBuffer write only at index 133.
- **CAUTION honored:** the 4-tap edge kernel (4 tap samples + `let edges = abs(left - right) + abs(top - bottom);`) and the pulse-radius sinusoid `let currentRadius = max(radius + sin(time * pulseSpeed) * 0.02 * (1.0 + bass), 0.001);` preserved verbatim; ring alpha may still exceed 1 pre-clamp and the final `clamp(0,1)` is kept.

## Deviations

- None from the brief. `naga` WAS available in this VM (brief warned it might not be) — full validation ran.

## Gate result

```
WGSL PRECOMMIT GATE
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | extraBuffer violations: 0
✅ public/shaders/cursor-aura.wgsl — naga OK, bindgroup compatible
```

JSON also validated with `json.load` — parses cleanly.
