# Claude Opus batch 2026-09-27 — quantum / radiant / crystalline generative (10)

Contract: `docs/SHADER_UPGRADE_BATCH.md`. Cards written before any WGSL edit.

Runtime notes (verified 2026-09-27):
- `plasmaBuffer[0].xyz` is written every frame (`src/renderer/webgpu/audioDepth.ts` `writePlasmaBuffer`, called from `frame.ts`). Audio is live.
- `writeExtraBuffer` uploads the full 256-float scratch every frame, so `extraBuffer[133..138]` is zeroed each frame and cannot hold state. **No file in this batch touches extraBuffer.** Every file already owns its pointer behaviour; no springs added.

Batch-wide FORBID: shared spring / ripple / IQ-palette overlay, extraBuffer state, renaming or re-defaulting params, starting to use B.

---

```
SHADER: gen-quantum-liquid-metal-chronosphere
IDENTITY: raymarched thin-film liquid-metal sphere with capillary modes and differential latitude bands
KEEP VERBATIM: 4 params, surfaceModes (ideas 1–2 from 09-15), held gravity well, click-ring loop, ACES display A
ADD:
  3. Rayleigh–Plateau beading — the held-mouse pull tendril necks into droplets along the ray (liquid metal pinches off; Surface Tension sets bead spacing)
  4. Chrono echo shells — exact C loads at a radially contracted coord so past frames expand outward as fading shells in the void (this is the "chrono" sphere)
FORBID: springs, IQ palettes beyond the existing one, echoes over the lit surface
A PACKING: ACES display RGBA (C read as radial echo)
```

```
SHADER: gen-quantum-mycelial-neural-web
IDENTITY: curl-warped three-axis fibre web raymarched with bioluminescent volumetric glow
KEEP VERBATIM: params (camelCase ids), fibre SDF + entanglement rotations, held-mouse attractor, radial pulse
ADD:
  1. Action-potential spikes — map returns the axial coordinate of the nearest fibre; sharp packets travel along each fibre at Pulse Speed (neurons fire along axons)
  2. Synaptic junction flares — where the 2nd-nearest fibre is nearly as close as the nearest (crossings), a warm flash fires as a spike passes; Entanglement tints it
FORBID: ripple shockwaves, trail feedback overlays
A PACKING: ACES display RGBA
FLOOR: audio from plasmaBuffer (was a filtered sample of dataTextureC), ACES, semantic alpha, depth, A write
```

```
SHADER: gen-quantum-mycelium
IDENTITY: fly-through of domain-repeated septate hyphae with fleshy SSS, spore haze, cursor repulsion sphere
KEEP VERBATIM: septa + fusion bridges (09-13 ideas), 4 params, repulsion sphere, pulse wave
ADD:
  3. Cytoplasmic streaming granules — organelle beads flowing along each thread's axis, lit through the SSS term, piling up against septa
  4. Melanized wound rim — threads cut by the cursor's repulsion sphere get a dark-amber cauterised rim at the cut surface
FORBID: generic cursor glow, trails
A PACKING: ACES display RGBA (C unused)
```

```
SHADER: gen-quantum-neural-lace
IDENTITY: octahedral node lattice joined by strands, warp-flight camera, pulse wave + travelling packets, HDR trails
KEEP VERBATIM: orbit camera, forward conveyor, pulse wave, packets, advected HDR trail
ADD:
  1. Per-node stochastic firing with refractory decay — map fills its unused material id with node-vs-strand + cell-id hash; each node flashes on its own clock
  2. Nodes of Ranvier — strands banded into myelin segments with bright gaps; packets are gated to the gaps (saltatory conduction)
FORBID: palette swaps, springs
A PACKING: HDR trail RGB (pre-ACES), alpha = coverage; ACES on writeTexture only
```

```
SHADER: gen-quantum-pollen
IDENTITY: three-layer drifting pollen swarm with gravity well, click burst, luma-keyed spawn, advected trails
KEEP VERBATIM: layers, drift field, burst, spawn, palette, neon/CA/ACES post chain, params
ADD:
  1. Echinate exine — grain cores modulated by angular spikes (count and spin per cell), so grains read as spiky pollen, not dots
  2. Tetrad dehiscence — each cell holds four sub-grains whose separation breathes between clumped tetrad and released monads
FORBID: new sim, extra trail overlays
A PACKING: HDR feedback RGB + slow age alpha (existing)
FLOOR: advection now an exact C load (was textureSampleLevel on rgba32float)
```

```
SHADER: gen-quantum-singularity-forge
IDENTITY: black hole with warped accretion torus ejecting KIFS crystals, mouse lens
KEEP VERBATIM: map + materials, KIFS, heat gradient, param mapping
ADD:
  1. Photon ring + lensed starfield — miss rays bend by impact parameter before the starfield lookup, thin bright ring at the critical impact parameter (wires the dead Lensing Intensity slider)
  2. Relativistic Doppler beaming — approaching side of the disk brighter/bluer, receding side dimmer/redder
FORBID: ripples, springs
A PACKING: ACES display RGBA, alpha = coverage
FLOOR: exact C load, semantic alpha, JSON features/params
```

```
SHADER: gen-quantum-superposition
IDENTITY: Lissajous ghost wave-packets, mouse collapse, click-ripple collapse, two-source fringes, Zeno
KEEP VERBATIM: everything above, 4 params
ADD:
  1. Coherent interference term — use the accumulated but unused totalRe/totalIm: |Σψ|² − Σ|ψ|² as phase-hued fringes; Decoherence fades coherent → incoherent
  2. Detector-screen buildup — per-frame stochastic hits where hash < probability, accumulated in C with slow decay (the double-slit dot-by-dot histogram)
FORBID: trails of the colour image, springs
A PACKING: rgb = ACES display, a = detector hit accumulator (writeTexture alpha stays semantic)
```

```
SHADER: gen-quasicrystal
IDENTITY: n-fold plane-wave quasicrystal with metallic/gem colouring and Voronoi crackle
KEEP VERBATIM: symmetry/density/colour/projection params, quasicrystal2, gem + crackle + sparkle, B writes
ADD:
  1. Phason strain field — per-wave phase offsets from a perpendicular-space field (fbm + pointer Gaussian) cause local tile flips; the pointer pushes the phason
  2. Ammann bars — Fibonacci-spaced line grids (cut-and-project) along each of the n directions, faint gold
FORBID: palette swaps, springs
A PACKING: rgb = display trail, a = bass envelope (fixes HEAD lie: bass envelope was in A.r and was read back as red trail)
```

```
SHADER: gen-radiant-chrono-glass-nautilus
IDENTITY: log-spiral glass shell with plasma-filled chambers, septa and birefringent lamellae
KEEP VERBATIM: spiral map, ids 1–3, septa, lamellae, 4 params
ADD:
  3. Siphuncle — thin tube threading the interior chambers (id 4) with plasma pulses travelling along log r
  4. Chamber-sequential plasma tide — interior glow modulated per whorl index; a wave moving newest → oldest chamber, bass × Audio Reactivity speeds it
FORBID: trails, springs
A PACKING: ACES display RGBA
```

```
SHADER: gen-radiant-quantum-crystalline-forge
IDENTITY: KIFS crystal fly-through with twin facets, weld seams and fog
KEEP VERBATIM: fold loop, twins, welds, 4 params, screen-space gravity well
ADD:
  3. Blackbody seam cooling — weld/seam-fog emission tinted by a blackbody ramp cooling with ray distance (hot near the forge front)
  4. Cleavage-plane glints — sharp speculars on facets whose normals align with the axis-aligned fold planes, treble-boosted
FORBID: ripples, springs
A PACKING: ACES display RGBA
```
