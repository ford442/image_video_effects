# opus/batch-32 — fork B Idea Cards (written before WGSL edits)

SHADER: hyb-neural-voronoi-feedback (second pass)
IDENTITY: image echoed through an FBM-drifting C history under an iridescent Voronoi cell net with F2 synapse seams and neural dust.
KEEP VERBATIM: voronoi2D F1/F2, fbm drift + exact-C echo, dust grid, 4 params (density/drift/dust/mix), ACES display A.
ADD:
  1. Action-potential pulses — bright packets travel along each F2 synapse seam (phase from the seam's along-edge coordinate + per-cell hash), so the net reads as firing, not static.
  2. Soma firing flash — each cell fires on its own hashed period; the interior near the site lights in that cell's iridescent hue and decays (refractory), bass shortens the period.
FORBID: spring cursor, ripple rings, new palette.
A PACKING: ACES display RGBA (unchanged).

SHADER: gen-prismatic-ion-cascade (second pass)
IDENTITY: cursor-anchored angular prismatic ion streams with RGB spectral split, cyclotron wobble and recombination shell.
KEEP VERBATIM: band phase / RGB split / masks, cyclotron gyration, recombination shell, C trail, 4 params.
ADD:
  1. Avalanche beads — charge packets ride outward along each band (radial fract of r*k - time*speed, gated by bandMask), denser with bass.
  2. Magnetic-mirror pinch — bands narrow and brighten as they cross the recombination shell radius (thickness modulated by shell proximity).
FORBID: different motif, palette swap.
A PACKING: ACES display RGBA (unchanged).

SHADER: lidar (second pass)
IDENTITY: depth-slicing LiDAR sweep with Sobel edges, contour rings, point cloud, echo trail and range ticks.
KEEP VERBATIM: scan_pattern modes, sobel, contours, A echo packing (r=echo,g=in_beam,b=dist), 4 params.
ADD:
  1. Incidence-angle return intensity — beam/points dim on grazing surfaces (large depth gradient) and bright on sensor-facing ones, from the existing Sobel magnitude.
  2. Dual-return ghost — a dimmer second-return beam trails the first slice in depth (classic multi-echo LiDAR).
BUG FIX: grid used smoothstep(0.48,0.5,fract) = half-cell slabs (≈50% of screen lit); now thin lines.
FORBID: palette changes, ripple overlay.
A PACKING: A.r echo, A.g in_beam, A.b dist (unchanged).
