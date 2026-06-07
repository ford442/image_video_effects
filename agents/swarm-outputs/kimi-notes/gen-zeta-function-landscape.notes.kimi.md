# gen-zeta-function-landscape — Kimi Notes

## Changes
- Temporal term evolution: audio (`treble`) dynamically adjusts zeta series term count (50–200).
- Chromatic aberration on zero-proximity valleys: near zeros shift hue toward cyan/purple.
- Depth pass-through with height-based alpha: valleys are more transparent, ridges opaque.
- Temporal smoothing: `dataTextureC` blends 8–10% previous frame for landscape stability.
- `dataTextureA` stores frame for downstream shaders.

## Wow-Factor
- Riemann zeta critical line becomes a living landscape — zeros glow with chromatic halos.
- Audio-driven term count visibly changes precision: low = smooth hills, high = jagged ridges.

## Risks
- Term count up to 200 in a loop is expensive; `treble` spike could cause frame drops.
- `zetaApprox` naive summation loses precision for large `|t|`; acceptable for visual use.
