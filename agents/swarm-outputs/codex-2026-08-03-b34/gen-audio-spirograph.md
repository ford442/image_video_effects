# Changelog — gen-audio-spirograph (Batch 34)

Lines: 192 → 244.

- Replaced eight moving line stubs with sampled epitrochoid/hypotrochoid trails
  whose sweep length follows the saved Trail Length control.
- Added safe segment math, sprung mouse lensing, click chime shells, regional
  audio color, bounded display history, semantic alpha, and curve depth.
- Uses a fixed 90-segment total sampling budget (five outer trails at 12 samples
  and three inner trails at 10) to keep the upgrade bounded.
- Preserved all musical-ratio and saved control roles.

Validation: focused WGSL/Naga, contracts, and strict extraBuffer checks pass.
Real-GPU visual QA remains external.
