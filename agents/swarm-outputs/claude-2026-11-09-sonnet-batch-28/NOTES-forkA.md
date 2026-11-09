# NOTES — fork A (voronoi-chaos, spec-bicubic-crystal, voronoi-faceted-glass)

Evidence: SwiftShader WebGPU render harness (rgba32float, extraBuffer re-uploaded each frame). Structural / PNG proof only — **no real-GPU visual QA claimed.** Renders: HEAD vs new, 192 px (20 frames) and 576 px (6 frames), default params 0.5×4; idle cursor, held cursor (0.3,0.6), audio 0.8,0.5,0.9, click ripple. nan=0 in every render.
Gates (all three): naga-wasm valid 3/3, `wgsl_precommit_gate.py` pass, dead-slider audit PASS (0 new). No extraBuffer use added.

## voronoi-chaos (`public/shaders/voronoi-chaos.wgsl`; JSON features + `upgraded-rgba`, `temporal`)
- KEEP VERBATIM: 4 params (cell scale, chaos, color mix, dot size); swimming seeds + pointer repulsion + bass snap; ridge/spectral colour; dots; mouse highlight; held-trail smear from C; alpha formula (+ crack term); ACES.
- A PACKING: display RGBA history (unchanged).
- Ideas: 1 fracture seams (L183): dark crack + thin lit lip, width 0.03+0.05·chaos. The card said F2−F1; renders showed plain F2−F1 gives long fuzzy wedges for close seed pairs, so the gap is the true distance to the bisector of the two nearest seeds (`dot(0.5(d1+d2), d2−d1)/|d2−d1|`) — closest honest version of the Worley border row. 2 impact shatter (L115): per-neighbour jolt along a hash direction inside each ripple's 0.38 uv/s band, amplitude 0.25+0.6·chaos (cells moves and the sampled tile follows).
- Rescues: R2 (L154) tile colour sampled at the actual pushed seed (`m_sample` = swum + pointer push + click jolt, deliberately NOT the 6 Hz bass snap, so the picture does not flicker); R-phase (L84, L166) no `time*(0.5+mids)` / `time*(3+bass*5)`; audio now phase-modulates the swim and stretches ring frequency; R3 (L63) search started at 1.0 so pushed seeds >1 cell away left cell (0,0) → black holes in HEAD (visible in the HEAD 576 render); start at 8.0.
- Formulae: Worley border distance (F1/F2 bisector).
- Default-look change: yes (cracks everywhere; black holes gone). meanL/stdL HEAD→new idle 0.5107/0.1721 → 0.4923/0.1827; held 0.5906/0.1128 → 0.5854/0.1166.
- Open: HEAD's `mousePos.x >= 0` guard is never false (engine mouse is 0..1) — left alone.

## spec-bicubic-crystal (`public/shaders/spec-bicubic-crystal.wgsl`; JSON unchanged)
- KEEP VERBATIM: 4 params; cell grid, wedge offset, facetEdge, mouse bulge, ripple shocks; Catmull-Rom 16-tap; facet-normal dispersion; edgeGlow; Fresnel seams; C persistence 0.07; alpha; ACES.
- A PACKING: ACES display RGBA (unchanged).
- Ideas: 4 Beer–Lambert wedge absorption (L163): T=exp(−σ·t), t from `wedge`, σ=(1.4,0.55,0.15)·(0.4+1.5·distortion), thin side clear / thick side cyan. 5 internal-reflection twin (L152): one bilinear tap mirrored across the tilt axis, mix = 0.22·smoothstep(|wedge|) + Schlick·seam·0.5 (cap 0.45). Floor: colour clamped ≥ 0 before ACES.
- Formulae: Beer–Lambert (§12.2F), Fresnel–Schlick (reuses the file's seam term).
- Default-look change: yes (darker thick sides, faint mirrored second image). meanL/stdL idle 0.4822/0.2099 → 0.4526/0.2014 after the coordinator halved σ to (0.4+1.5·distortion) (first pass was 0.4208, ~13 % darker).

## voronoi-faceted-glass (`public/shaders/voronoi-faceted-glass.wgsl`; JSON unchanged)
- KEEP VERBATIM: 4 params (Density, Refraction, Shimmer, EdgeSoftness); seed swim + pointer push + ripple shocks; tilt / bevel / glint maths; spectral tint; C persistence 0.08; alpha; ACES.
- A PACKING: ACES display RGBA (unchanged).
- Ideas: 4 bevel dispersion (L147): R/B taps along `outDir`·(0.25+0.75·bevel)+tilt·0.12, scaled by `cauchyScale(0.2)` = (0.887,1,1.197), G stays. 5 frosted panes (L159): `hash22(cellId)` picks 1/3 of the panes → 4-tap rotated cross, radius 0.6–1.4×refraction, 85 % blend; clear panes keep one tap (R/G/B taps now 3 instead of 1 per pixel, +4 on frosted).
- Formulae: Cauchy dispersion (§12.2F). Shared with prismatic-feedback-loop (budget 2); other ideas differ.
- Default-look change: subtle (fringes at rims, soft grass/sky patches in frosted panes). meanL/stdL idle 0.4157/0.2317 → 0.4215/0.2253.
- Open: dispersion is subtle at default Refraction 0.5 — visible mostly at the rim and at high Refraction.
