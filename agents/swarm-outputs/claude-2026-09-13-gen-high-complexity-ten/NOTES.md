# NOTES — claude-2026-09-13 higher-complexity generative ten

Coordinator: Claude (5 parallel forks, 2 shaders each). Cards in `cards/` were written before each WGSL edit.
All ideas are marked `// Idea N:` in the WGSL.

---

## gen-kaleidoscopic-synapse-bloom
- Kept verbatim: sector fold, axon/branch/runner/node formulas, dendrite web, bridge sparks, click ring loop, drag twist, palette chain, history mix, ACES, slider roles.
- A packing: ACES display RGBA; C read with exact textureLoad as colour history (unchanged).
- Ideas: existing 1 axon runner fronts (L81), 2 counter-rotating dendrite web (L89); NEW 3 refractory wake behind runner fronts (L84–88, bass sets recovery); NEW 4 vesicle release at folded lattice sites (L95–104, treble-lifted, feeds alpha/depth).
- Floor: standard banner added. JSON: +upgraded-rgba.

## gen-kinetic-neo-brutalist-megastructure
- Kept verbatim: 4.0 domain repetition, four massing types, hash height/roughness/neon, GGX/Schlick/Smith, neon pulse, fog, 100-step march, mouse repulsion, C colour feedback, ACES, slider roles.
- A packing: ACES display RGBA; C exact textureLoad colour history.
- Ideas: 1 grinding interlock — `grindStroke()` slides slot cutter/cap/side mass along its joint, friction seam glow (L101, L113–157, L214–219); 2 server-core slits with rack LEDs on neon towers (L221–232).
- Floor fixes: sway read `u.config.y` (click count) → removed; alpha was material id (0–11) → fog-attenuated coverage; depth passthrough → hit distance; cell-id floor/round mismatch fixed; repulsion field now rides 15u ahead of the camera (was fixed at z=5 → pointer went dead). JSON features [] → mouse-driven, audio-reactive, upgraded-rgba.

## gen-klein-bottle-walk
- Kept verbatim: kleinBottlePoint surface, walkU/walkV walk, 4-oct fbm, cross-product normal, orbiting light, hue2rgb audio chain, alpha shape, ACES.
- A packing: ACES display RGBA; C now exact textureLoad.
- Ideas: 1 orientation-reversing seam flip + seam glow (L119–136, L148); 2 walker footprint trail from C (L155–164).
- Floor fixes: sliders were wired one slot off vs JSON names (Walk Speed was dead) → realigned to x Walk Speed / y Texture Density / z Light Intensity / w Color Shift. This fixes wiring to the saved names; JSON unchanged. JSON features [] → audio-reactive, upgraded-rgba (no pointer use).

## gen-kryonic-quantum-aether-fractal-core
- Kept verbatim: fold(), 5-iter map(), audio shatter offset, pointer melt sphere, 80-step volumetric march, calcNormal, dif/spec/fresnel/chromatic edge, void fog, treble tint, depth, slider roles.
- A packing: ACES display RGBA (C not read).
- Ideas: 1 frost-rime orbit trap (L213–216); 2 aether shatter veins on fold mirror planes (L218–222). `foldTraps()` (L93–122) runs once per hit, not per step.
- Floor fixes: banner claimed upgraded-rgba with no ACES → ACES added (1.2 exposure); melt `if` → select with guarded smin k. JSON features [] → mouse-driven, audio-reactive, upgraded-rgba.

## gen-liquid-cathedral-dream
- Kept verbatim: melt warp, column/tier grid, arch/spire/window/rose/caustic masks, palette(), click rose fronts, drag refraction, history blend, alpha/depth formulas, slider roles.
- A packing: ACES display RGBA; C colour history (unchanged).
- Ideas: 1 lead cames dividing windows into hash-tinted panes (L93–104, L121–122); 2 molten glass drips with glowing beads below arches (L106–118, L123–124).
- Floor: standard banner. JSON: +upgraded-rgba.

## gen-liquid-crystal-hive-mind
- Kept verbatim: hex grid + hollow prism walls, height pulse, curl/fbm fluid, 80-step march, palette, wall shading, click fronts, chroma/ACES, slider roles.
- A packing: raw sim state (A.rgb audio envelopes, A.a hive pulse), exact textureLoad; not tone-mapped (unchanged).
- Ideas: 1 polariser birefringence fringes from curl-flow director (L243–244, L344–348); 2 hive relay wave lighting cells outward from pointer cell (L246–251, L350–351, L380–382).
- Floor: banner rewritten. JSON: +upgraded-rgba.

## gen-liquid-metal-cymatic-resonator
- Kept verbatim: standing-wave height (Resonance/Complexity), mouse frequency modulation, normals, camera, 100-step march, sky/sun, iridescence, Fresnel, slider roles.
- A packing: ACES display RGBA; C exact textureLoad (previously misused as "audio").
- Ideas: 1 viscosity drag via C blend (L270–274); 2 Chladni nodal crystallization filigree + treble glints (L242–251); 3 ferrofluid spikes under pointer, bass-grown (L90–95).
- Floor fixes: audio was a filtered sample of C → plasmaBuffer[0].xyz; ACES, semantic alpha, depth, A write added. JSON features added.

## gen-liquid-neon-cyber-metropolis
- Kept verbatim: city SDF (gravity warp, towers, crowns, neon shell, floor), normals, camera, 160-step march + glow, concrete lighting, neon ramp, bloom, fog.
- A packing: ACES display RGBA; C colour history (neon afterglow, max vs ×0.3).
- Ideas: 1 liquid neon rivers down tower veins pooling at bases (L252–256, L292–296); 2 wet-street reflections, 40-step reflection march on puddles (L265–287); 3 warp horizon ring (L258–263).
- Floor fixes: removed `applyGenerativePrimaryControls` shim; audio extrusion read `u.config.y` → plasmaBuffer[0].x; Reinhard → ACES; depth 0 → t/maxDist; alpha + A write. City Density `max(1,30-y)` (near-dead) → `mix(8,5,y)` (default 0.5 ≈ old 6.5). JSON features [] → three tags.

## gen-liquid-neon-topography
- Kept verbatim: simplex, mapTerrain (warp, rotated octaves, ridges), 100-step march, normals, neonPalette, camera, shading chain, sky glow, slider roles.
- A packing: ACES display RGBA; C exact textureLoad feeding existing 0.7 blend.
- Ideas: 1 neon contour lines with every-5th major lines (L221–229); 2 liquid valley pools — ray/plane hit, bass-raised level, ridge reflections, treble shimmer (L244–260).
- Floor fixes: "history" blended readTexture (input image) → C; "audio" was filtered C sample → plasmaBuffer; Reinhard → ACES; alpha 1.0 → semantic; depth + A writes. JSON: features line inserted, formatting preserved.

## gen-liquid-rainbow-glass
- Kept verbatim: noise/fbm, liquidRainbow, liquidLayer, glassRefraction, oilFilm, vortexStir, 9 layers + weights, post chain, ACES, temporal formula, slider roles.
- A packing: colour history `mix(prev*0.96, color, 0.25)`; C now exact textureLoad (was filtering sampler).
- Ideas: 1 dispersive meniscus rims at liquid/glass boundary (L254–262); 2 stir memory — C read back swirled around pointer, fades after release (L341–356).
- Floor fixes: mouse divided by resolution twice (stir stuck in corner) → zoom_config.yz; depth 0 → glass thickness; mouse ifs → held multiplier. JSON features [] → three tags.
