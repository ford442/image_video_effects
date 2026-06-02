# generative-turing-veins — Kimi Notes

## Changes Made
- Added chromatic activator/inhibitor separation (R=activator green, G=inhibitor pink).
- Added temporal pattern memory via `dataTextureC` blend for organic evolution.
- Added audio-driven feed rate modulation (`bass * sin(time)`).
- Added depth-scaled growth complexity.
- Fixed semantic alpha with `clamp(0.5 + vein_mask * 0.5 + glow * 0.2, 0, 1)`.

## Wow Factor
- Veins organically evolve over time with audio-reactive growth rates.
- Chromatic separation makes activator/inhibitor regions visually distinct.
- Depth drives pattern complexity for layered biological realism.

## Risks for Claude Polish
- `fbm` function uses 6 octaves in activator path; may be expensive on low-end GPUs.
- Temporal blend factor (0.05 + bass*0.02) is subtle; may need tuning for visibility.
- Pattern density may clip at high feed rates; consider clamp in `turing_pattern`.
