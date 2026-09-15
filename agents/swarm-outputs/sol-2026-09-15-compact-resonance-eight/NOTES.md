# Compact Generative Resonance Eight — Implementation Notes

## `gen-aetherial-plasma-loom`

- Kept: 3D value noise/FBM, ray-integrated ribbon density, pointer twist, and
  all four saved slider roles.
- Added: opposite-helicity warp/weft ribbon families; anti-aligned crossing
  knots with paired cyan/magenta exhaust.
- Floor: feedback-as-audio replaced by `plasmaBuffer[0].xyz`; ACES, semantic
  coverage, generated hit depth, exact C display history, and A writeback.
- A packing: ACES display RGBA.

## `gen-prismatic-mobius-helix`

- Kept: Möbius SDF, stacked helix, mouse orbit, thin-film palette, and all four
  saved slider roles.
- Added: a face-aware 4π traveler; handed spectral current on the orientation
  seam.
- Floor: A changed from unrelated telemetry to the display RGBA that C already
  reads as color history; semantic history alpha retained.
- A packing: ACES display RGBA.

## `gen-hyperdimensional-bismuth-lattice`

- Kept: eight-generation absolute box fold, 45-degree fold rotations, box SDF,
  pointer-local twist, and all four saved slider roles.
- Added: generation-scaled hopper terrace shells; alternating-parity twin
  boundary glints.
- Floor: reserved `extraBuffer` pseudo-audio removed in favor of
  `plasmaBuffer[0].xyz`; ACES, semantic coverage, generated hit depth, A write.
- A packing: ACES display RGBA.

## `gen-sentient-void-silk-nebula`

- Kept: simplex-derived curl field, flow/density/vortex/iridescence controls,
  held-pointer vortex, and slow temporal persistence.
- Added: three phase-offset fibrils braided around the curl tangent; compact
  opposing-curl tension knots with tangent-aligned caustic tails.
- Floor: raw curl magnitude retained instead of normalizing away tension;
  reserved `extraBuffer[0]` audio removed; exact C display history, ACES,
  semantic alpha/depth, A write.
- A packing: ACES display RGBA.

## `gen-quantum-liquid-metal-chronosphere`

- Kept: simplex-displaced spherical SDF, temporal radial distortion, smooth
  pointer gravity well, and all four saved slider roles.
- Added: coherent quadrupole/octupole capillary modes; latitude-dependent
  differential-rotation bands in the thin-film phase.
- Floor: ripple padding is no longer treated as amplitude/audio; zero-radius
  normalization is guarded; ACES, semantic alpha, hit depth, A write.
- A packing: ACES display RGBA.

## `gen-prismatic-quantum-glass-chrysalis-engine`

- Kept: octahedron/hex-prism intersection, Voronoi cuts, raymarch, internal
  plasma, mouse orbit, and all four saved slider roles.
- Added: tapered transverse chamber ribs clipped to the original shell;
  wavelength-separated TIR caustic threads on interior cut lips.
- Floor: canonical Uniforms layout restored; fake ripple-coordinate audio and
  `fract(time)` chromatic flicker removed; real three-band audio, ACES,
  semantic alpha/depth, A write.
- A packing: ACES display RGBA.

## `gen-void-harmonic-cymatic-resonator`

- Kept: three-axis standing waves, spherical envelope, bounded complexity
  harmonics, pointer warp, and all four saved slider roles.
- Added: interior zero-pressure Chladni membranes; smoothly beating adjacent
  eigenmodes with moving degeneracy seams.
- Floor: C-as-FFT fiction removed; `plasmaBuffer[0].xyz`, exact C display
  history, ACES, semantic alpha/depth, A write.
- A packing: ACES display RGBA.

## `gen-stellar-acoustic-resonance-manifold`

- Kept: repeated-cell stellar spheres, FBM perturbation, orbital motion,
  blackbody family, pointer gravity bend, and all four saved slider roles.
- Added: coherent radial p-mode shells plus angular g-mode sectors;
  compression-antinode blackbody heating and rarefaction cooling.
- Floor: C-as-audio fiction removed; `plasmaBuffer[0].xyz`, exact C display
  history, ACES, semantic alpha/depth, A write.
- A packing: ACES display RGBA.

## Parameter compatibility

All pre-existing `params`, `parameters`, `passes[].params`, and
`updatedParams` blocks were compared against `HEAD` and remained equal.
Missing top-level `params` / `updatedParams` metadata was added without changing
the saved values or slider mappings.

## Visual handoff

The Cloud VM has no WebGPU adapter. Naga and application-level structural gates
prove compilation and contract compatibility; composition, motion balance, and
performance still require real-GPU review.

## Post-review corrections

- Möbius Helix: replaced the algebraically toroidal cross-section with a true
  half-twist rectangular strip; quantized/centered coil count and stopped Coil
  Count from changing animation speed.
- Bismuth Lattice: corrected Complexity to select exactly 4–8 fold generations
  and mapped pointer twist into aspect-correct world space.
- Chronosphere: aligned the pointer ray with the engine's top-down mouse space.
- Cymatic Resonator: confined nodal membranes to the spherical resonator and
  mapped the full 1–10 Complexity range continuously onto five bounded octaves.
- Stellar Manifold: made Audio Reactivity gate all audio influence, removed
  camera dolly from Orbital Speed, corrected pointer Y, and made hit stepping
  robust to signed-distance overshoot.
