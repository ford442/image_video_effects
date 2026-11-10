# opus/batch-31 — fork D Idea Cards (written before any WGSL idea edit)

```
SHADER: spec-hypercube-projection
IDENTITY (one sentence): a glowing wireframe tesseract (32 edges, XW/YZ/XY double rotation, 4D perspective) over the photo, inner-cube (W) edges brighter/cooler
KEEP VERBATIM: 16-vertex/32-edge build, rotate4D_* chain, project4DTo2D, lineSDF min-edge search, depth-faded edge glow, W-silhouette boost, photo-at-closest-edge-h tint, rot_xw/rot_yz/edge_glow/face_opacity roles
ADD (second pass; existing ideas kept):
  1. real projected square faces — the 24 tesseract faces point-in-quad tested and stacked as translucent glass layers (count-weighted), replacing the HEAD centre disc; face_opacity keeps its role (it now scales true faces)
  2. vertex nodes — 16 projected vertices as bright perspective-sized glints (size and brightness by 4D w), treble sparkle
  3. W-parallax refraction through faces — photo under each face is offset along the face's projected centroid by its mean w, so stacked cells visibly shift the image (4D lensing)
FORBID on this file: springs, click ripples, IQ palette as the whole look, raymarch
A PACKING: ACES display RGBA (unchanged)
Also: mids (declared, unused at HEAD) breathe the 4D camera distance.
```

```
SHADER: cyber-grid-pulse
IDENTITY (one sentence): a cyan neon grid laid over the photo that pulses radially with bass and is magnetically pulled toward the cursor
KEEP VERBATIM: gridSize/pulseSpeed/distortion/glow param mappings, magnetic pull warp, click shockwave ring loop, wave-bent X lines, luma-thickened lines, dual-lattice dots, X-line packet, scanline, ACES
ADD (second pass; existing ideas kept):
  1. pulse-front cell capture — cells whose centre sits on the radial pulse crest fill solid as photo-luma-quantised neon blocks (Tron cell capture); replaces the dead plasmaBuffer[1..8] fftCell term with a live per-cell hash flicker driven by treble
  2. field-line chromatic split — inside the magnetic pull zone the grid lines are evaluated three times with R/B offset along the pull direction, so bent lines fringe red/blue proportional to pull
FORBID on this file: new spring overlay, IQ palette, oil-slick chroma on the photo
A PACKING: ACES display RGBA (unchanged)
Rescues planned: extraBuffer[133..138] spring (zeroed every frame; thread (0,0) writes while other threads read = race) removed → raw mouse; plasmaBuffer[1..8] is never uploaded (dead fftCell).
```
