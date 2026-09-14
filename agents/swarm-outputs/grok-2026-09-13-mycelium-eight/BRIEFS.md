# Mycelium leftover eight — Idea Cards

Written **before** any WGSL edit, per `docs/SHADER_UPGRADE_BATCH.md` §2.

Family: remaining mycelium companions that are **not** tropism-rich. Two native
ideas each. Identities kept. No spring+ripple+IQ stamp, and **do not clone
“septa + anastomosis” onto every file**.

Skipped: `mycelium-network` (already tropism / bass-heartbeat / click packets);
physarum `extraBuffer[0..]` agents; `digital-moss` / `digital-moss-rgba`
(already 09-12 Idea Cards); blackbody cluster; liquid-small; `crt-clear-zone`.

---

```
SHADER: gen-quantum-mycelium
IDENTITY: raymarched repeating cylinder hyphae, mouse void cutout, SSS flesh, z-axis cyan pulses, volumetric spores
KEEP VERBATIM: Network Density / Growth Chaos / Pulse Speed / Edge Softness; domain-rep cylinders; mouse void; z-pulse
ADD (2 native ideas):
  1. Septate rings — periodic thickness/emission along each cylinder axis (real hyphal septa, uses Edge Softness)
  2. Neighbor fusion — smin a short bridge to the nearest domain-repeat sibling so threads fuse instead of only tiling
FORBID on this file: IQ palette; extraBuffer springs; cloning mycelium-network heartbeat
A PACKING: ACES display RGBA (C unused — keep it that way)
```

Floor: mouse is `zoom_config.yz` in 0–1 UV (drop `/ dims`); `plasmaBuffer[0].xyz` not `config.y`; ACES on display; write A; semantic alpha.

---

```
SHADER: gen-fractal-neuro-mycelium-lattice
IDENTITY: raymarched 3D Voronoi-edge tube lattice + nodes, mouse warp, fake SSS, z-pulse emit
KEEP VERBATIM: Branch Density / Flow Speed / Glow Intensity / Audio Reactivity; voronoi_edges tubes; mouse pull
ADD (2 native ideas):
  1. Action-potential runners — emission travels along voronoi edge distance (`map.y`), not only `p.z`
  2. Synapse flash — nodes fire when the runner arrives (vertex sites, not a disk fill)
FORBID on this file: springs; `dataTextureC` as audio; cloning quantum septa
A PACKING: ACES display RGBA (C unused)
```

Floor: `plasmaBuffer[0].xyz * Audio Reactivity`; write A; semantic alpha.

---

```
SHADER: gen-symbiotic-chrono-mycelium-engine
IDENTITY: raymarched gear SDF fused with an fbm mycelial tube, plasma glow, mouse warp
KEEP VERBATIM: Mycelial Density / Plasma Glow / Temporal Warp / Mouse Influence; sdf_gear; sdf_mycelium; smooth_min
ADD (2 native ideas):
  1. Hyphal wrapping — extra tube that coils around the gear radially (entwine, not just blob smin)
  2. Chrono lag — mycelium warp phase delayed vs gear rotation so the living net trails the clockwork
FORBID on this file: new springs; IQ overlay; leaving `applyGenerativePrimaryControls` in place
A PACKING: ACES display RGBA (C unused)
```

Floor: un-steal sliders — delete `applyGenerativePrimaryControls`. `x/y/z` already drive SDF/glow; wire `w` as real mouse SDF influence (JSON name). ACES once on display.

---

```
SHADER: gen-symbiotic-cyber-mycelium
IDENTITY: repeating X/Y/Z cylinders + data-node spheres, mouse infection bloom, data pulses
KEEP VERBATIM: Data Speed / Network Density / Growth Twist / Infection Bloom; thread vs node materials
ADD (2 native ideas):
  1. Axis-aligned packets — pulses travel along the nearest cylinder axis in `q`, not radial `length(p.xy)`
  2. Infection quarantine rim — emission ring at the infection falloff edge (front), not a disk fill
FORBID on this file: extraBuffer audio lies; making the existing IQ palette the whole look; new springs
A PACKING: ACES display RGBA (C unused)
```

Floor: `plasmaBuffer[0].xyz` (drop `extraBuffer[0]` and unread `[133]`); write A; semantic alpha.

---

```
SHADER: gen-mycelium-network
IDENTITY: DLA-like 2D branching with bioluminescent tips, traveling pulses, kick shockwave, HDR C history
KEEP VERBATIM: Growth Rate / Branching Factor / Nutrient Density / Bioluminescence; extraBuffer[133..135] kick env; HDR A
ADD (2 native ideas):
  1. Chemotaxis — branch wander biased toward the mouse nutrient well, scaled by Nutrient Density (slider currently only tints dirt)
  2. Anastomosis loops — when a side-branch tip lands near another segment, fuse a short bridge (DLA loops)
FORBID on this file: cloning non-gen mycelium-network tropism/heartbeat; new springs
A PACKING: HDR display history (pre-ACES) as HEAD — do not ACES stored A
```

---

```
SHADER: gen-chrono-voronoi-mycelium
IDENTITY: multi-generation Voronoi fungal layers, mouse nutrient, click fronts, traveling spores, HDR trails
KEEP VERBATIM: Growth Rate / Generations / Decay Rate / Tip Glow; myceliumBranch borders; glowingTips; exact C history
ADD (2 native ideas):
  1. Clamp connections — extra glow where two generation borders coincide (colonies fuse across layers)
  2. Apothecia cups — disk fruiting bodies at Voronoi seeds on high-generation patches (dark cup, bright rim — not the existing tip spark)
FORBID on this file: springs; cloning digital-moss rhizoids; IQ overlay
A PACKING: HDR display RGBA as HEAD
```

---

```
SHADER: chrono-voronoi-mycelium
IDENTITY: 2D Voronoi colonies, hyphae on edges, raw A growth-ring layers, bass spore rings, damped inoculation
KEEP VERBATIM: Growth Bias / Temporal Scale / Decay Influence / Pattern Complexity; extraBuffer[133..134] inoc; A = (L1,L2,L3,0)
ADD (2 native ideas):
  1. Clampellate ticks — periodic dark septa along existing hyphae (`hyphae1/2/3` distance)
  2. Neighbor-site cords — short extra thread toward the second-nearest seed (`v.zw` already returned) so colonies link, not only edge-glow
FORBID on this file: new springs; rewriting as Gray-Scott; cloning gen-chrono fruiting cups
A PACKING: raw (layer1, layer2, layer3, 0) — ACES display only
```

Floor: exact `textureLoad(dataTextureC, coord, 0)` for layer state (drop filtered sample); extraBuffer inoc **single-writer at (0,0)**.

---

```
SHADER: gen-cybernetic-mycelium-neural-web
IDENTITY: KIFS lattice + hyphal filigree, spring-cursor attractor, click mutation, four-neighbor C history
KEEP VERBATIM: Growth Rate / Pulse Intensity / Decay Speed / Network Complexity; extraBuffer[133..138] spring; ACES display A
ADD (2 native ideas):
  1. Myelination — trails thicken where four-neighbor history is already high (fire-reinforced, uses existing connectivity)
  2. Gap-junction flash — spark when this pixel and a neighbor both spike this frame (not the existing intersection ridge)
FORBID on this file: new springs; IQ overlay; cloning other files’ septa
A PACKING: ACES display RGBA (HEAD)
```
