# crt-clear-zone v2 Upgrade Notes

## Overview
Upgraded from 92 lines to 134 lines. Added accurate CRT electron beam simulation with Gaussian spot spread, inline shadow mask, phosphor decay via temporal feedback through `dataTextureC`, barrel distortion with proper corner darkening, per-RGB chromatic aberration, moiré patterns on shadow mask, and ACES tone mapping.

## Algorithmist Changes
- Added `gaussian_spread(uv, res, spread)` — 5-tap cross-shaped blur simulating electron beam spot spread
- Added `shadow_mask(uv, res)` — inline slot shadow mask with RGB triads at subpixel scale
- Added `barrel_distort(uv, amt)` with r² and r⁴ terms for accurate barrel distortion
- Phosphor decay reads previous frame from `dataTextureC` and blends with decay factor 0.78
- Moiré pattern on shadow mask via `sin(x) * sin(y)` interference

## Visualist Changes
- Per-RGB channel chromatic aberration with separate red/blue offsets scaled by distortion
- Proper corner darkening via `pow(max(corner * 16.0, 0.001), 0.18 + distortion * 0.08)`
- Inline shadow mask RGB triads at `res * 0.5` frequency
- ACES tone mapping on final color
- Scanline intensity audio-reactive with bass modulation

## Interactivist Changes
- Bass drives scanline intensity: `scanlineInt * (1.0 + bass * 0.25 + mids * 0.12)`
- Bass also drives barrel warp: `distortion * (1.0 + bass * 0.15)`
- Mouse creates clear zone with soft falloff: `smoothstep(clearRadius, max(clearRadius - 0.06, 0.001), dist)`
- Depth controls phosphor bloom spread: `spread = 0.8 + depth * 1.5`

## Alpha Strategy
- `alpha = clamp(clearMask * 0.95 + (1.0 - clearMask) * (luma * 0.45 + f32(in_bounds) * 0.2) + edge * 0.35 + treble * 0.04, 0.0, 1.0)`
- 1.0 inside clear zone (via `clearMask * 0.95`), fades to ~0.5 in distorted periphery
- Never uses `vec4(..., 1.0)`

## Parameter Changes
- No parameter ID changes; same 4 params with refined ranges and audio reactivity

## Validation
- naga: PASS
- workgroup_size: (16, 16, 1) — upgraded from original (8, 8, 1)
