# Claude generative-fourteen — Notes

Per shader: kept verbatim, A packing, §12.2 rows, where each idea lives.

---
<!-- group A -->
# NOTES (after implementation)

## gen-quantum-aether-origami — NOTES
- Kept verbatim: map() geometry and fold planes (fold() only gains a counter), march, thin-film palette bands, shadow, AO, spectralFold, Fresnel rim, crease emissive, fog, existing Idea 1 (jittered C mix) and Idea 2 (chromatic fold creases), param roles.
- A packing: ACES display RGBA (C read as colour history) — unchanged. Header gained `Ideas:` (listing the two pre-existing inline ideas too) and `A packing:`; `Upgraded: 2026-06-28, 2026-10-19`.
- §12.2 rows: E "Fold count as material", E "SDF curvature".
- Where: `var<private> gFolds` + counting in fold() (~L55–61), reset at top of map(); Idea 3 at ~L176 in main() hit block (captured right after `dRaw = map(p)`, before normal/shadow/AO calls overwrite it), applied to `base_col`; Idea 4 at ~L206 (6-tap Laplacian, `creaseWhite` added into colour + alpha luma, scaled by Crease Glow y).
- Floor: clamp ≥0 before ACES (Idea 2's `color.b -=` could go negative).
- Cost: +7 map() calls per hit pixel.

## gen-neural-fractal — NOTES
- Kept verbatim: neuralLayer + activation cycling, all traps, multiTrapColor, Ideas 1–4, vignette, ACES, depth.
- A packing: ACES display RGBA in A — unchanged. `Upgraded: 2026-09-14, 2026-10-19`.
- §12.2 rows: none (neuro-native ideas from tactics 1–3).
- Where: trap-loop records `dendAlong` / `dendSoma2` in the existing `stalk < dendTrap` branch; Idea 5 at ~L244 (node beads, myelin dimming, quantised node-hop impulse); Idea 6 at ~L258 (bouton from d2 at the trap minimum, release = Idea 2 spike phase minus a 1.4 rad delay). Both added into alpha.
- Floor: `pow((dendTrap-0.08)*22, 2)` (negative base, existing Idea 3) replaced with an explicit square; clamp ≥0 before ACES.

## gen-fractal-bioluminescence-spore-network — NOTES
- Kept verbatim: map(), 64-step march and scalar `glow` (still drives mix/quorum/alpha), injection, clicks, quorum, packets, marine snow, hue drift, depth absorb, max(prev·decay) afterglow.
- A packing: ACES display RGBA — unchanged. `Upgraded: 2026-10-10, 2026-10-19`.
- §12.2 rows: F "Beer–Lambert" (Idea 5 only).
- Where: Idea 5 in the march loop (~L176, `glowSea += glowStep·exp(−σ·t)`) and right after `final_col` init (green-normalised tint, capped 1.6); Idea 6 at ~L215, just before the existing afterglow max() (fresh emission × (1 − 0.4·smoothstep(0.35,0.9, luma(C)))).
- Floor: clamp ≥0 before the max/ACES (hueShift can produce negatives).

## voxel-grid — NOTES
- Kept verbatim: box intersect, 24-layer occupancy loop, warp/curl, rotation, pop, fake normal, key/fill/Fresnel, palette mix, mortar AO, axis-face tint, C trail, chromatic shift, premultiplied alpha.
- A packing: ACES display RGBA, premultiplied (C read as premultiplied history) — unchanged; header line made explicit. `Upgraded: 2026-09-11, 2026-10-19`.
- §12.2 rows: none (voxel-native ideas).
- Where: `voxelOccupied()` helper = the loop's exact hash test; Idea 3 at ~L184 (3 layers back, slid along keyDir by depth gained, weights 0.45/0.30/0.15 → `keyShadow` multiplies keyLit and the bevel light); Idea 4 at ~L214 (bevel band inside `box`, light rotated into the cube's local frame).
- Floor: clamp ≥0 before all three ACES calls.

## §12.2 row de-dup across my four files
E fold count as material (origami), E SDF curvature (origami), F Beer–Lambert (spore). No row on more than one file.

## Gates (each file)
naga-wasm: valid ×4; wgsl_precommit_gate: pass ×4; audit:dead-sliders: 0 new (origami JSON has no saved `params`, so 3 scanned); audit:extrabuffer: PASS. No fwidth/dpdx; remaining pow bases are non-negative. No JSON changes.

---
<!-- group C -->
# NOTES (after edits)

## gen-bioreactor-bloom — NOTES
- Kept verbatim: 4 param roles/mappings, fbm warp, grid scroll, nucleus/pulse formulae (pulse phase
  now mixes toward neighbourhood mean only under quorum lock), mitosis bud (Idea 1), necrosis
  (Idea 2), reactivity bloom rings (Idea 3), palette, 3% exact-C blend, ACES, depth.
- A packing: display RGBA (ACES colour + semantic alpha); C read as colour — unchanged.
- §12.2 rows: Beer–Lambert (F) — Idea 6 only.
- Where: Idea 5 `main()` ~L147 (3x3 hash22 loop, quorumLock, pulsePhase) + wash in colour block;
  Idea 4 ~L175 (sdBud/sdCellBody dumbbell membrane, furrowLine darkens colony, contractileRing
  added to colour + alpha); Idea 6 ~L231 (prevLuma -> OD -> transmittance on bloom/poison, haze,
  alpha). Floor: bass envelope moved extraBuffer[0] -> guarded [133] (known baseline violations
  34 -> 33); max(.,0) before ACES.
- JSON: unchanged.

## gen-luminous-cauldron — NOTES
- Kept verbatim: 4 param roles, heatShimmer, swirl convectionWaves, causticPattern (now evaluated
  after the bubble loop with a lens offset), 3-layer bubble grid, collapseRing (Idea 1), meniscus
  (Idea 2), click/stir behaviour, palette, 3% exact-C blend, ACES, depth.
- A packing: ACES display RGBA in A — unchanged.
- §12.2 rows: Snell vector refraction (F) — Idea 3 only.
- Where: new helper `convectionAt()`; Idea 4 inside bubble loop ~L165 (plumeBias on `alive`);
  Idea 3 inside bubble loop ~L181 (hemisphere normal, eta 1.33 refraction, lensOffset, TIR rim)
  + caustics after loop; Idea 5 ~L254 (rotating fbm wisps, mix toward brewScatter, alpha).
  Floor: two `pow(neg, 2.0)` in meniscus -> x*x; max(.,0) before ACES.
- JSON: unchanged.

## gen-xeno-botanical-synth-flora — NOTES
- Kept verbatim: param roles (growth/complexity/depthWeight/glowSpread), branchDensity,
  turingPattern, sdLeaf, leafVeinMask, lSystemIterate, Ideas 1-5, R/G/B encoding, 0.85 input mix,
  6% exact-C blend, alpha functions, ACES, depth passthrough.
- A packing: ACES display RGBA — unchanged.
- §12.2 rows: golden-angle layout (E) — Idea 6 only.
- Where: Idea 6 ~L153 (3-blade rosette loop replacing the single fixed blade; nearest blade's
  frame/len feed veins + stomata); Idea 7 ~L190 (sapF/sapPulse on ridge) + G-channel add +
  coverage. Floor: max(.,0) before ACES.
- JSON: unchanged (definition has no `params`; features still only `upgraded-rgba`, which stays
  truthful).

Gates (all three): naga-wasm valid; wgsl_precommit_gate pass; audit:extrabuffer PASS (0 new);
audit:dead-sliders PASS (0 new). No fwidth/dpdx/pow left. No visual QA claimed.

---
<!-- group D -->
# NOTES (after edits)

## sand-dunes — NOTES
- Kept verbatim: fBm/domain-warp height, slope, crest/bubble, ripple sines, palette, lights,
  GGX/Schlick, SSS, sparkles, wind shadow, haze, trail, alpha, depth, all 4 param roles.
  Only change to an existing term: `rippleMask` becomes `var` and is multiplied by
  (1 - slipface*0.85) — part of Idea 1 (grainflow erases ripples).
- A packing: unchanged — rgb = trail*alpha, a = bass envelope.
- §12.2 rows: none (ideas are dune geomorphology, not a table formula).
- Floor touch-ups: pow() in linear_srgb_to_oklab guarded with max(.,0); trail clamped >= 0 before ACES.
- Idea 1 slipface grainflow tongues: main(), after rippleMask (~L143) + duneColor lightening (~L166).
- Idea 2 brink terminator: main(), after SSS (~L185).
- Idea 3 brink spindrift (exact textureLoad on C, upwind along windDir): main(), before trail (~L216).
- Header: Upgraded: 2026-10-19 added (none before), Ideas:, A packing: lines added.

## neon-edge-pulse — NOTES
- Kept verbatim: Ideas 1–3 (2026-10-05), layer law, vortex, flow, chroma split, weights, fog,
  both alpha functions, depth out, param roles.
- A packing: ACES display RGBA (unchanged); C now read as display colour (Idea 6) — truthful.
- §12.2 rows: none.
- Idea 4 plasma-core whitening: in the layer loop, after edgeHue (~L195).
- Idea 5 discharge striations: in the layer loop (~L202), multiplies into accumulatedEdge.
- Idea 6 phosphor afterglow: after aces(outColor) (~L243), exact textureLoad(dataTextureC).
- Header: Upgraded: 2026-10-05, 2026-10-19; Ideas: appended; A packing note extended.

## generative-turing-veins — NOTES
- Kept verbatim: fields, Gray-Scott constants/update, 3-layer coupling, veinThickness, ridge,
  nutrientFlow, colour mixing (incl. HSV-as-RGB quirk), bass feed pulse, click colony
  extraBuffer[133..136], alpha formula, all param roles. Both defs' saved params untouched.
- A packing: linear colour history RGB (clamped 0..2, pre-ACES) + semantic alpha; C read as colour.
- Floor fixes: C read via exact textureLoad (was filtering textureSampleLevel+u_sampler);
  ACES on writeTexture only; depth now vein relief (was 0); stale "[6..8]" comment -> [134..136].
- §12.2 rows: D "Isotropic 9-point Laplacian" (Idea 1) — used on this file only.
- Idea 1: lapActivator/lapInhibitor (~L80), called from turing_pattern.
- Idea 2: turing_pattern returns reaction in .z; multi_scale_turing .w = p1.z + 0.6*p2.z (~L131);
  sprout glow in main (~L250). Threshold smoothstep(1.6, 2.6) chosen from a numpy port of the
  fBm fields (a*b^2 sum: p50 ~1.0, p75 ~1.6, p95 ~2.5).
- Idea 3: prevC exact load + activator re-feed (~L219); ridge hold in the history blend (~L258).
- JSON: "upgraded-rgba" added to features in BOTH generative-turing-veins.json and
  turing-veins.json (ACES now in WGSL + ideas implemented). params untouched.

---
<!-- group B -->
Group B wrote NOTES inline under each card in BRIEFS.md.

---
## Coordinator amendments

- gen-bioreactor-bloom: Idea 6 (culture turbidity, §12.2F Beer–Lambert) was removed after the group
  finished — Beer–Lambert had landed on three files (bioreactor, spore network, spore-galaxy). The
  file keeps Ideas 4 (cleavage furrow) and 5 (quorum-sensing pulse lock); the bloom rings and poison
  cloud are no longer attenuated by C, and alpha drops the turbidity term. The extraBuffer[0] →
  [133] bass-state move stays.
- aurora-curtain: now passes naga (duplicate `let aspect` removed). Removed from
  src/contracts/wgsl_validation.json knownFailures; ratchet 28 → 27. The post-ACES rainbow
  `clockRings` overlay (IQ cosine palette, a previous pass) was removed as a generic overlay; it
  never rendered because the file did not compile. Click fronts are kept, now in the oxygen-green
  line before tone mapping.
- generative-turing-veins / turing-veins: `upgraded-rgba` added to both definitions (ACES now in
  WGSL, ideas implemented). Saved params byte-identical.
