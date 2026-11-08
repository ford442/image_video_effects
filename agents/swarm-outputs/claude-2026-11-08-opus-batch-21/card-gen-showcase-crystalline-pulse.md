SHADER: gen-showcase-crystalline-pulse (1st pass)
IDENTITY: voronoi crystal blobs on dark space, diamond-lattice phonon overlay, feedback trails
KEEP VERBATIM: voronoi grid, palette, phonon ω, feedback mix, params
ADD:
  1. Pyramidal facet shading — voronoi now returns offset-to-site; angular sector (5–7 per crystal) lit from upper-left + facet ridges
  2. Phonon wavefront sweep — travelling compression front along k (idle-visible; bass speeds it, mids brighten)
  3. Laue diffraction glints — 6-spot Bragg star + core at crystal sites, flashing as the front crosses (treble adds)
FORBID: generic ripples/springs
A PACKING: display RGBA (ACES)
Plumbing: JSON features were [] → audio-reactive, mouse-driven, upgraded-rgba; Upgraded/Ideas/A packing header lines.
Stats (384px, 20f, t=3, params .5): before meanL .107 meanA .376 → after .090 / .349 (facets darken shadow sides).
