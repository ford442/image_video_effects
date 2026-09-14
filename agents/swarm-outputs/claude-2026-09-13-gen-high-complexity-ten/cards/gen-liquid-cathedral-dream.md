# Idea Card — gen-liquid-cathedral-dream

```
SHADER: gen-liquid-cathedral-dream
IDENTITY: tiers of melting stained-glass arch windows, spires and rose tracery over racing floor caustics, drag-refracted by the pointer, with click rose-window shock fronts and melt-offset colour history.
KEEP VERBATIM: melt warp field, columns/tier cell grid, arch/spire/window/roseTracery/floorCaustic masks, cosine stained-glass palette(), ripple rose fronts, pointer drag refraction + pink drag glow, melt-offset exact C history blend, structure-based alpha/depth, slider roles (x spire density, y melt speed, z refraction, w stained hue).
EXISTING IDEAS: none named (no Ideas: line).
ADD:
  1. Lead cames — each window is divided into leaded panes (radial + tier-ring came lines in window-local polar coords); the lead lines darken the glass and each pane gets its own hue offset, so windows read as real leaded stained glass. Native: this effect is stained glass; cames are how it is built.
  2. Molten glass drips — per-column hashed drips hang below each arch window, lengthening with Melt Speed and bass, their bead tips glowing in the pane colour and feeding the floor caustic. Native: the cathedral is "melting"; drips are the melt made visible on the existing arch grid.
FORBID: springs, extra ripple systems, new palettes (reuse palette()), extraBuffer state, dataTextureB, replacing the arch grid.
A PACKING: ACES display RGBA (C read via exact textureLoad as colour history) — unchanged.
```
