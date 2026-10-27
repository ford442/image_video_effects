# Upgrade Notes — Grok high (`grok/batch-01`, 2026-10-25)

Fifteen shaders. Idea cards are in `BRIEFS.md` (written first). Each file keeps its previous ideas and gains two more. Saved `params` are byte-exact. Eight pasted binding headers were migrated to `#include "_prelude.wgsl"` before the idea edits; that swap is not the upgrade.

Real-GPU visual QA was not run. This VM has no hardware GPU. Gates below are structural.

## Per shader

### cellular-automata-rgba
- Kept: four-species step, taxis, nutrient patches, param roles, raw RGBA packing.
- Added: Holling II satiation on the existing predation term; Allee gate on `avgPlants`.
- Formula: none. A packing unchanged (raw densities). ACES on display only.

### gen-conway-game-of-life
- Kept: three-rule morph, generation counter, prior tints, bezel, strobe, existing pointer spring.
- Added: longevity rings from `generation`; cold rim on the n = 2 survival edge.
- Formula: none. A packing unchanged.

### gen-bioluminescent-reaction-diffusion
- Kept: Gray–Scott 9-point step, luciferin age, quench, front, pointer wake, quorum flash.
- Added: substrate veins from the loaded ∇A; quenched cores mixed back toward deep water.
- Formula: none (9-point Laplacian was already the solver). A packing unchanged.

### gen-dla-copper-deposition
- Kept: deposit / depletion / oxidation / activity, screening, sheen, twin, meniscus.
- Added: oxidation-weighted annealing facets; current crowding on exposed fresh tips.
- Formula: none. A packing unchanged.

### wave-equation
- Kept: damped wave step, foam, caustics, standing nodes, click fronts, wall.
- Added: capillary damping on large `|laplacian|` (§12.2D, this file only); whitecaps locked into the foam channel on steep positive crests.
- A packing unchanged (raw h, v, foam, phase).

### slime-mold-on-video
- Kept: trail / food / drift, anastomosis, streamers, chem packets.
- Added: faster evaporation off dark video; extra deposit where drift aligns with ∇food.
- Formula: none. A packing unchanged.

### galaxy-compute
- Kept: log-spiral arms, nebula, Keplerian motes, halo, optical-depth composite. Slider use stays zoom / pan / opacity. JSON names Gravity / Damping / Star Size / Pattern Opacity were not retargeted.
- Added: trailing dust lane on the same spiral phase; core blackbody (§12.2F) with bass on the bulge and a treble lift on the existing motes.
- Floor: prelude, ACES on display, `dataTextureA` write. A packing: ACES display RGBA (C unread). Features gained `audio-reactive` and `upgraded-rgba`.

### gen-verlet-cloth-wind
- Kept: 64×64 (h, v), gust, hem lead, warp/weft sheen, fold occlusion, pinned row.
- Added: stiffer free side columns; slack panels (near-zero stretch) darken.
- Formula: none. Lattice packing unchanged.

### gen-phyllotaxis-galaxy-spiral
- Kept: golden-angle florets, flat curve, bulge, dust, H II, parastichy.
- Added: outer seed-scale bracts; cool meristem tint on the outer ring.
- Formula: none (PHI was already the layout). A packing unchanged.

### gen-plasma-mandala
- Kept: dihedral fold, diocotron ring, click echoes, filaments, Debye sheath.
- Added: reconnection flash where the filament crosses the ring; density cavity just outside the ring.
- Formula: none. A packing unchanged.

### gen-fractal-tree-growth
- Kept: recursive growth, sway, sap, bark rings, apical buds.
- Added: reaction wood on the compressed side of each bend; lenticel pores between rings.
- Formula: none. A packing unchanged (pre-ACES HDR in A).

### gen-hyperbolic-tree
- Kept: Poincaré tree, metric thinning, leaves, ideal 7/14-gons, horocycles.
- Added: hot rim where branches crowd the boundary; faint 7-fold sector wash in negative space.
- Formula: none. A packing unchanged. No `params` array was added (the definition only has `x-meta.upgrade.params`).

### gen-fireworks-dahlia-burst
- Kept: shell timing, imbrication, midrib, involute, pistil, gravity fall.
- Added: laciniated tip lobes; pollen grains falling from the pistil under the same gravity.
- Formula: none. A packing unchanged.

### particle-dreams-hdr
- Kept: 5-layer vortex accumulation, 16-tap bloom, depth chromatic, fog, slider roles including the layer-speed coupling. A stays raw HDR rgb + exposure.
- Added: energy-conserving bloom (§12.2F, this file only); hollow vortex eye from the existing center distance.
- Floor: mouse glow reads `zoom_config.yz` as 0–1 (it had been divided by resolution). Semantic alpha from layer weight, bloom, and fog. Feature `upgraded-rgba` added. No audio claim.

### nano-assembler
- Kept: cell body, docking seams, ballistic scatter, emission, four slider roles.
- Added: print-head so Assembly Progress is a front across x; hash vacancies that fill only near full progress.
- Formula: none. A packing unchanged (ACES display RGBA).

## Formula use

| §12.2 row | File |
|---|---|
| Deep-water dispersion (D), as capillary damping | wave-equation |
| Blackbody (F) | galaxy-compute |
| Energy-conserving bloom (F) | particle-dreams-hdr |

## Gates

- Naga / bind group / prelude: 15/15 (`wgsl_precommit_gate.py`). Tracker dropped the eight migrated ids. `python3 scripts/test_prelude_migration.py` and `check_prelude_migration.py --base origin/main` passed.
- extraBuffer: pass (0 new reserved-zone writes).
- Dead sliders: pass on the 14 definitions that have a `params` array. `gen-hyperbolic-tree` has no `params` array and is skipped by the auditor, as before.
- Catalog lists regenerated for the two feature-tag edits (`simulation.json`, `advanced-hybrid.json`).
- Vitest: 1433 passed, 1 skipped, 2 failed in `RendererManager.test.ts` (device-loss recovery never reached `idle`; the WebGPU probe reported `probe pipeline failed`). Those tests do not read these shaders. This VM has no hardware GPU.
- `SKIP_WASM_BUILD=1 npm run build`: vite production build succeeded.
- Ledger: `npm run upgrades:record` logged all 15 as upgraded. Thumbnails are stale until a GPU machine refreshes them.
- Real-GPU visual QA: external. Not claimed from this VM.
