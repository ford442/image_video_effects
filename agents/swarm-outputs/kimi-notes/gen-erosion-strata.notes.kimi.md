# gen-erosion-strata Notes

- **Surprising behavior:** Domain-warped erosion channels can spontaneously create "bridge" formations where harder strata resist cutting, leaving thin rock spans across channels. Fossil imprints appear pseudorandomly in select layers and darken the exposed surface.
- **Audio reactivity:** Bass drives channel deepening via time-multiplied fBm; mids cycle geological era palettes (desert→coastal→volcanic) using `fract(mids*0.5)`; treble triggers mica sparkle in exposed mineral veins via thresholded hash noise.
- **Alpha semantics:** `alpha = layer_exposure * weathering * (1.0 - haze*0.5)` — exposed foreground canyon walls are fully opaque while distant/background layers fade to translucent atmospheric haze.
