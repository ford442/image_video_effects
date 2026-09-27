# NOTES — Organic / Optical Seven (2026-09-27)

Request listed 10 IDs. gen-chromatic-glass-lattice, gen-celestial-prism-orchid, gen-celestial-glass-tornado already carry `Ideas:` and the idea bodies are present in the WGSL — not touched.
Cards: `card-<id>.md` (written before WGSL). Drafts: BRIEFS.md.

| ID | Kept verbatim | A packing | Ideas in the diff (`IDEA n` tags) |
|---|---|---|---|
| gen-abyssal-chrono-coral | fold/smin loop, growthRings, lensing, well math, sediment ripples, 4 params, alpha | ACES display trail (unchanged) | 1 growth-band strata (sawtooth ledges, phase on local_time); 2 red-shift + blue Einstein rim in the well; 3 budding front on tip nodes. Dead extraBuffer spring removed; fres pow base clamped |
| gen-abyssal-silicate-geode-weaver | voronoi/gyroid/smin, geode SDF, mouse well, march, palette, click waves, advection, HDR history | HDR history RGB + semantic alpha; ACES on writeTexture only | 1 agate banding (Voronoi F1 rings, not F2-F1: SDF pins F2-F1 ≈0.2); 2 dew-bead knots on thread domain; 3 thread thickness into thin-film phase (default hue shifts slightly). Filtered C read → manual bilinear textureLoad; alpha 1.0 → semantic |
| gen-aurora-silk | ribbons/band formula, falloff, palette, grade chain, ACES, 4 sliders | display RGBA (was wind/band/shimmer read back as colour — packing lie fixed; trail mix moved post-ACES) | 1 satin sheen from fold slope; 2 warp-thread striations; 3 fold-crease occlusion |
| gen-aurora-borealis-synthesis | fbm march, chromatic R/G/B split, storm-dir mouse, primary-controls tail, params | linear aurora-glow layer (base image excluded) + coverage alpha; writeTexture ACES display | 1 altitude emission palette (replaces dead plasmaBuffer[1..127] LUT); 2 sheared curtain pleats + altitude parallax; 3 age-based click substorm arcs (ripple.w/.z-as-radius bug gone). Slider w also scales drift (×1.0 at default). DEFAULT LOOK CHANGES A LOT |
| gen-bio-luminescent-jelly | bell SDF, 8×5 tentacle chain, params, drift, shockwave, sparkles, ACES tail | raw pulsePhase in A.r, A.g/b=0, A.a=alpha (HEAD's, now documented) | 1 jet propulsion + drift-lag tentacle streaming; 2 lappets, radial/ring canals, horseshoe gonad (innerGlow kept softened); 3 jelly-lit marine snow |
| gen-bioluminescent-abyss | map, 128-step march, camera, seasons, spotlight, alpha model, premultiplied output | ACES display RGBA (rgb + alpha trail) | 1 plume crown (bump/emission, shading only); 2 bacterial mats by nearest-vent distance; 3 click chain-reaction. Fixed: click age on 0.1-scaled clock, ripple→world mapping (spotlight drift after ~20 s), bloom added after colour, A alpha 1.0, filtered C read |
| gen-coral-reef-colony | four slider roles, aragoniteColor, clickFront, caustics, semantic alpha, existing ACES approx | A.rgb ACES display; A.a = skeleton memory (skel*0.9, NOT display alpha) | 1 forking branches (fbm was raw per-pixel hash → value noise; default look no longer grain); 2 C.a skeleton accretion + bleaching; 3 star-lobed polyps retract at pointer |

## Not fixed / open
- coral-reef: colony drift `current*time*0.08` accelerates unboundedly; cells not aspect-corrected; skeleton rates per-frame not dt-based.
- bioluminescent-abyss: A history never reaches writeTexture (pre-existing).
- jelly: tentacles run toward -y, same side as dome (pre-existing quirk, kept); bassSmooth uses constant prev.
- Real-GPU QA external: aurora-synthesis default look, chrono-coral strata cost (raymarch), geode bead density, reef branch density.
