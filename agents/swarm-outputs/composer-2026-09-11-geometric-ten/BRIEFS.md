# Geometric ten — Idea Cards (written before WGSL)

Family: leftover `geometric` cohort from foundation note. Two native ideas each. Identities kept. Existing springs/ripples kept where HEAD owns them; no new springs. Skipped shaders upgraded in recent batches: `kaleido-scope`, `time-lag-map`, `adaptive-mosaic`, `neon-poly-grid`, `spec-hypercube-projection`, `crystal-mosaic`.

Claimed IDs: `interactive-origami`, `datamosh`, `flip-matrix`, `neon-quantum-lattice`, `ascii-glyph`, `voronoi-zoom-turbulence`, `kinetic_tiles`, `hyperbolic-dreamweaver`, `digital-crease`, `kaleido-scope-grokcf1`.

---

SHADER: interactive-origami
IDENTITY: Triangle-wave origami crease planes with held pinch, foil iridescence, and click ripples
KEEP VERBATIM: foldScale/depth/lightInt/depthInfl; triWave foldHeight; foil; spring-free pinch; exact C
ADD (2 native ideas):
  1. Mountain-valley fold parity — alternate crease sign by grid cell so ridges read as paper
  2. Wet-fold shadow along crease tangent (darken valley side of each fold normal)
FORBID: replacing with liquid sim, new springs
A PACKING: ACES display RGBA in A

---

SHADER: datamosh
IDENTITY: Block-wise motion-vector datamosh with I-frame smear and spring-smoothed pointer
KEEP VERBATIM: motionStrength/iframeInterval/blendAmount/feedbackDecay; block motion; A motion packing; spring [133..138]
ADD (2 native ideas):
  1. Macroblock quantization tear at I-frame phase boundary (8×8 block snap glitch)
  2. Chroma ghost trail along stored motion vector from exact C
FORBID: replacing with slit-scan, new springs
A PACKING: motion state in A (documented); display on writeTexture

---

SHADER: flip-matrix
IDENTITY: Split-flap departure board with inertial hinge propagation from mouse
KEEP VERBATIM: density/effectRadius/flipIntensity/gap; cell flip phase; hinge/bevel; exact C history
ADD (2 native ideas):
  1. Mechanical cam notch darkening at hinge line when flap crosses 90°
  2. Back-face mirror sample when flap angle > π/2 (shows reverse of tile)
FORBID: matrix rain overlay, new springs
A PACKING: ACES display RGBA in A

---

SHADER: neon-quantum-lattice
IDENTITY: Penrose-like quasi-lattice neon tiles with depth parallax and mouse inflation
KEEP VERBATIM: inflation/glowWidth/parallax/brightness; penrose_dist; tile_color; depth parallax
ADD (2 native ideas):
  1. Electron hop glow along nearest lattice edge on treble beats
  2. Defect pentagon tile highlight (quasi-crystal mismatch sites)
FORBID: replacing with square grid, springs
A PACKING: ACES display RGBA in A

---

SHADER: ascii-glyph
IDENTITY: Luminance-driven ASCII cells with spring lens densification and ripple scramble
KEEP VERBATIM: glyphSize/brightness/colorAmount/densityBoost; spring [133..136]; ripple scramble
ADD (2 native ideas):
  1. Phosphor persistence smear on character index changes (compare to C)
  2. CRT horizontal scanline mask modulating glyph brightness
FORBID: replacing with bitmap font atlas, new springs
A PACKING: ACES display RGBA in A

---

SHADER: voronoi-zoom-turbulence
IDENTITY: Per-cell zoom pulses and site-boundary shear conveyors on a Voronoi grid
KEEP VERBATIM: cellDensity/turbulenceSpeed/zoomIntensity/mouseInfluence; zoom pulses; boundary shear; fast-motion
ADD (2 native ideas):
  1. F2−F1 edge neon rim along Voronoi boundaries (native to this grid)
  2. Bass-driven centroid inflation pulse (cells breathe from site center)
FORBID: kaleidoscope overlay, new springs
A PACKING: ACES display RGBA in A

---

SHADER: kinetic_tiles
IDENTITY: Traveling wave tile cascade with rotating bevel shear and spring cursor
KEEP VERBATIM: gridDensity/mouseRadius/rotationAmt/tileScale; wave cascade; bevel shear; spring [133..138]
ADD (2 native ideas):
  1. Staggered domino row delay (wave front delayed by floor(cell.y))
  2. Grout mortar compression darkening where neighboring tiles overlap
FORBID: replacing tiles with particles, new springs
A PACKING: ACES display RGBA in A

---

SHADER: hyperbolic-dreamweaver
IDENTITY: Hyperbolic disk tiling distortion with depth-aware alpha and anti-moiré LOD
KEEP VERBATIM: tileCount/curvature/aberration/glowIntensity; hyperbolicDist; fwidth LOD
ADD (2 native ideas):
  1. {7,3} hyperbolic distance band coloring (native geometry palette)
  2. Geodesic thread weave along tile edges in the Poincaré disk
FORBID: Euclidean kaleidoscope rewrite, springs
A PACKING: ACES display RGBA in A

---

SHADER: digital-crease
IDENTITY: Kawasaki origami crease with spring local fold, held deepen, chromatic folding
KEEP VERBATIM: foldCount/depth/softness/chromaticOffset; spring [133..138]; paperTex; exact C fold memory
ADD (2 native ideas):
  1. Valley-fold ambient occlusion on concave crease side
  2. Wet-glue seam highlight along the spring crease ridge
FORBID: replacing with cloth sim, new springs
A PACKING: ACES display RGBA in A

---

SHADER: kaleido-scope-grokcf1
IDENTITY: Multi-segment kaleidoscope mirror with rotation, zoom, and ring offset
KEEP VERBATIM: segments/rotation/zoom/ringOffset; kaleido fold; ring structure
ADD (2 native ideas):
  1. Segment seam glow along mirror boundaries (native kaleido beat)
  2. Counter-rotating inner ring wedge at half angular speed
FORBID: psychedelic tunnel rewrite (that's kaleido-scope main), new springs
A PACKING: ACES display RGBA in A
