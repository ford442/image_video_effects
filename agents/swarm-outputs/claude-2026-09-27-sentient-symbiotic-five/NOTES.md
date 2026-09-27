# NOTES — Sentient / Symbiotic Five (2026-09-27)

Requested 10; 5 already had `Ideas:` (09-13 / 09-15) and were skipped: gen-sentient-aether-plasma-nebula-moth,
gen-sentient-bismuth-hypercrystal, gen-sentient-cyber-aurora-void-owl, gen-sentient-void-silk-nebula, gen-symbiotic-cyber-mycelium.

## Per shader (ideas are tagged in the WGSL and in the header `Ideas:` line)
- **gen-sentient-aether-flora-biosphere** — kept: stem/petal SDF + smin, petal pulse, camera, cursor chase, click growth seeds, SSS, spores, HDR feedback, 4 sliders.
  Ideas: async per-cell bud-to-open blossoming with scalloped corollas; stamen crown with gold anthers (material 3); phototropic stem bow.
  A packing: raw HDR history, ACES on writeTexture only. Fixed: click ring `pow(negative,2)` NaN reached camera/ray dir. Noted, not fixed: HEAD's extraBuffer[133..137] kick/smoothMouse state is zeroed each frame (dead).
- **gen-sentient-cyber-chrono-void-serpent** — kept: map(), march, matID 1–4 shading, hex armour, Julia backdrop, fog, ACES, depth, camera, mouse pull.
  Ideas: chrono echoes (phase-lagged translucent spine afterimages); scale-glint hex facets; rift isochrones (Julia trap contours, scaled by Void Density).
  A packing: display RGBA post-ACES, no C read. Base march steps 80→96 (perf cost). Dead-slider audit scanned 0 (updatedParams-only JSON); sliders x/y/z/w verified read by hand.
- **gen-sentient-liquid-neon-fractal-heart** — kept: map() fractal, mouse shock, click fronts, artery bands, history advection, depth, updatedParams.
  Ideas: lub-dub double beat; systolic wavefront ring; oxygenation gradient (magenta core → cyan rim).
  A packing: raw HDR history (0..5) in A.rgb, coverage in A.a; ACES on writeTexture only. Fixed: fresnel pow NaN; history read now 4 exact textureLoad + manual bilinear (was sampler); HEAD wrote un-tonemapped HDR to display with alpha 1.0 → now ACES + semantic alpha (**default look shifts**).
- **gen-symbiotic-cyber-fungal-core-reactor** — kept: map, 100-step march, colours, negative-colour core skin, ripple rings, fog, trail feedback, ACES, depth, controls.
  Ideas: reactor containment ring (precessing torus + hot spot); sporangia pods (Worley); fractured core shell (F2−F1 cracks).
  A packing unchanged (raw HDR trail + nutrient alpha). Fixed: pow(negative,2) NaN in map + spore ring; dead extraBuffer spring — **core now follows raw mouse and click age comes from newest ripple (`time - z`), so core motion/click behaviour changes**. Old writer block left in place, unread.
- **gen-symbiotic-light-networks** — kept: node hashes/drift, growth ramp, link rule, pulse/taper, networkCompetition, colours, intersection mix, mouse pull, flicker, vignette, all 4 slider mappings.
  Ideas: hub-thickened Physarum tubes; evanescent leakage halo; mycorrhizal exchange tint (×(1−Competition)); luciferin afterglow via C (0.95/frame).
  A packing: A.rgb afterglow memory (linear pre-ACES) + display alpha; C read .rgb only, no early return. Node positions hoisted out of the O(n²) loop. JSON features gained upgraded-rgba, audio-reactive, mouse-driven.

## Coordinator corrections
- Removed three idea-named tags from flora JSON `features` (asynchronous-blossoming, stamen-anthers, phototropic-bow): only `upgraded-rgba` / `mouse-driven` are contract tags.

## Not verified
Rendered look of any of the five (no GPU). Perf of chrono-serpent (96+ steps) and flora-biosphere (extra map work) unmeasured.
