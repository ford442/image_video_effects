# NOTES — fork D (sonnet/batch-55): gen-aetheric-tachyon-lattice, gen-ethereal-neon-bismuth-origami

Cards, interrogation and HEAD verification table: `BRIEFS-forkD.md` (read the ADDENDUM at the bottom: the origami rotation decision changed). Scratch/renders: `/tmp/claude-0/-root-image-video-effects/741dbe8f-87a6-4dc9-8039-cfc9fd9fdfde/scratchpad/d/` (`*_head.wgsl`, `v_sheet_a.png`, `v_sheet_o.png`, `o_timestrip.png`, `o_zoom.png`, `az_cmp.png`).
Files: `public/shaders/gen-aetheric-tachyon-lattice.wgsl` (+46/−10), `public/shaders/gen-ethereal-neon-bismuth-origami.wgsl` (+123/−23), the two `shader_definitions/generative/*.json` (description + features only; **`params` byte-exact, no `x-meta` touched**). Nothing committed, no shared generated file touched.

## gen-aetheric-tachyon-lattice — 2 new ideas (3 and 4 in the file; 1–2 existed)
- **KEEP VERBATIM:** 3 params and roles; abs-fold + rot2D loop; three-axis tube SDF; fold-count ember material; junction nodes; sin·sin·sin checker emission; bass terms; mouse-down rd twist; camera drift; ACES; coverage alpha; depth t/20; A = ACES display RGBA.
- **Idea 3 — axial tachyon packets** (domain mechanism, no §12.2 row): `mapEx().w` = the folded coordinate along the nearest tube (argmin of d1/d2/d3, previously discarded); packets `pow(0.5+0.5·sin(axial·7 − t·speed·2.5), 10)` ride on the checker, blue-white warming to the ember hue with fold count; mids scale brightness. Found at `// ── Idea 3` (two places: `mapEx` argmin, shading block).
- **Idea 4 — soft inverse-square aether halo (§12.2F)**: `halo += stepLen/(d²+r0²)` integrated along the existing march (r0 = 0.04 + latticeThickness, no singularity), added as teal `haloAmt = halo·0.002·(0.7+0.8·treble)` to hits and void, and into coverage. Found at `// ── Idea 4`.
- **Floor/hygiene (not ideas):** removed `textureStore(dataTextureB, …, vec4(0.0))` (undocumented zeros; B has no read binding in the single-pass contract); mids/treble now read (all of `plasmaBuffer[0].xyz` used; treble also lifts the junction flash).
- **C decision:** no `textureLoad(dataTextureC)`. A (ACES display RGBA) is read downstream as colour — that is what the write is for; no native idea needs feedback (a trail would be a generic overlay).
- **A packing:** ACES display RGBA (unchanged). **Rescues:** none. Centre-row seam check: none at HEAD (row-diff 0.009 vs 0.025 baseline) → uv left alone.
- **Numbers (256 px, t=4, JSON defaults 3,2,0.05; audio 0.3,0.2,0.1):** meanL 0.084 → 0.152, meanA 0.150 → 0.241, stdL 0.191 → 0.205, NaN 0; 83.8 % px differ >8/255 (the aura reaches most of the frame faintly); void stays near-black. Audio: silent→loud changes the frame (meanL 0.123 → 0.246). SRC=img vs none: 0.0 % (generator ignores source). Exercised: foldCount 1 / 6, speed 5, thickness 0.2, mouse-down, t=12 — all NaN-free and non-blank.
- **Timing (interleaved, mr_ab, 8 cycles, load ~5):** 0.91× min / 0.80× paired-median vs HEAD. (A first reading of 1.47× was taken at load 8–10 and did not reproduce.)
- **Gates:** precommit 1/1, naga-wasm 1/1, dead sliders 0 new, extraBuffer pass.

## gen-ethereal-neon-bismuth-origami — 2 new ideas + 2 rescues + audio floor
- **KEEP VERBATIM:** 4 params and roles; KIFS loop (fold, scale clock, cube SDF); cos palette; world-axis oxide terraces; neon edge lines; crease glow; glow veil; ACES + sRGB encode; coverage alpha; depth write; A = ACES display RGBA.
- **Idea 1 — hopper stair-step rings:** inset = −median(q)·2 of the folded cube (Chebyshev distance to the facet edge), 4 steps per facet at every iteration level; lighting only (stair darkening, riser shadow, lip highlight), faded when a step is < ~2 px (`ringVis`). `mapEx().y/.z`, shading block `// ── Idea 1 (2026-11-22)`.
- **Idea 2 — step-count AO (§12.2E) + exposure-graded oxide:** 5 taps of `map()` along the normal; `ao` multiplies the lit colour (×mix(0.4,1,ao)) and slides the palette phase by `(1−ao)·0.18` (thin film in the recesses). `// ── Idea 2 (2026-11-22)`.
- **R1 rescue — pixel-centred uv:** integer-pixel uv put the centre row exactly in the y=0 fold plane (row-128 luma 0.749 vs 0.858 above / 0.819 below; row-diff 0.118 → 0.024 after).
- **R2 rescue — true rotation in the KIFS loop:** HEAD's `p.x = …; p.y = p.x·s + …` was a shear, not a rotation (SDF not a distance bound; plaid grid at t = 1, 6, 9, 16; hopper inset constant 0.504 ± 0.009 so Idea 1 was impossible). **This changes the default picture a lot** — see numbers. Evidence: `o_timestrip.png` (top HEAD, bottom orthogonal).
- **Audio floor:** `plasmaBuffer[0].x` bass adds `0.06·bass` to the fold/unfold scale clock; `.z` treble ×(1+0.5·treble) on the crease neon; `audio-reactive`/`mouse-driven`/`upgraded-rgba` added to JSON features (+ `audio-reactive` tag). Silent audio == no audio term.
- **C decision:** no C read (stateless SDF; A is downstream display RGBA). **B:** not written.
- **A packing:** ACES display RGBA (unchanged).
- **Numbers (256 px, t=4, defaults 0.5,1,2,1; audio 0.3,0.2,0.1):** meanL 0.822 → 0.791, stdL 0.107 → 0.149, meanA 1.0 → 1.0 (honest: every ray hits at the default), NaN 0; **95.2 % px differ >8/255 vs HEAD** (mostly R2). With the same geometry but no ideas (orth-only variant) meanL 0.804, so the ideas themselves move meanL by ~−0.013 globally — they act locally (recess pockets, facet rings). Audio silent vs default 66.8 %, silent vs loud 91.2 % px (bass breathes the folds — see open call). `scale` 0.2 → dark expanse with a glowing cluster (meanL 0.241, meanA 0.208); `scale` 1.5 → meanL 0.711; mouse-down bloom 3, t=10 all NaN-free. SRC=img vs none 0.0 %.
- **Timing:** R2 alone 0.92× HEAD; ideas on top 1.16–1.28× until `map()` was made distance-only (pixel-identical, 0 px >2/255) → **0.79× paired-median / 0.88× min vs HEAD** (load ~5, 8 cycles).
- **Gates:** precommit 1/1, naga-wasm 1/1 (both files re-run together 2/2 after the last edit), dead sliders 0 new, extraBuffer pass.

## Open calls for the user / coordinator
1. **Origami R2 (rotation) changes every default frame** (95 % px, geometry from big folded planes to a fine facet field). Kept because HEAD collapses to a plaid grid at many clock values and Ideas 1–2 need real facets; reverting = restore 2 rotation lines and drop both ideas.
2. **Origami is still pastel at the default (meanL 0.79):** every ray hits within ~1 unit, so there is no dark expanse unless `scale` is low (≈0.2). The sRGB `pow(0.4545)` after ACES was left alone (catalog-wide convention across ~20 `gen-*` files; removing it only gets 0.82 → 0.67).
3. **Origami bass breath (0.06) is strong:** loud vs silent changes 91 % of pixels > 8/255 (the fractal amplifies a 5 % scale change). Lower the `0.06` in `let unfold = bass * 0.06;` if it reads as jitter on a real GPU.
4. **Aetheric halo lifts the default void from pure black to near-black teal near struts** (meanL 0.084 → 0.152). Gain is the single `0.002` in `haloAmt`; set to 0 to restore the pure-black void.
5. Real-GPU visual QA is external (SwiftShader only here).
