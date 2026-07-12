# Thermal Vision — retry upgrade notes

**Base preserved:** heat-signature gradient, FBM sensor noise, audio-reactive sensitivity, depth fade, sensitivity/color-range/noise/blur params.

**New visual upgrades added:**
- **Blackbody temperature** — `blackbody()` gives hot spots a realistic blackbody emission tint.
- **Split-tone** — cool shadows and warm highlights are blended based on thermal luma.
- **Hue-preserve clamp** — keeps hue intact when bright thermal whites push channels above 1.0.
- **Vignette** — subtle corner darkening focuses attention on the centre of the thermal view.

**Other changes:**
- Semantic alpha still combines source alpha, heat and bass.
- Kept the canonical 13-binding header, `@compute @workgroup_size(16,16,1)`, ACES tone map and IGN dither.
- JSON features updated with `blackbody-temperature`, `split-tone`, `hue-preserve-clamp`, `vignette`.

**Line count:** 102 → 143 (+41 lines).
