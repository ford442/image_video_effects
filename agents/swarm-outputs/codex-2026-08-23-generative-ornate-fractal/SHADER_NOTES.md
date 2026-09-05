# Shader notes

- `gen-dynamic-tessellation-ornate-fractal-tiles`: upgraded 8×8 to 16×16, replaced generic post-controls with live fractal detail/motion/tile/mouse behavior, removed double tone/gamma handling, and added exact ornate-tile history plus click fronts.
- `gen-echo-dunes`: moved bass-envelope persistence from forbidden slot 0 to slot 133, preserved cursor echo rings, added timestamped dune echoes, exact history, semantic dune coverage, relief depth, and display RGBA A packing.
- `gen-eldritch-quantum-fractal-eye`: repaired the nearly zero fractal iteration count, normalized mouse orbit correctly, applied both camera rotations safely, and added exact temporal plasma, click rings, ACES, semantic alpha, and near-is-one hit depth.
- `gen-emergent-calligraphic-weave`: new layered pressure-nib ink field with flow-noise lanes, chromatic hairlines, held-pointer bending, and expanding click ink.
- `gen-ferrofluid-monolith`: new raymarched twisted obelisk with audio-shaped radial ferro spikes, emissive core, pointer orbit, click magnetism, and hit-distance depth.
- `gen-fibonacci-spiral-garden`: new 96-node golden-angle phyllotaxis system with staged unfurling, five-lobed petals, pointer repulsion, and growth-front clicks.
- `gen-flame-fractal-attractor`: new curling folded orbit-density field with center/filament traps and interactive ember wakes.
- `gen-flowing-silk-ribbons`: new layered analytic silk bands with tangent-dependent anisotropic sheen, held-pointer combing, spectral audio, and click waves.
- `gen-fractal-flame-classic`: new classic swirl/horseshoe/polar variation blend, warm-to-spectral palette cycling, distance traps, and temporal ember feedback.
- `gen-fractal-tree-growth`: new recursive binary-path segment field with staged growth, branching depth/spread, pointer wind, spectral leaves, and click growth fronts.

The first three legacy definitions now also expose four named `params`; their generic `updatedParams` labels were corrected where the actual WGSL behavior was specific.
