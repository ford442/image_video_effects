# tilt-shift v2 — Upgrade Notes

## Category
image (unchanged)

## Upgrade Summary
- **Workgroup size**: `(16, 16, 1)` unchanged
- **Line count**: 99 → ~137
- **Naga status**: PASS

## Algorithmist Changes
- Replaced simple vertical blur gradient with Scheimpflug principle tilt-shift:
  - Tilted focal plane: `tiltedDist = abs(uv.y − focusCenter + tiltAngle × (uv.x − 0.5))`.
  - Circle-of-confusion (CoC) computed from tilt angle and focal plane distance.
  - Depth scales local blur radius for shallow DOF effect.
- Angular blur kernel with golden-angle spiral + tilt angle rotation.

## Visualist Changes
- Added chromatic aberration in out-of-focus areas (RGB channel offset scaled by CoC).
- Added boosted saturation for toy miniature aesthetic.
- Added vignette on blurred regions (edges darken proportionally to blur strength).
- Added ACES tone mapping.

## Interactivist Changes
- Bass drives tilt angle oscillation (`tiltOsc = sin(time × 2.0) × bass × 0.1`).
- Mouse positions the focal plane (`focusCenter = mouseY`).
- Depth controls local blur radius (shallow DOF).

## Alpha Semantics
`alpha = clamp(focusConfidence × saturationBoost × (0.2 + depth × 0.8), 0.0, 1.0)`
- Encodes in-focus confidence, saturation boost, and depth factor.
- Never hardcoded to 1.0.

## Params
- strength, width, saturation unchanged.
- contrast renamed → tiltAngle (semantic clarity; value range unchanged).

## Tags Added
tilt-shift, miniature, depth-of-field

## Feature Flags Added
depth-aware
