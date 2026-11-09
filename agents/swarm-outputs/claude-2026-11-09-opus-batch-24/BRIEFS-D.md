# Fork D Idea Cards (written before WGSL)

SHADER: gen-glass-mosaic-liquid-refraction
IDENTITY: domain-warped Voronoi stained-glass panes with lead came over refracted liquid-rippled video.
KEEP VERBATIM: voronoi/worley cells, heightMap ripples, facet-pane tilt, meniscus, came ridge, seed bubbles, 4 param roles (facets/bevel/refraction/ripple speed).
ADD:
  3. antique reams — per-pane draw-line ridges (angle from cell hash) shift the refracted image along one axis; real cylinder-blown glass.
  4. backlit-window sun at the pointer — transmitted through pane tint + Beer–Lambert absorption, blocked by the came (silhouette).
FORBID: ripple shockwaves, IQ palette, springs.
A PACKING: ACES display RGBA (unchanged).

SHADER: spec-cooperative-edge-linking
IDENTITY: Sobel edges linked into per-tile chains by workgroup union-find, coloured by chain id.
KEEP VERBATIM: Sobel, union-find passes, gap bridging, chain-size confidence, per-chain strobe, 3 colour modes, A diagnostic packing.
ADD:
  4. chain terminals — interior edge pixels with exactly one 8-neighbour drawn as bright nodes (where linking stopped).
  5. held-pointer chain pick — atomic per-root flag; touching any member lights the whole linked chain.
FORBID: generic glow overlay, springs, ripples.
A PACKING: diagnostic (gradMag, chainId/256, isEdge, alpha) — unchanged.
