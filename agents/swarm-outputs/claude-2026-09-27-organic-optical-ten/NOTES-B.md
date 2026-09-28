# NOTES — group B (celestial-weave, chromatic-metamorphosis, plasma-loom)

## gen-celestial-weave
- Kept verbatim: fbm domain-warp lattice, weft/warp sine fields, fiber/knot thresholds, star grid hash/twinkle, constellation neighbor-search + sdSegment, palette(), params/mapping.
- Ideas landed: (1) shimmer-driven traveling thread glint (`glintWeft`/`glintWarp` from the existing weft/warp phase), (2) void-depth star parallax (`nearness`/`starDepthHash` scaling radius, brightness, and a small drift jitter), (3) constellation pulse-travel (`constellationPulse` using each link's along-segment fraction, gated by `smoothBass`).
- Floor fix: packing lie resolved — `dataTextureA` now stores the same `vec4(color, alpha)` as `writeTexture` (previously stored raw fields while C was read as color). Switched `textureSampleLevel` → exact `textureLoad`. Real semantic alpha (fiber/knot/star/constellation coverage) replacing hardcoded `1.0`. Real relief depth from fiber/knot/voidDepth replacing hardcoded zero.
- Did NOT add "mouse-driven" to JSON features (pointer only pans sample position marginally).
- naga: PASS.

## gen-chromatic-metamorphosis
- Kept verbatim: 4-shape smin weight chain (`w0..w3`/phase), independent HSV color field, GGX/Fresnel/AO/grain stack, mouse catalyst mechanic, params/mapping.
- Ideas landed: (1) catalyst stutter-hold (`stutterHold`/`heldMorphT` biases the morph clock toward the nearest integer phase before the existing perturbation releases it), (2) temporal afterimage (`histColor` — genuine exact `textureLoad(dataTextureC, ...)`, first real use of that binding), (3) per-phase seasonal color lean (`materialLean` recomputes the phase weights for color purposes only — leans hue/saturation/roughness so box/capsule reads as a different material than sphere/torus).
- Floor fix (largest lift in the batch): added the missing `dataTextureA` store (was never written); added `acesToneMap()` (none existed) applied to display RGB before store, widened the pre-ACES clamp ceiling from 1.25→4.0 so ACES has real HDR headroom to roll off; fixed `writeDepthTexture` trailing component 1.0→0.0; rewrote the header to the canonical 7-line banner (previously no `Category:`/`Ideas:`/`A packing:`, used `Updated:` instead of `Upgraded:`).
- naga: PASS.

## gen-aetherial-plasma-loom (Track B — second pass)
- Kept verbatim: existing ideas "alternating heddle lanes" and "plasma shuttle necking" untouched in the WGSL and in the header's `Ideas:` line (appended to, not replaced); ring-ribbon SDF, raw un-sprung mouse twist center, params/mapping, ACES display RGBA packing.
- New ideas appended: (1) warp thread-memory ghosting — real bug fix framed as an idea: `dataTextureC` was declared but never read; added a genuine exact `textureLoad` blended into `final_color`, (2) weft-catch spark — `spark_light` accumulates `sample.y * sample.z` (heddle × shuttle) during the existing raymarch loop, no new SDF term, just multiplying two already-returned fields where lane-lift and shuttle-pass coincide.
- JSON fix: de-duplicated repeated top-level keys (`updatedParams`, `supportsDepth`, `supportsDof`, `updated`, `features` each appeared twice, second copy silently won). The surviving `features`/`feedbackPacking` claims ("temporal-feedback", "dataTextureA/C = tone-mapped display RGBA history") are now actually true instead of a packing lie.
- naga: PASS.

All three: no `params` renamed/re-defaulted. No spring/ripple/palette-overlay added to any of the three (each FORBID list respected).
