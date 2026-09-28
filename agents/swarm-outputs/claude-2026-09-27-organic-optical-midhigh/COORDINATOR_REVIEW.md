# Coordinator review — organic/optical mid-high ten (2026-09-27)

Checklist per §9 of `docs/SHADER_UPGRADE_BATCH.md`, applied to each file's Idea Card + diff (as reported by the two implementing forks; naga/gate results independently re-run below in batch closeout).

| Shader | Card before edit | Ideas pointable in diff | KEEP VERBATIM held | Diff not boilerplate-dominated | No shared overlay w/ others | A packing matches C read | Saved params unchanged | Springs/ripples native only | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| gen-bioluminescent-neural-lattice | yes | yes (fire_pulse, afterglow, treble ambient) | yes | yes (real logic, not header-only) | yes (unique mechanic) | yes (display RGBA, now real) | yes | n/a (no click mechanic; none added) | **PASS** |
| gen-biomechanical-hive | yes | yes (afterglow, vein growth, nerve flicker) | yes | yes | yes | yes (raw HDR history, documented) | yes | n/a (no click mechanic; none added) | **PASS** |
| gen-celestial-aether-seraphim-wings | yes | yes (stall-vortex shedding, lift-hue shift) | yes | yes | yes | yes (display RGBA, now exact textureLoad) | yes | n/a (no click mechanic; none added) | **PASS** |
| gen-crystalline-mandala-bloom | yes | yes (facet refraction offset, treble sparkle) | yes | yes | yes | yes (unchanged, already correct) | yes | yes (existing ripple bloom kept, not touched) | **PASS** |
| gen-cosmic-slime-mold | yes | yes (growth-memory accumulator, mature-colony glow) | yes | yes | yes | yes (unchanged) | yes (dead duplicate JSON key removed, not a param change) | yes (existing feeding mechanic kept) | **PASS** |
| gen-cosmic-velvet-hypnosis (2nd pass) | yes | yes (counter-runner, seam glint) | yes | yes | yes | yes (unchanged) | yes | yes (existing drag/ripple kept, not touched) | **PASS** |
| gen-cymatic-plasma-mandalas | yes | yes (3-band interference, sand speckle) | yes | yes | yes | yes (unchanged, now documented in header) | yes | yes (existing spring/vortex kept exactly) | **PASS** |
| gen-depth-refracted-liquid-stained-glass | yes | yes (leaded-came highlight, caustic glow) | yes | yes | yes | yes (unchanged, now documented in header) | yes | yes (existing click-flex kept) | **PASS** |
| gen-cybernetic-ferro-coral | yes | yes (circuit-trace glow, signal pulse) | yes | yes | yes | yes (unchanged) | yes | yes (existing ripple spike-boost kept) | **PASS** |
| gen-chrono-voronoi-mycelium (2nd pass) | yes | yes (cyclic regeneration, rebirth burst) | yes | yes | yes | yes (unchanged, packing intentionally preserved) | yes | yes (existing nutrient/clickSurge kept) | **PASS** |

## Cross-batch checks
- No two files share a generic overlay (no shared spring+ripple+IQ-palette stamp): confirmed — the only two files with springs/ripples that were touched are `gen-cosmic-velvet-hypnosis`/`gen-cymatic-plasma-mandalas`/`gen-depth-refracted-liquid-stained-glass`/`gen-cybernetic-ferro-coral`/`gen-chrono-voronoi-mycelium`, and in each case the pointer mechanic pre-existed natively and was extended, not injected.
- Plumbing-floor fixes (not counted as "the upgrade" themselves): fake→real audio and dead dataTextureA/depth on `gen-bioluminescent-neural-lattice`; dead dataTextureA/C on `gen-biomechanical-hive`; filtering→exact textureLoad and real depth on `gen-celestial-aether-seraphim-wings`; missing `Ideas:` header added on `gen-cymatic-plasma-mandalas`, `gen-depth-refracted-liquid-stained-glass`, `gen-cybernetic-ferro-coral`; dead duplicate JSON params key removed on `gen-cosmic-slime-mold`.
- Both second-pass files (`gen-cosmic-velvet-hypnosis`, `gen-chrono-voronoi-mycelium`) list their prior-pass ideas under `EXISTING (kept)` and only new ideas under `ADD` — no idea was restated as new.
- 10/10 PASS. Batch is complete pending the structural gate re-run below (naga, extraBuffer audit, dead-slider audit, manifest regen, duplicate check, Jest, build).
