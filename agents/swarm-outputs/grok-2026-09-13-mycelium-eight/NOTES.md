# Mycelium leftover eight — notes

Per shader: kept verbatim, packing, which ideas are in the diff.

## gen-quantum-mycelium
- Kept: Network Density / Growth Chaos / Pulse Speed / Edge Softness; domain-rep cylinders; mouse void; z-pulse; SSS flesh.
- A packing: ACES display RGBA (C unused).
- Ideas in diff: septate rings along cylinder Y (Edge Softness); neighbor-cell fusion capsule to nearest face.
- Floor: mouse UV 0–1 (dropped `/ dims`); plasmaBuffer not `config.y`; ACES; write A; semantic alpha.

## gen-fractal-neuro-mycelium-lattice
- Kept: Branch Density / Flow Speed / Glow Intensity / Audio Reactivity; voronoi_edges tubes; mouse pull; nodes.
- A packing: ACES display RGBA (C unused).
- Ideas in diff: action-potential runners in edge-distance; synapse flash at Voronoi sites when the runner arrives.
- Floor: plasmaBuffer × Audio Reactivity (was filtered C); write A; semantic alpha.

## gen-symbiotic-chrono-mycelium-engine
- Kept: Mycelial Density / Plasma Glow / Temporal Warp / Mouse Influence; sdf_gear; sdf_mycelium; smooth_min.
- A packing: ACES display RGBA (C unused).
- Ideas in diff: helical wrap tube around gear; mycelium warp on lagged time vs gear rotation.
- Floor: deleted `applyGenerativePrimaryControls` (un-stole sliders); Mouse Influence scales SDF warp; ACES once.

## gen-symbiotic-cyber-mycelium
- Kept: Data Speed / Network Density / Growth Twist / Infection Bloom; X/Y/Z cylinders + node spheres; thread vs node materials.
- A packing: ACES display RGBA (C unused).
- Ideas in diff: packets along nearest cylinder axis in `q`; quarantine rim at infection falloff edge.
- Floor: plasmaBuffer (dropped `extraBuffer[0]` / unread `[133]`); write A; semantic alpha. Existing cosine palette kept as a tint, not the look.

## gen-mycelium-network
- Kept: Growth Rate / Branching Factor / Nutrient Density / Bioluminescence; extraBuffer[133..135] kick env; traveling pulses; HDR A.
- A packing: HDR display history (pre-ACES).
- Ideas in diff: chemotaxis wander toward mouse well × Nutrient Density; anastomosis loops (sibling-root + tip-to-tip).

## gen-chrono-voronoi-mycelium
- Kept: Growth Rate / Generations / Decay / Tip Glow; myceliumBranch borders; glowingTips; click fronts; exact C history.
- A packing: HDR display RGBA.
- Ideas in diff: clamp glow where generation borders coincide; apothecia cups (rim, not tip spark) on high-gen seeds.

## chrono-voronoi-mycelium
- Kept: Growth Bias / Temporal Scale / Decay Influence / Pattern Complexity; extraBuffer[133..134] inoc; A = (L1,L2,L3,0); spore rings.
- A packing: raw (layer1, layer2, layer3, 0) — ACES display only.
- Ideas in diff: clampellate septa along hyphae; neighbor-site cords to second-nearest seed.
- Floor: exact `textureLoad` for layers; inoc single-writer at (0,0); clock/IQ overlay stripped; `__finalRGB` renamed.

## gen-cybernetic-mycelium-neural-web
- Kept: Growth Rate / Pulse Intensity / Decay Speed / Network Complexity; extraBuffer[133..138] spring; KIFS + filigree; four-neighbor C.
- A packing: ACES display RGBA.
- Ideas in diff: myelination from neighbor-history luma; gap-junction flash when this pulse AND neighbor luma both spike.
