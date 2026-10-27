# Upgrade Notes — Grok (`cursor/print-craft-twelve`, 2026-10-27)

Twelve print and craft shaders. Idea cards are in `BRIEFS.md` (written before the idea edits). Each file keeps its mechanism and gains two ideas. Saved `params` are byte-exact.

All twelve pasted headers were migrated with `migrate_to_prelude.py`. That swap is not the upgrade. `paper-cutout` binding 5 was renamed to `non_filtering_sampler` so the migrator would take it.

`impasto-swirl` on main was an unrelated stipple (Sobel dots, sliders wired to dot size, edge, posterize, and ink). The catalog entry and the last oil-paint version are a swirl smudge with drying and canvas tooth. This batch puts that body back, then adds the two ideas. History is `textureLoad` of C. Display is ACES. A stays linear paint RGB with thickness in A.a.

`foil-impression`, `poly-art`, and `cross-stitch` display writes are now ACES. None of them reads C. `x-meta.upgrade.params` was added on `impasto-swirl`, `poly-art`, and `cross-stitch`, mirroring saved params. `impasto-swirl` gained `upgraded-rgba`.

Gates: Naga 12/12, precommit gate 12/12, prelude tracker consistent, extraBuffer clean, dead sliders 0 new on these 12, shader-list and ledger diffs limited to these ids. Vitest 169 files: 1433 passed and 2 `RendererManager` failures on the full run; that file passed 44/44 on an immediate re-run. `SKIP_WASM_BUILD=1 npm run build` succeeded. Real-GPU visual QA was not run. This VM has no hardware GPU.

## Per shader

### impasto-swirl
- Kept: perpendicular swirl of history, brush mask, dry-back outside the brush, thickness in A.a, canvas tooth, thickness-driven saturation.
- Added: a ridge from the slope of stored thickness; a bead of paint where the brush mask is halfway.
- Formula: none. The lip is the brush edge, not the watercolour wet-edge row.

### paper-cutout
- Kept: luma layers, height-weighted shadows, lit core and far rim, per-sheet jitter, click emboss.
- Added: the lit core breaks up along the cut; fibre darkens the sheet, more inside the shadow.
- Formula: paper granulation (§12.2C).

### cmyk-halftone-interactive
- Kept: 15/75/0/45 screens, registration target, feed slur, CMYK persistence in A.
- Added: ink spread peaks around a 50% dot; a hairline of black under the colour rims.
- Formula: none.

### foil-impression
- Kept: foil noise, image-relief normal, press mix, brushed streaks, crinkle at the boundary.
- Added: the specular widens along the existing brush tangent; steep emboss shows paper.
- Formula: none.

### poly-art
- Kept: Voronoi seeds, mouse densify, flat facet shade, border from the second-nearest seed.
- Added: busy detail uses smaller facets; the crease facing the light catches a highlight.
- Formula: none.

### cross-stitch
- Kept: the X, half-stitch in dark cells, satin sheen, mouse unravel, cloth grid.
- Added: a darker knot where a full stitch crosses; needle holes at the cell corners.
- Formula: none.

### knitted-fabric
- Kept: offset courses, strain-thinned yarn, two-ply, heather, click pluck, masks in B.
- Added: odd courses turn the back loop outward; fibres stick into the gaps.
- Formula: none.

### interactive-halftone-spin
- Kept: four screen angles, arc smear, CMYK in A, ghost from last frame's coverage.
- Added: a paper hole where C, M and Y print without K; new ink on old ink goes darker.
- Formula: none.

### dynamic-halftone
- Kept: Euclidean spot, 3×3 pooling, ragged rims, premultiplied coverage alpha.
- Added: dots elongate toward the pointer; the center dot grows where the photo changes.
- Formula: none.

### charcoal-rub
- Kept: reveal state in A.r, laid-paper fibre, vine-dust halo, fade-back.
- Added: the stick takes the photograph's colour; a heavy rub opens the photograph.
- Formula: none.

### sequin-flip
- Kept: hex grid, flip angle, GGX, gold/silver, click fronts.
- Added: a stitch hole near the rim; a bright slit when the disk is edge-on.
- Formula: none.

### stipple-engraving
- Kept: low-discrepancy threshold, tangent hatch, paper fibre, burnish, held pool, click rings.
- Added: dots stretch along the hatch tangent; a pale shoulder sits beside the cut.
- Formula: none.
