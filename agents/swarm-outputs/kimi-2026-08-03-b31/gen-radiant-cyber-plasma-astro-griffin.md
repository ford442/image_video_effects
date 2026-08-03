# Changelog — gen-radiant-cyber-plasma-astro-griffin (visualist, b31)

## Critical bug fix
- Uniforms struct was already canonical (`config, zoom_config, zoom_params, ripples`) — verified and kept verbatim; header bindings 0–12 confirmed canonical.
- **Audio contract violation fixed**: shader read `plasmaBuffer[1].x` (off-limits). Remapped to `plasmaBuffer[0].y` (mids) for bioluminescence and added treble-driven seam shimmer.
- Now writes `writeTexture`, `writeDepthTexture` AND `dataTextureA` every frame (previously only `writeTexture`); resolution guard switched to canonical `u.config.zw`.

## Visual upgrades (role mandate)
- **New geometry**: golden eagle **head + tapered beak wedge** (smooth-min'd onto the body) — the griffin finally has a face.
- **Material-ID driven palettes**: `map()` now returns `(dist, matId, featherCellHash)` — 1=plasma wings, 2=chrono-prism body, 3=golden head; palette, seam placement and glow per material.
- **Faceted chrono-prism normals**: normal quantized to facet centers + per-facet hash albedo variation and specular intensity — shattered-crystal look.
- **2D geometric patterning**: triangular tessellation (`triGridEdge`) carved as glowing cyan/magenta seams across body & head; density scales with Fractal Depth, shimmer with treble.
- **Per-feather variation**: each repeated feather cell gets a hash that phase-shifts its gold↔magenta plasma tint.
- **3-point lighting** (key/fill/back), Blinn-Phong specular on facets, Fresnel plasma rim (kept from original), distance fog into the rift.
- **ACES filmic tonemap** replaces bare gamma; semantic alpha (translucent rift, solid griffin); real near-is-one depth (`1.0 - t/MAX_DIST`, miss = 0); `dataTextureA` packs encoded normal + material tag.
- All 4 sliders live: Warp→anomaly twist, Wing Span→feather width/length, Fractal Depth→displacement + seam density, Plasma Glow→key light audio gain, seam brightness and rim.

## Perf estimate
- Raymarch: 100 steps/px × map (wing repetition + body + head + warp). On hit: +6 map evals for the normal. Background: 4-octave rift only on miss. Roughly original +~15%; comfortable at 1080p.

## Rating prediction
- Was: single flat material, illegal audio read, no depth/alpha semantics. Now: reads as an actual griffin with faceted prism armor. Predict **4.0–4.5 / 5**.

## Gate
- `wgsl_precommit_gate.py` ✅ naga OK, bindgroup compatible. 304 lines (+76 vs 228).
