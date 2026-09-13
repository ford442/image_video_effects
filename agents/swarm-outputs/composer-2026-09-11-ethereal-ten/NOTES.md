# Ethereal generative ten — batch notes (2026-09-11)

## IDs

`gen-ethereal-cyber-chrono-nebula-phoenix`, `gen-ethereal-cyber-chrono-void-whale`, `gen-ethereal-cyber-plasma-void-dragon`, `gen-ethereal-glass-flora-terrarium`, `gen-ethereal-quantum-glass-nautilus`, `gen-ethereal-quantum-hologram-bonsai`, `gen-ethereal-quantum-holographic-fractal-coral`, `gen-ethereal-quantum-medusa`, `gen-ethereal-silk-veil`, `gen-feedback-echo-chamber`

## Per-shader

### gen-ethereal-cyber-chrono-nebula-phoenix
- **Kept:** sdPhoenix, attractorTrap, spring halo [133..137], ripple flares, all four params
- **Ideas:** `wingFeatherFilaments()` on SDF edge; `tailEmberConvection()` along tail axis
- **A packing:** raw telemetry (trap, d, nebula, alpha) — unchanged

### gen-ethereal-cyber-chrono-void-whale
- **Kept:** rib torus cage, core bloom, temporal streams, click fronts, four params
- **Ideas:** `baleenStriations()` on rib mat; `bassSonarPings()` automatic core rings
- **A packing:** ACES display RGBA

### gen-ethereal-cyber-plasma-void-dragon
- **Kept:** capsule segments, octahedral shards, halo sigils, nebula veins, four params
- **Ideas:** `breathPlasmaJet()` along spine; `scaleOverlapParallax()` per segment
- **A packing:** ACES display RGBA

### gen-ethereal-glass-flora-terrarium
- **Kept:** chromatic raymarch, pollen mat, four params
- **Ideas:** `condensationDroplets()` on shell; `dewMeniscus()` on leaf normals
- **A packing:** ACES display RGBA

### gen-ethereal-quantum-glass-nautilus
- **Kept:** log spiral map, voronoi micro-fractures, four params (byte-exact)
- **Ideas:** chamber septa in `map()`; `pearlNacreLuster()` on inner ridges
- **Floor:** ACES, depth, dataA, exact C, plasmaBuffer audio, semantic alpha, updatedParams + features on JSON
- **A packing:** ACES display RGBA

### gen-ethereal-quantum-hologram-bonsai
- **Kept:** branch SDF, bass_env [133], mouse lensing, four params
- **Ideas:** `pruneSealRings()` at tips; north-facing moss from `dot(n, upLight)`
- **A packing:** ACES display RGBA

### gen-ethereal-quantum-holographic-fractal-coral
- **Kept:** recursive branch map, palette interference, four params
- **Ideas:** polyp mouth pits (`max(d, -pitSDF)`); zooxanthellae symbiont pulse from exact C
- **A packing:** ACES display RGBA

### gen-ethereal-quantum-medusa
- **Kept:** tentacle field, C glow memory, chromatic separation, four params
- **Ideas:** nematocyst stinger dots on rim; bell contraction wave from bass phase
- **A packing:** ACES display RGBA

### gen-ethereal-silk-veil
- **Kept:** ribbon layers, gather, click pluck, four params
- **Ideas:** selvage fray on ribbon edges; held-crease memory from exact C
- **A packing:** ACES display RGBA

### gen-feedback-echo-chamber
- **Kept:** loadHistoryExact taps, bass_env [133], gravity well, four params
- **Ideas:** harmonic echo ladder at 2×/4×/6×/8× spacing; standing-wave nodal interference
- **A packing:** ACES display RGBA

## Gates

- Naga: 10/10
- extraBuffer new violations: 0
- dead sliders new: 0
- catalog regenerated
- Jest: 652 pass, 6 fail (pre-existing WASM bridge/api.js)
- SKIP_WASM_BUILD=1 build: green
- Real-GPU visual QA: external
