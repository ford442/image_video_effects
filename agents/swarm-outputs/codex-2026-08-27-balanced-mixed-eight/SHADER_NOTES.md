# Balanced Mixed Eight — Shader Notes — 2026-08-27

## Feedback ownership

- `alpha-hdr-bloom-chain`: A/C = raw HDR RGB, overexposure.
- `magma-fissure`: A/C = heat, zero, zero, one.
- `paper-burn`: A/C = burn state, zero, zero, one.
- `cyber-hex-armor`: A/C = final ACES display RGBA.
- `pp-chromatic`: A/C = final ACES display RGBA.
- `sequin-flip`: A/C = final ACES display RGBA.
- `rorschach-inkblot`: A/C = final ACES display RGBA with ink coverage alpha.
- `alpha-depth-fog-volumetric`: A/C = final ACES fogged display RGB and
  Beer-Lambert transmittance.

All C reads are exact and coordinate-bounded. All eight write A and never write
B or `extraBuffer`.

## Control liveness

Each shader reads `zoom_params.x`, `.y`, `.z`, and `.w` directly. In
particular, Bloom Saturation controls luma-to-color reconstruction, Paper Char
Width controls the ember/char/hole bands, and Fog Color Temperature controls a
continuous warm-neutral-cool scattering palette.

## Interaction and audio

Each effect uses mouse position even when not held, increases or changes the
local response while held, and scans at most 50 ripple records. Click fronts
require non-negative age and expire within a shader-specific finite lifetime.
Bass, mids, and treble have separate roles in geometry or propagation,
emission or motion, and spectral detail or sparkle.
