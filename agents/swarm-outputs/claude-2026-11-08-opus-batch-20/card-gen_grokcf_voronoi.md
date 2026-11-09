SHADER: gen_grokcf_voronoi / gen-grokcf-voronoi (2nd pass)
IDENTITY: 3-layer parallax Worley fbm, thin-film edge colour, per-cell starfield
KEEP VERBATIM: worley/fbm, palettes, nucleus/crack/comet/triple ideas, params, telemetry A packing
ADD: 1. Delaunay dual spokes — each cell draws its half of the segment to every neighbouring site (true neighbours only), meeting the neighbour's half at the wall; mids brighten
     2. nucleation growth fronts — a ring expands from each site at equal speed and dies at the wall ((F1+F2)/2), the grain-growth process that produces a Voronoi tessellation; bass speeds it
RESCUES: none
A PACKING: unchanged (cell id xy, edge mask, F1)
Stats @160 defaults: before meanL 0.407 std 0.093 → after 0.423 std 0.101.
