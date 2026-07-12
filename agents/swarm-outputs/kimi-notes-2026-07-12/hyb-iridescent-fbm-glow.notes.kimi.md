# hyb-iridescent-fbm-glow — retry upgrade notes

**Base preserved:** domain-warped FBM noise, thin-film iridescence, image glow blend, audio reactivity, fbm-scale/octaves/shift-speed/glow-mix params.

**New visual upgrades added:**
- **Chromatic aberration** — `chromaticAberration()` applies a subtle directional RGB split on bright source areas.
- **Fresnel rim** — `fresnelRim()` adds an iridescent edge glow around the viewport.
- **OkLab mixing** — `oklabMix()` blends the source and glow in perceptually uniform OkLab space instead of raw RGB.

**Other changes:**
- Fixed cube-root handling in the OkLab conversion to avoid `pow()` on negative LMS values.
- Semantic alpha still combines source alpha with glow energy and depth.
- Kept the canonical 13-binding header, `@compute @workgroup_size(16,16,1)`, ACES tone map and IGN dither.
- JSON features updated with `chromatic-aberration`, `fresnel-rim`, `oklab-mix`.

**Line count:** 85 → 147 (+62 lines).
