# Holographic Glitch — retry upgrade notes

**Base preserved:** block glitch, chromatic aberration, holographic cosine tint, scanlines, temporal feedback, glitch/holographic/RGB-shift/flicker params.

**New visual upgrades added:**
- **Fresnel rim** — `fresnelRim()` brightens the viewport edges like a worn holographic plate.
- **Split-tone** — cool cyan shadows and warm amber highlights via `splitTone()`.
- **Film grain** — coarse analog grain overlay driven by the glitch seed block.
- **Hue-preserve clamp** — prevents saturated highlights from clipping to white.

**Other changes:**
- Semantic alpha is still derived from luma and depth.
- Kept the canonical 13-binding header, `@compute @workgroup_size(16,16,1)`, ACES tone map and IGN dither.
- JSON features updated with `fresnel-rim`, `split-tone`, `film-grain`, `hue-preserve-clamp`.

**Line count:** 95 → 128 (+33 lines).
