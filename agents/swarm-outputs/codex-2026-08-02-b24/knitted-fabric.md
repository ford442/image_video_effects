# Batch 24: `knitted-fabric`

- Added soft spring-following fabric pull and mouse-down tension using safe
  persistent state slots.
- Added guarded click plucks that propagate as radial yarn ridges from normalized
  ripple positions.
- Added per-stitch FFT shimmer and click-driven relief depth.
- Fixed feedback ownership: display RGBA now writes `dataTextureA`; yarn/pull
  diagnostic masks moved to `dataTextureB`.
- Preserved all four source parameters exactly and added indexed
  `updatedParams`, `supportsDepth`, and click-reactive metadata.
