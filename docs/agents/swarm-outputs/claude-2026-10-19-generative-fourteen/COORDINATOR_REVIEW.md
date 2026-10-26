# Coordinator review — claude-2026-10-19-generative-fourteen

Checklist per §9 / §12.7. All 14 files: card written before diff, ideas pointable via
`// ── Idea N` comments, saved params unchanged, A packing stated in header, Naga (naga-wasm) valid,
precommit gate, extraBuffer and dead-slider audits pass. No springs added; no ripple fronts added
(aurora-curtain keeps its existing click fronts). Real-GPU visual QA: external, not done.

| Shader | New ideas | §12.2 rows | Verdict |
|---|---|---|---|
| gen-quantum-aether-origami | 3 mountain/valley fold parity; 4 whitened crease lines | E Fold count as material; E SDF curvature | pass |
| gen-neural-fractal | 5 nodes of Ranvier / saltatory conduction; 6 synaptic boutons with delay | — | pass |
| gen-fractal-bioluminescence-spore-network | 5 seawater spectral extinction; 6 luciferin depletion (C) | F Beer–Lambert | pass |
| voxel-grid | 3 voxel cast shadow; 4 bevel catch-light | — | pass |
| gen-nebular-chrono-astrolabe | 3 engraved limb graduations; 4 march-count crevice occlusion | E Step-count AO | pass |
| gen-murmuration-phantom | 5 fringe birds resolve; 6 flow-carried wake (C back-trace) | — | pass |
| spore-galaxy | 1 arm dust lane; 2 spore ignition; 3 golden-angle sporangium core | F Beer–Lambert; E Golden-angle | pass |
| aurora-curtain | 1 sharp lower border / rayed tail; 2 N2 pink fringe; 3 O(1D) red afterglow | — | pass (naga fixed, ratchet 27) |
| gen-bioreactor-bloom | 4 cleavage furrow; 5 quorum-sensing pulse lock | — (turbidity dropped) | pass after amendment |
| gen-luminous-cauldron | 3 bubble lensing of caustics; 4 plume-gated nucleation; 5 steam veil | F Snell refraction | pass |
| gen-xeno-botanical-synth-flora | 6 golden-angle phyllotaxis; 7 xylem sap pulses | E Golden-angle | pass (7 ideas total across passes; 2 this pass) |
| sand-dunes | 1 slipface grainflow tongues; 2 brink terminator; 3 brink spindrift (C) | — | pass |
| neon-edge-pulse | 4 plasma-core whitening; 5 discharge striations; 6 phosphor afterglow (C) | — | pass |
| generative-turing-veins (+ turing-veins) | 1 isotropic 9-pt RD stencil; 2 reaction-front sprouting tips; 3 flow-driven vessel remodelling | D Isotropic 9-point Laplacian | pass |

Row de-dup (§12.4): Beer–Lambert ×2 (after dropping bioreactor turbidity), Golden-angle ×2, every
other row ×1. No two files share both formulae.

Floor fixes carried along: exact C `textureLoad` replacing filtered history reads
(generative-turing-veins, spore-galaxy); `pow` with possibly negative base removed (neural-fractal,
astrolabe, cauldron, sand-dunes, spore-galaxy); clamp ≥ 0 before ACES across the batch;
spore-galaxy per-arm audio moved off never-written plasmaBuffer[1..8] to plasmaBuffer[0].xyz;
bioreactor bass state moved off extraBuffer[0] to extraBuffer[133].
