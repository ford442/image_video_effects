# digital-lens v2 — Upgrade Notes

## Category
image (unchanged)

## Upgrade Summary
- **Workgroup size**: `(8, 8, 1)` → `(16, 16, 1)`
- **Line count**: 97 → ~130
- **Naga status**: PASS

## Algorithmist Changes
- Replaced simple barrel distortion with full Brown-Conrady lens distortion model (`brownConrady`):
  - Radial coefficients k1, k2.
  - Tangential coefficients p1, p2.
- Added per-RGB channel chromatic aberration with different refractive indices (R: 1.4×, G: 0.7×, B: 1.1×).
- Depth controls chromatic separation magnitude.

## Visualist Changes
- Added lens breathing amplitude driven by bass.
- Added anamorphic squeeze (horizontal stretch).
- Added ACES tone mapping.
- Added procedural film grain (hash-based, time-animated).
- Chromatic aberration now scales with radial distance from center.

## Interactivist Changes
- Bass drives lens breathing amplitude (`breathe = bass × param4 × 0.3`).
- Mouse controls focus point (focusOffset from mouse position).
- Depth controls bokeh/chromatic separation (`depthSep = (1.0 − depth) × 0.5 + 0.5`).

## Alpha Semantics
`alpha = clamp(distortionStrength × chromaticSeparation × (0.3 + depth × 0.7), 0.0, 1.0)`
- Encodes geometric distortion strength, optical dispersion, and depth factor.
- Never hardcoded to 1.0.

## Params (unchanged)
distortion, dispersion, vignette, focus

## Tags Added
anamorphic

## Feature Flags Added
depth-aware, anamorphic
