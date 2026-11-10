# opus/batch-31 — fork D notes

Measurement: SwiftShader minirender with synthetic photo input (SRC=img), 192², 3 frames to t=2.0, JSON default params, mouse (0.5,0.5) up, audio 0. Δ = % of frame pixels with max-channel |Δ| > 0.02 vs the same file with that one idea switched off. Timing: 12 frames, alternating HEAD/new runs (SwiftShader is noisy ±20%).

## spec-hypercube-projection (second pass)
- Kept verbatim: 16-vertex/32-edge build, rotate4D_XW/YZ/XY chain, perspective projection, lineSDF min-edge search, depth fade, W-silhouette boost, closest-edge photo tint, all 4 param mappings.
- A packing: ACES display RGBA (unchanged).
- Ideas added:
  1. 24 projected square faces (bit-walked base vertex + axis pair, convex point-in-quad), stacked as glass layers `1-(1-a)^count`, tinted by mean face w. Replaces HEAD's centre disc; face_opacity still the face opacity. Δ 8.1 % of frame (≈ the whole tesseract area; cube covers ~8–10 % of frame at default).
  2. Vertex nodes: 16 glints sized by 4D perspective, treble sparkle. Δ 1.7 % of frame (~20 % of cube area), peak Δ 0.49.
  3. W-parallax refraction: photo under faces offset toward each face centroid by its mean w. Δ 4.8 % of frame (~half the cube area).
- Audio: mids (declared but unused at HEAD) now breathe the 4D camera distance (2.5 → 2.15).
- Perf: bounding-box early-out for faces/nodes; frame time ≈ 1.0–1.1× HEAD (126/122 vs 153/113 ms).
- Total vs HEAD: 19.9 % pixels > 0.02.

## cyber-grid-pulse (second pass)
- Kept verbatim: param mappings, magnetic pull warp, click shockwave loop, wave-bent X lines, luma thickness, dual-lattice dots, X-line packet, scanline, ACES, alpha recipe (+capture term).
- A packing: ACES display RGBA (unchanged).
- Rescues:
  - extraBuffer[133..138] spring cursor removed: host re-uploads (zeroes) the range every frame and thread (0,0) wrote it while the rest of the dispatch read it (race). Raw `zoom_config.yz` now; extraBuffer audit clean.
  - plasmaBuffer[1..8] per-cell "FFT" was dead (only [0] uploaded) → live per-cell hash flicker gated by treble.
  - pixel-centre uv `(gid+0.5)/res`; unused `peak` removed.
- Ideas added:
  1. Pulse-front cell capture: radial pulse crest sampled at each cell centre; captured cells fill with photo luma quantised to 4 neon levels (bass widens the captured set). Δ 5.5 %.
  2. Field-line chromatic split: in the pull zone the lattice is re-evaluated with R/B offset along the pull direction (only the displaced part adds), lines fringe red/blue by pull strength. Δ 7.2 %.
- Perf: ≈ 0.85× HEAD (9–10 vs 11–12 ms; spring removal offsets the extra line evals).

## Gates
wgsl_precommit_gate 2/2, verify-naga-wasm --files 2/2, audit:dead-sliders (2 defs scanned) 0 new, audit:extrabuffer PASS. JSON untouched (features already truthful: mouse-driven, audio-reactive, upgraded-rgba). Audit runs rewrote reports/*.json|md — not staged by this fork.
Real-GPU visual QA: external.
