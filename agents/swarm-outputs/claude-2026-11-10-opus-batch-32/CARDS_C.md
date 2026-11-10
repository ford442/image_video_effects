# Fork C Idea Cards (written before WGSL edits)

SHADER: spirograph-reveal (second pass)
IDENTITY: layered epicycloid gear lines around the cursor revealing the image, metallic spectral ink.
KEEP VERBATIM: 3-gear spiro field, param roles (outer/inner teeth, speed, thickness), pen trace, pooling, pressure, ACES display A.
ADD:
  1. Paper tooth — fibrous paper grain modulates ink deposit, so ballpoint lines skip in grain valleys (pen on paper).
  2. Wet-ink persistence — exact textureLoad of C (prev display RGBA) keeps freshly drawn lines as a slowly drying ghost behind the moving gears.
FORBID: ripples-as-idea, IQ palette overlay, new motif.
A PACKING: ACES display RGBA (unchanged).

SHADER: flux-core (first pass)
IDENTITY: cyan fbm lightning arcs radiating from the cursor, conducting to bright image areas, white core.
KEEP VERBATIM: angular bolt_path, param roles (arc sharpness, conductivity, core energy, shockwave), bass/mids reactions.
ADD:
  1. Luma-gradient steering — bolts bend toward bright image edges (angle perturbed by local luma gradient), so they visibly seek conductors.
  2. Forked branches — a thinner, higher-frequency secondary bolt that branches off only where the main bolt is already present.
  3. Ionization tint — arc colour shifts toward violet where it strikes bright surfaces (contact discharge), plus ACES on display.
FORBID: spring cursor, ripple rings, palette swap of the whole look.
A PACKING: ACES display RGBA.
