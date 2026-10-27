# Upgrade Notes — Grok high (`grok/batch-02`, 2026-10-25)

Fifteen shaders, 151–197 lines. Idea cards are in `BRIEFS.md` (written first). Each file keeps its previous ideas and gains two more. Saved `params` are byte-exact. Seven pasted binding headers were migrated with `migrate_to_prelude.py`. `split-flap-display` was migrated by hand: its `dataTextureA` was `read_write`, which the codemod refuses, and the read moved to `dataTextureC`. That swap is not the upgrade.

Real-GPU visual QA was not run. This VM has no hardware GPU. Gates below are structural.

## Per shader

### gen-cymatic-plasma-mandalas
- Kept: integer symmetry, three-band radial sum, shared-node sand, antinode bellies, bass nodal rings, chromatic SDF, click nodes, the existing pointer spring.
- Added: angular Chladni spokes from the fold's angular zeros; sand attenuated on the bellies so grains leave the antinodes.
- Formula: none. A packing unchanged (ACES display RGBA).

### gen-cellular-automata-tapestry
- Kept: Gray–Scott 9-point step, feed/kill roles, anisotropy, weft, nucleus, halo, apoptosis, held-pointer injection.
- Added: pale replenishment wash where `feed·(1−A)` refills empty substrate; hot stoichiometric rim where `A·B²` is high and the pixel is not the nucleus.
- Formula: none. A packing unchanged (raw `nextA, nextB`).

### multi-scale-evolutionary-cellular-gardens
- Kept: `(s1, s2, resource)`, distance-weighted 8-neighbor means, epoch drift, border glow, nurture slider roles.
- Added: founder specks on barren plots only; ochre overgrazing scar where both species are high and resource has crashed.
- Floor: exact `textureLoad` of C (was a filtering sample). A packing unchanged (raw fields). ACES on display only.

### gen-crystal-lattice-growth
- Kept: golden-angle recursion, twins, hopper edge, striae, faceted core, click fronts, slider roles.
- Added: inclusion veils along each segment; a tight highlight at the child-branch junction.
- Formula: none. A packing unchanged (HDR in A, ACES on display).

### gen-fireworks-ring-shell
- Kept: Saturn tilt, empty core, per-shell roll, far-side dimming, rocket, gravity, slider roles.
- Added: Cassini gap — Thickness splits sparks onto two ringlets; rotating spoke lanes around `ang`.
- Formula: none. A packing unchanged.

### gen-psychedelic-moire-flower
- Kept: three moiré stacks, 8/13 petals, the 1.068 detune, held-pointer recenter, chromatic triple sample. Slider roles stay Intensity / Speed / Pattern Density / Color Shift. The definition has `x-meta.upgrade.params` and no `params` array; none was added.
- Added: radial beat at the difference of the two detuned ring frequencies; a 5-lobe vernier gating the existing 8×13 product.
- Formula: none. A packing unchanged.

### gen-buddhabrot-aura
- Kept: `z²+c`, nebulabrot bins, interior dust, orbit spine, escape streaks, dwell isochrones, cardioid, period-2 bulb, click kick.
- Added: smooth escape time (§12.2E) in place of the integer `esc`; a period-3 limb at the bulb nucleus.
- A packing unchanged.

### gen-echo-dunes
- Kept: three ridges, slipface, wind streaks, crest saltation, avalanche tongue, shadow march, mirage, echo rings, bass envelope in `extraBuffer[133]`.
- Added: fine ripples only on the windward (stoss) face; a cornice lip where the crest becomes the slipface.
- Formula: none. A packing unchanged (HDR in A).

### gen-dynamic-tessellation-ornate-fractal-tiles
- Kept: per-tile Julia, blackbody glaze, grout, corner rosettes, equipotential contours, click fronts, slider roles.
- Added: a recessed groove outside the grout highlight; diagonal filigree joining the corner rosettes.
- Formula: none (blackbody was already the glaze). A packing unchanged.

### magnetic-flux-garden
- Kept: dipole march, curl offset, harmonic warp, IQ mix on the bloom only, seed hash, slider roles.
- Added: a neutral sheet on the midplane between the poles; soft inverse-square cores (§12.2F) where the march bails out.
- Floor: exact `textureLoad` of C. A stays `(flux, curl, seed, alpha)`. ACES on display only.

### gen-celestial-yggdrasil-matrix
- Kept: KIFS march, buds, counterflowing sap, xylem rings, mycorrhizal nodes, mouse gravity warp, leaf swarm.
- Added: longitudinal bark furrows cutting the rings; low plasma `flow` mixed toward dry heartwood.
- Formula: none. A packing unchanged. No extra march.

### gravito-phononic-accretion
- Kept: two centers, pull and swirl, exact-C advection, phonon fundamental, shock shells, audio spring, click fronts, slider roles.
- Added: an L1 dimple where the two pulls match, on the existing segment; the second harmonic of the phonon ridge.
- Formula: none. A packing unchanged. Features gained `audio-reactive` and `upgraded-rgba` (both were already true in the WGSL).

### flow-sort
- Kept: luminance-tangent flow, mouse and ripple vortices, Asendorf gate, short LIC, threshold and persistence roles. C stays color.
- Added: a longer LIC pair mixed only where the field ahead agrees; a pale cap where the gate refuses a brighter upstream sample.
- Formula: none. A packing unchanged.

### split-flap-display
- Kept: grid density, mouse radius, auto flip, damping, cosine foreshortening, back-face invert, hinge, magnetic snap to π.
- Added: the lower half renders `angle − lag(velocity)`, so the bottom leaf trails and rests as one plane; a gold drum pip whose height is `fract(angle/π)`.
- Packing fix: state was read from write-only `dataTextureA` at `cell_id` (not this cell). A is now raw `(angle, velocity, 0, 1)`, read back from C at the cell-center pixel. ACES on display only.
- Formula: none.

### gen-crystalline-mandala-bloom
- Kept: polar fold, per-facet hash offset, petal SDF, bass rings, hue rotation, edge sparkle, click blooms, slider roles.
- Added: red/blue samples along the existing facet offset (Cauchy, §12.2F), green kept on the faceted coordinate; a tight dark culet inside the bloom.
- A packing unchanged (HDR in A, ACES on display).

## Formula use

| §12.2 row | File |
|---|---|
| Smooth iteration count (E) | gen-buddhabrot-aura |
| Soft inverse-square (F) | magnetic-flux-garden |
| Cauchy dispersion (F) | gen-crystalline-mandala-bloom |

No row is shared. Springs and ripples were not added. Files that already owned a spring (`gen-cymatic-plasma-mandalas`, `gravito-phononic-accretion`) or a bass envelope (`gen-echo-dunes`) kept it.

## Gates

- Naga / bind group / prelude: 15/15 (`wgsl_precommit_gate.py`). `check_prelude_migration.py --base origin/main` passed. The tracker dropped the eight migrated ids (seven eligible, `split-flap-display` was `binding-type`).
- extraBuffer: pass (0 new reserved-zone writes).
- Dead sliders: pass on the 14 definitions that have a `params` array. `gen-psychedelic-moire-flower` has only `x-meta.upgrade.params` and is skipped by the auditor, as before. All four of those sliders are read.
- Catalog lists regenerated (`generative.json` picks up the two gravito feature tags).
- Vitest: 169 files, 1435 passed, 1 skipped, 0 failed.
- `SKIP_WASM_BUILD=1 npm run build`: vite production build succeeded.
- Ledger: `npm run upgrades:record --ids=…` logged all 15 as upgraded. Thumbnails are stale until a GPU machine refreshes them.
- Real-GPU visual QA: external. Not claimed from this VM.
