# Batch 59 shader notes

- **Liquid Jelly:** retained Batch 51 Kelvin–Voigt motion and added coral/aqua
  lobe orbits, a smooth traveling soliton, faster shear, lime bioluminescence,
  sharper highlights, and bounded advected display history.
- **Liquid Jelly Fluid:** A/C is `velocity.xy / pressure / density`. Corrected
  divergence to use velocity derivatives, pressure projection to use pressure
  neighbors, and curl confinement to use bounded exact neighbor loads. Added
  fast cyan/UV/lime ribbons, KH curls, dye packets, and strong held stirring.
- **Liquid Lens:** A/C is display RGBA. Multi-lobed lens geometry, two orbiting
  lenslets, caustic mesh motion, click rings, and held compression replace the
  old single radial lens.
- **Liquid Magnetic Ferro EM:** A/C is `field.xy / potential / charge`.
  Transported EM state drives black-iron spike lattices, rotating dipoles,
  field packets, pointer compression, and violet/cyan/electric-red arcs.
- **Liquid Metal Prismatic:** A/C stores violet/cyan/amber/red band intensity.
  Flowing silver facets, spectral seams, curvature motion, click fronts, and
  rotating sweeps consume that history truthfully.
- **Liquid Mirror:** A/C is display RGBA. Mercury ribbons, folding seams,
  cobalt/rose accents, reflection sweeps, click waves, and held push/pull make
  Smoothness and the other three controls visibly live.
- **Liquid Oil:** A/C is display RGBA. Black/amber/teal/oxidized-orange petrol
  marbling uses vortex cells, tendrils, a fast conveyor, click stirring, and
  bounded viscous history; all four formerly dead sliders are live.
- **Liquid Oil Iridescence:** A/C is spectral RGB plus normalized thickness.
  Bounded transport/diffusion produces pearl-black islands and magenta/cyan/lime
  contours; held input locally thins the film.
- **Liquid Prism:** A/C is display RGBA. Rotating triangular shards, laser RGB
  dispersion, caustic spokes, fast sweeps, click fronts, and held facet bending
  replace the old pointer-only radial ripple.
- **Liquid Rainbow:** retained Batch 51 trochoidal physics and added a third
  crest layer, braided ribbons, faster transport, stronger film motion, and
  energetic click response while preserving display history.
