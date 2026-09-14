SHADER: gen-neuro-kinetic-bloom
IDENTITY: Raymarched deep-sea garden of repeated biomechanical neuron-flora (axon capsule + two side dendrites), twisting with bass, neon-green veins, sprung-mouse repulsion, click bloom rings.
KEEP VERBATIM: sdCapsule/rot, domain repetition (spacing 6), bass twist, sprung cursor spring (133..138), mouse repulsion, vein displacement MatID, fog, click-bloom ring loop, ACES, semantic alpha (hit + glowMass + treble + click), depth = 1 - t/50.
ADD (2 native ideas):
  1. Dendritic bifurcation: each side-branch tip forks into two thinner second-generation spines (length scales with Bloom Extension via branch_length).
  2. Saltatory action potentials: a per-cell spike front sweeps the axon but is quantized to nodes of Ranvier (0.9 spacing), so a white-cyan flash hops node to node; bass speeds conduction and brightens it; feeds glowMass/alpha.
FLOOR FIXES: removed unguarded extraBuffer[133/134/137] reads inside map() (sprung mouse now passed in as a parameter from main); all 133..138 reads now inside `arrayLength(&extraBuffer) > 138u` guard (writes already guarded); plasmaBuffer[0].xyz clamped 0..1 in map and main; mouse-held (zoom_config.w) now wired (repulsion push 0.5 -> 0.9 when held); header replaced to contract format; Uniforms comment corrected (y=RippleCount, w=MouseDown). JSON: added params array (bloomExtension/repulsionRadius/veinGlow/cameraZoom matching updatedParams), features now include audio-reactive/mouse-driven/upgraded-rgba. updatedParams unchanged. No dataTextureC use (no feedback), no dataTextureB write.
FORBID: writing dataTextureB/C, extraBuffer outside 133..138, u.config.y as audio, new springs, replacing the flora motif.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x (branch length oscillation amplitude + spine length), y (repulsion radius), z (vein displacement + vein glow + spike brightness), w (camera dolly) live
