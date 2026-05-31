# spec-blackbody-thermal — Kimi Notes

## Changes Made
- Added audio reactivity: bass drives thermal intensity, mids temperature oscillation, treble mouse heat.
- Added chromatic temperature gradient: cooler=blue-shifted, hotter=red-shifted.
- Added temporal ember persistence via `dataTextureC` blend for glowing decay.
- Added `writeDepthTexture` output (was missing entirely).
- Fixed `vec3(0.0)` -> `vec3<f32>(0.0)` on line 43.

## Wow Factor
- Audio makes embers pulse and flicker with the music.
- Chromatic gradient gives physically-grounded temperature color shifts.
- Temporal persistence lets hot spots glow and fade organically.

## Risks for Claude Polish
- `blackbodyColor` called 3x per pixel (thermal + persistentEmber + glow loop); expensive.
- Ember persistence uses alpha channel as temperature proxy; verify scale.
- Depth write was missing; now added but may need depth-aware values.
