# Geometric ten — batch notes (2026-09-11)

## IDs

`interactive-origami`, `datamosh`, `flip-matrix`, `neon-quantum-lattice`, `ascii-glyph`, `voronoi-zoom-turbulence`, `kinetic_tiles`, `hyperbolic-dreamweaver`, `digital-crease`, `kaleido-scope-grokcf1`

## Per-shader

### interactive-origami
- **Kept:** triWave folds, foil, ripples, four params
- **Ideas:** mountain-valley parity; wet-fold shadow along crease tangent
- **A packing:** ACES display RGBA

### datamosh
- **Kept:** block motion, I-frame smear, spring [133..138], four params
- **Ideas:** 8×8 macroblock tear at I-frame; chroma ghost from C motion
- **A packing:** motion state in A (documented)

### flip-matrix
- **Kept:** hinge propagation, bevel, exact C, four params
- **Ideas:** cam notch at 90°; back-face mirror past π/2
- **A packing:** ACES display RGBA

### neon-quantum-lattice
- **Kept:** penrose_dist, tile_color, parallax, four params
- **Ideas:** electron hop on treble; defect pentagon highlight
- **A packing:** ACES display RGBA

### ascii-glyph
- **Kept:** spring [133..136], ripple scramble, four params
- **Ideas:** phosphor smear on char change vs C; CRT scanline mask
- **A packing:** ACES display RGBA

### voronoi-zoom-turbulence
- **Kept:** zoom pulses, boundary shear, fast-motion, four params
- **Ideas:** F2−F1 edge neon rim; bass centroid inflation
- **A packing:** ACES display RGBA

### kinetic_tiles
- **Kept:** wave cascade, bevel shear, spring [133..138], four params
- **Ideas:** domino row delay; grout compression darkening
- **A packing:** ACES display RGBA

### hyperbolic-dreamweaver
- **Kept:** hyperbolicDist, fwidth LOD, four params
- **Ideas:** {7,3} distance band color; geodesic edge weave
- **A packing:** ACES display RGBA

### digital-crease
- **Kept:** Kawasaki fold, spring [133..138], paperTex, four params
- **Ideas:** valley-fold AO; wet-glue seam on crease ridge
- **A packing:** ACES display RGBA

### kaleido-scope-grokcf1
- **Kept:** segments/rotation/zoom/ringOffset, kaleido fold
- **Ideas:** segment seam glow; counter-rotating inner ring
- **A packing:** ACES display RGBA

## Skipped (recent batches)

`kaleido-scope`, `time-lag-map`, `adaptive-mosaic`, `neon-poly-grid`, `spec-hypercube-projection`, `crystal-mosaic`

## Gates

- Naga: 10/10
- extraBuffer new: 0
- dead sliders new: 0
- SKIP_WASM_BUILD=1 build: green
- Jest: 652 pass / 6 fail (pre-existing WASM bridge)
- Real-GPU visual QA: external
