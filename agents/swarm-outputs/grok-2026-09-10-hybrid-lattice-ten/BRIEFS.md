# Hybrid leftover ten — Idea Cards (written before WGSL)

Family: leftover hybrid hex / Voronoi / field / lattice, plus one lighting neon-tube. Native mechanism ideas only. No spring+ripple+IQ stamp. Did not clone today’s kaleido/tunnel/pixel-sort overlays.

Skipped as overlay-rich or already idea-bearing: `hyb-spectral-fbm-displace` (Batch 56), `hyb-kaleidoscope-pulse`, `hybrid-noise-kaleidoscope`, `hyb-iridescent-fbm-glow`, `ripple-bloom`, `hybrid-fractal-feedback` (spring + click + IQ), `hybrid-voronoi-glass`, `hybrid-reaction-diffusion-glass`, `hybrid-spectral-sorting`, `hyb-temporal-fbm-ghost`, `digital-crease` / `interactive-origami` (Batch 61/58E), `neon-quantum-lattice` (phason/conveyor/runners), `electric-contours` (Batch 60). Skipped `hybrid-sdf-plasma` and `hybrid-chromatic-liquid` — WGSL is a duplicated ink/halftone kernel, not the named effect; rewriting would be a new shader.

---

SHADER: hyb-hex-voronoi-distort
IDENTITY: photo pulled toward hex cell centers, with Voronoi distance phasing the pull
KEEP VERBATIM: hex_scale / voronoi_density / distort_amount / effect_mix; nearestHexCenter; voronoi2D; mix(uv, hexCenter)
ADD:
  1. F2−F1 crack ridge — second-nearest site so cell walls are cracks, not only F1 glow
  2. Hex mortar — near hex edges keep the source UV (grout), distortion only in the cell interior
FORBID: springs, IQ palettes, cloning crystal-mosaic lead came
A PACKING: ACES display RGBA (HEAD wrote display to A and never read C)

---

SHADER: hyb-chromatic-circuit
IDENTITY: hex traces over the photo with chroma split along the hex gradient
KEEP VERBATIM: grid_scale / trace_width / chroma_spread / effect_mix; sdSegment spokes; pulse; image-edge boost; chroma along grad
ADD:
  1. Neighbor-gated traces — only draw a spoke if both this cell and the neighbor pass the hash gate (a net, not a star)
  2. Traveling packet — a bright blob at fract(time+rnd) along each live segment’s h
FORBID: springs; cloning hex-circuit vias; treating existing hsv2rgb as the upgrade
A PACKING: ACES display RGBA (HEAD never wrote A)

---

SHADER: hyb-neural-voronoi-feedback
IDENTITY: Voronoi neural cells + FBM drift echo + dust over the photo
KEEP VERBATIM: voronoi_density / feedback_drift / dust_intensity / effect_mix; voronoi2D; fbm drift; dust particles; existing iridescence mix
ADD:
  1. Honest C echo — textureLoad dataTextureC along the drift (HEAD resampled the source and called it feedback)
  2. F2 synapse — glow where F2−F1 is small (cell borders as synapses)
FORBID: springs; treating existing iridescence as the upgrade
A PACKING: ACES display RGBA so next C is color. Write A.

---

SHADER: hybrid-particle-fluid
IDENTITY: curl-noise particles with glowing trails
KEEP VERBATIM: particle_count / flow_speed / trails / glow_size; curlNoise; golden-ratio seeds; 5-step advection; existing palette
ADD:
  1. Exact-C advection — textureLoad C at the back-advected pixel (no filtering sampler on history)
  2. LIC ribbon — two extra taps along velocity so trails read as streamlines (do not grow the particle loop)
FORBID: new springs; increasing the 100-particle loop; IQ as the whole look
A PACKING: ACES on writeTexture; display RGB in A (HEAD already stored color for trails)

---

SHADER: hybrid-magnetic-field
IDENTITY: mouse dipole field lines with fading trails
KEEP VERBATIM: field_strength / line_density / trails / distortion; magneticField 1/r³; orbiting second source; FBM field noise; sin(angle) stripes
ADD:
  1. Opposite-polarity second pole — source2 strength is negative so lines loop N↔S
  2. Exact-C LIC along fieldDir — streamline smear from history, not only the angle sine
FORBID: new springs; cloning magnetic-luma-sort; `u.config.y` as audio
A PACKING: ACES on writeTexture; display RGB in A (HEAD already)

---

SHADER: hybrid-cyber-organic
IDENTITY: hex circuit that grows with FBM moss / tendrils
KEEP VERBATIM: circuit_density / growth / glow / chaos; hex grid; FBM growthPattern; tendrils; cyber/organic mix
ADD:
  1. Exact-C occupancy — moss persists in C.r so growth actually spreads
  2. Photo-luma seed — source luma boosts growthPattern (colonizes the image)
FORBID: springs; Gray-Scott rewrite; cloning chromatic-circuit vias
A PACKING: raw occupancy in A.r (not ACES). ACES on writeTexture only.

---

SHADER: spec-hypercube-projection
IDENTITY: 16-vertex tesseract projected to 2D, photo under the wireframe
KEEP VERBATIM: rot_xw / rot_yz / edge_glow / face_opacity; 16 verts; one-coordinate edges; XW/YZ/XY rotations; held extra XY rot
ADD:
  1. W-silhouette — edges that differ in W (inner cube) get a thicker / cooler glow
  2. Edge-parameter photo — sample the photo at the closest-edge’s h, so the image rides the wire
FORBID: springs; kaleido overlay; IQ as the whole look
A PACKING: ACES display RGBA. HEAD packed edgeColor/edgeDepth in A and never read C (packing lie).

---

SHADER: hex-circuit
IDENTITY: hex overlay that lights on photo edges and mouse pulse rings
KEEP VERBATIM: grid_size / glow_strength / pulse_speed / edge_sensitivity; hex grid; Sobel-ish imgEdge; mouse sin-ring pulse
ADD:
  1. Via pads — disks at hex nuclei when the cell is active
  2. Exact-C contour persist — last frame’s active hexes fade instead of strobing
FORBID: new springs; cloning chromatic-circuit packets
A PACKING: ACES display RGBA. HEAD packed (imgEdge, activeHex, pulse, alpha) and never read C.

---

SHADER: neon-poly-grid
IDENTITY: hex grid that lights under a sprung pointer and leaves a C trail
KEEP VERBATIM: grid-scale / line-width / glow-strength / decay-speed; extraBuffer[133..138] spring; click rings; A.r trail
ADD:
  1. Dual-lattice vertex — glow where the two hex tilings (a vs b) are equally close
  2. Occupied-cell fill — faint interior when the trail is hot (not only the stroke)
FORBID: a second spring; IQ palettes; treating existing FFT cell voice as the upgrade
A PACKING: keep A.r trail (HEAD already). ACES on writeTexture.

---

SHADER: neon-light
IDENTITY: blackbody emission on photo/depth edges with mouse-heated hotspots
KEEP VERBATIM: base_temperature / edge_heating / emissive_gain / thermal_fog; Planck RGB; Sobel luma+depth; Schlick; mouseHot
ADD:
  1. Phosphor persist — exact-C afterglow of last emission (tube phosphor)
  2. Tube-axis stretch — extra glow along the Sobel tangent (neon tube, not a point lamp)
FORBID: springs; holographic overlay; treating blackbody itself as the upgrade
A PACKING: raw phosphor RGB in A (not ACES). Display ACES on writeTexture. HEAD packed telemetry and never read C.
