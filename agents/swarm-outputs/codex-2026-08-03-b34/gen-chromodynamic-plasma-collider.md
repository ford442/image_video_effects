# Changelog — gen-chromodynamic-plasma-collider (Batch 34)

Lines: 178 → 202.

- Corrected normalized mouse mapping and added a sprung magnetic anomaly plus
  click-triggered collision shells.
- Replaced backward signed marching inside the containment tunnel with bounded
  forward steps and emitted real near-is-one tunnel depth.
- Kept A as display feedback and preserved ring density, collision rate,
  anomaly pull, and tunnel warp controls.

Validation: focused WGSL/Naga, contracts, and strict extraBuffer checks pass.
Real-GPU visual QA remains external.
