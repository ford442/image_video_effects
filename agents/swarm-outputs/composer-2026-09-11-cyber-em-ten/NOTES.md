# Cyber-EM hybrid ten — batch notes (2026-09-11)

## IDs

`cyber-rain-em`, `cyber-lattice-bilateral`, `cyber-ripples-coupled`, `cyber-scan-gabor`, `cyber-trace-structure`, `block-distort-em`, `bio-touch-em`, `ferrofluid-em`, `edge-glow-mouse-em`, `gravity-well-em`

## Per-shader

### cyber-rain-em
- **Kept:** fp128 rain, spring [133..138], orbital clicks, four params
- **Ideas:** column lead-char bloom; EM wiper skew along mouse velocity
- **A packing:** ACES display RGBA

### cyber-lattice-bilateral
- **Kept:** hex lattice, bilateral filter, spring [133..138], four params
- **Ideas:** node capacitive discharge on ripple; seam snap bilateral highlight
- **A packing:** ACES display RGBA

### cyber-ripples-coupled
- **Kept:** coupled ripples, EM displacement, spring [133..138], four params
- **Ideas:** constructive crest doubling; orbital charge decay ring
- **A packing:** raw sim state (vel/vorticity/density) — documented

### cyber-scan-gabor
- **Kept:** Gabor bank, fp128 phase, scan packet, four params
- **Ideas:** orthogonal null cyan/magenta tint; retrace phosphor decay from C
- **A packing:** ACES display RGBA

### cyber-trace-structure
- **Kept:** structure tensor traces, spring [133..138], four params
- **Ideas:** eigenvector neon streak; saddle bifurcation fork
- **A packing:** trace history RGBA in A

### block-distort-em
- **Kept:** block push, per-block EM, click charges, four params
- **Ideas:** block hinge shear along E-field; row phase π stagger
- **A packing:** ACES display RGBA

### bio-touch-em
- **Kept:** voronoi cells, EM overlay, click charges, four params
- **Ideas:** mitosis twin pulse (bass); membrane depolarization wave
- **A packing:** ACES display RGBA

### ferrofluid-em
- **Kept:** multipole spikes, spring [133..138], four params
- **Ideas:** spike coalescence snap bridge; Earnshaw treble wobble
- **A packing:** HDR in A, ACES on write only

### edge-glow-mouse-em
- **Kept:** Sobel edge glow, EM fields, four params
- **Ideas:** Laplacian corona; field-line advection streak from C
- **A packing:** ACES display RGBA

### gravity-well-em
- **Kept:** gravity lens + EM singularity, click charges, four params
- **Ideas:** photon ring halo; frame-drag hue shear
- **A packing:** ACES display RGBA

## Gates

- Naga: 10/10
- extraBuffer new [0..132]: 0
- dead sliders new: 0
- SKIP_WASM_BUILD=1 build: green
- Jest: 652 pass / 6 fail (pre-existing WASM bridge/api.js)
