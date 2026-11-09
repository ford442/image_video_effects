SHADER: gen-grid (gen_grid.wgsl, 2nd pass)
IDENTITY: domain-warped FBM lattice with gravity well and moiré sub-grids
KEEP VERBATIM: warp, chroma dispersion, mini-grids, phosphor, cell wash, crease, params, A packing
ADD: 5. overstretch dash fatigue — a line family stretched past ~2x by the warp breaks into hashed dashes
     6. beam-sweep excitation — a raster beam crosses top→bottom; lattice lines just passed glow and decay behind it (bass)
     7. warp-slope emboss — displacement magnitude as height field lit upper-left; cell interiors read as raised tiles
RESCUE: extraBuffer[133..136] spring never persisted → well pinned near (0,0); now on cursor directly (spring removed). Ripple age used time*5 vs real-seconds stamp → clicks dead; now u.config.x.
A PACKING: unchanged (ACES display)
