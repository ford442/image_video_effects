# Neon Edge Radar — retry upgrade notes

**Base preserved:** mouse-centred radar sweep, depth+texture edge detection, audio-reactive neon emission, threshold/speed/width/intensity params.

**New visual upgrades added:**
- **Fresnel rim** — viewport-edge brightening using `fresnelRim()` gives the radar a curved-screen glow.
- **Volumetric fog** — exponential depth fog softens the glow as scene depth increases.
- **Hue-preserve clamp** — `huePreserveClamp()` normalises the brightest channel instead of clipping individual RGB channels.
- **Blackbody temperature** — hot radar contacts get a physically inspired blackbody tint.

**Other changes:**
- Semantic alpha is still derived from `edge * sweep * intensity + rim` modulated by depth.
- Kept the canonical 13-binding header, `@compute @workgroup_size(16,16,1)`, ACES tone map and IGN dither.
- JSON features updated with `fresnel-rim`, `volumetric-fog`, `hue-preserve-clamp`, `blackbody-temperature`.

**Line count:** 102 → 141 (+39 lines).
