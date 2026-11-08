SHADER: gemstone-fractures (2nd pass)
IDENTITY: image fractured into rotated voronoi gem shards with physical transmission
KEEP VERBATIM: voronoi shards, per-shard rotation, rutile silk, asterism, pleochroism, params, A packing
ADD: 4. total-internal-reflection rim — band inside each wall shows the shard interior mirrored off the wall (wall normal from two nearest centres; width/strength follow IOR)
     5. conchoidal shell ridges — curved shell ripples from a hashed impact point near fracture walls, scaled by fractureDensity, faded when sub-3px
     6. dispersive fire — edges whose outward normal faces the pointer light flash a spectral hue; IOR dispersion and bass scale it
FORBID: ripple rings, palettes, spring cursor
A PACKING: unchanged ACES display RGBA
HEAD BUG: none found (renders fine at defaults).
Renders: before-gem.png / after-gem-*.png, before-gem-512c.png vs after-gem-512c.png (params 0.15,0.9,0.1,0.8)
