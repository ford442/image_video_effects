SHADER: gen-hyperbolic-tessellation
IDENTITY: Poincare-disk kaleidoscope tessellation — Mobius-translated, rotating disk folded 8x by sector symmetry, palette colored by recursive depth, with a glowing ideal boundary circle.
KEEP VERBATIM: 13 bindings; Mobius translation (drift / held mouse); rotation; 8-step angular fold + scale recursion; palette(depthPhase); tilePulse; boundary glow; click ripple rings; C feedback blend (raw HDR in A/C, ACES on display only); params tileSymmetry / depthColor / rotationSpeed / boundaryGlow.
EXISTING IDEAS (2026-09-06):
  1. Kaleidoscope ideal vertices at fold corners
  2. Horocycles (constant hyperbolic radius rings from origin)
ADD:
  3. True {p,5} geodesic edges via repeated circle inversion — p = the existing symmetry count; each tile edge is a circle orthogonal to the unit circle (the defining line of a Poincare-disk tiling), drawn with Jacobian-corrected width so edges thin toward the ideal boundary exactly as the hyperbolic metric demands.
  4. Escher two-coloring from inversion parity — every inversion crosses to a neighbouring tile, so odd/even parity alternates tile hue (checkerboard of the hyperbolic tiling), strength on Depth Color.
FORBID: spring cursors, extraBuffer state, IQ-palette swaps, new sim, changing fold recursion or modes, new params.
A PACKING: raw HDR tessellation RGB + coverage alpha in A (C read as exact textureLoad raw history); ACES on writeTexture only. Unchanged.

## Notes
- Kept verbatim: bindings, Mobius drift/held-mouse translation, rotation, 8-step angular fold recursion, palette/tilePulse/boundary/vertex glow, horocycle rings, click ripples, C feedback blend, all 4 params (JSON params byte-exact).
- A packing: unchanged — raw HDR RGB + coverage in A, C read via exact textureLoad; ACES only on writeTexture.
- Idea locations (WGSL): Idea 1 line 94, Idea 2 line 113, Idea 3 lines 119-148 (symmetry slider sets p; Boundary Glow boosts geodesic brightness), Idea 4 lines 150-154 (Depth Color sets parity strength); geodesic/parity also feed coverage (170) and depth (171).
- Floor: already present (13 bindings, 16x16, ACES, semantic alpha, plasmaBuffer audio, depth, A write, no extraBuffer). Only fix: non-standard header normalized to 7-line banner. JSON features gained "mouse-driven" (held mouse translates the disk).
- Gates: naga "Validation successful"; wgsl_precommit_gate 1/1 passed, 0 extraBuffer violations. No textureStore(dataTextureC. Real-GPU visual QA: external.
