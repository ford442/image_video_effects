# Claude mixed-eight — Notes

2026-10-19. Eight shaders across simulation, retro-glitch, artistic, interactive-mouse,
advanced-hybrid and distortion. Prelude migration (six files: all except vinyl-scratch and
mosaic-reveal, which already used it) ran first via `scripts/migrate_to_prelude.py` and is
header-only, in its own commit. Saved `params` are byte-exact in every JSON.

| Shader | Kept verbatim | A packing | Ideas in the diff |
|---|---|---|---|
| bitonic-sort | padded smem + bitonic network, key formula + sentinel gate, 4 param roles, mouse direction flip, ripple mask, ACES, edge glow | feedback RGB + semantic alpha (unchanged) | Idea 1 `wNext`/`wPrev`/`runRgb` key-bilateral run tent; Idea 2 `upstream`/`drip`/`histRgb` exact-C drip along the sort axis, in both display and feedback |
| vinyl-scratch | 4 params/mapping, spring [133..138], click kick + stylus marks, spindle wow, 1/r pitch/label/lead-out, C.a sparkle coherence, dust/grain/vignette/warmth/rolloff/dirt, ACES | ACES display RGBA + semantic alpha; C.a sparkle proxy (unchanged) | Idea 4 bow-tie lobe in `grooveReflection` (wrapped `dA` mod π, `lobeWidth`, `gloss`; also fixes the unwrapped light angle that killed the sheen after ~10 s); Idea 5 `trackPos`/`gapDist`/`trackGap` glossy track gaps; Idea 6 `smearA`/`tapP`/`tapM` tangential platter smear |
| mosaic-reveal | 4 params/roles, hex lattice, conveyors, tile-turn front, grout+bevel, C afterimage, flood runner, click fronts, OkLab, ACES, layered alpha | pre-ACES reveal colour RGB + .a = 10 + accumulated alpha (unchanged) | Idea 4 tessera area-mean (5 taps → `colMosaic`); Idea 5 `tilt`/`tN`/`facet`/`glint` hand-set tessera tilt with pointer view vector, mosaic side only |
| cyber-organic | 4 params/roles, cursor+ripple reveal, warp, IQ/OkLab/blackbody palette chain, glow, thin-film rim, split-tone, clamp→ACES→dither, depth | raw fields (vein, scan, reveal, alpha), unchanged; C.z now read back | Idea 1 `valueNoise()` inside `fbm` (HEAD's `hash12(floor(f)+fract(f))` was white noise — visible change, needs GPU QA); Idea 2 `headY`/`headLine`/`afterglow`/`excite` scan-head fluorescence; Idea 3 `prevField` exact C.z → reveal persistence |
| sim-slime-mold-growth-em | agent loop, 3x3 diffuse×decay, E/B fields, field-line deposit, polarity wipe, streamlines, core glow, extraBuffer [133..138], 4 params | raw (trail, E mag, signed B, activity), unchanged; ACES display only | Idea 1 `veinRidge`/`wallMask` tube relief from the diffusion taps; Idea 2 `peristalsis`/`squeeze` shuttle streaming; Idea 3 `growth`/`frontFan` advancing search front (+ alpha) |
| gen-biomechanical-hive-julia | map() hex hive/ribs/biomass/breathing, quaternionJuliaDE + animated c, 100-step march, mouse camera, cosine core hue, spec/rim chitin, fog, 4 params | ACES display RGBA (C unused); depth t/100 | Idea 1 `quaternionJuliaTrap()` → `veinGlow` orbit-trap veins; Idea 2 `hiveAO()` step-count AO; Idea 3 `toCore`/`fall` soft inverse-square core light on the walls. Floor: the previously unused `toneMapACES` now applied; `dataTextureA` written; JSON gains `upgraded-rgba`. Cost: +5 `map()` per hit pixel |
| lenia-on-video | ring kernel + bell growth, video→μ/σ, anisotropic kernel, membrane, bass injection, mouse spawn/clear, ripple species, leniaColor + bloom, 4 params | raw (density, neighborhood, signed growth, video luma), unchanged; ACES only on writeTexture | Idea 3 `shellBeta` β-weighted outer kernel shell; Idea 4 `vidMotion`/`foodBias` motion-fed growth from C.a; Idea 5 `advance`/`retreat` growth-front shading (+ alpha) |
| data-slicer | fp128 slice phase, fbm/wave/bend jitter, voronoi + quasicrystal, packet + C smear, curl RGB split, tints/clicks/sparkle, 4 param roles, alpha/depth | ACES display RGBA (unchanged) | Idea 1 `seam`/`nbrJitter`/`syncGap` torn slice seams; Idea 2 `crush`/`crushX`/`levels` per-slice bit-crush; Idea 3 `dropout` exponential-tail bursts |

## §12.2 formula use

| Shader | Rows |
|---|---|
| bitonic-sort | none verbatim (§12.1 t1 bilateral range weight; t6 history advection) |
| vinyl-scratch | none (§12.1 t1, t3, t5) |
| mosaic-reveal | none (§12.1 t1 box mean; t2/t3 facet glint) |
| cyber-organic | none (§12.1 t1, t2, t6) |
| sim-slime-mold-growth-em | 5-pt Laplacian ridge from existing taps (§12.2D stencil family); rest Physarum biology |
| gen-biomechanical-hive-julia | Orbit trap (E); Step-count AO (E); Soft inverse-square (F) |
| lenia-on-video | none (§12.1 t1 multi-shell kernel, t3, t6) |
| data-slicer | Block DCT quantization (B, adapted); Dropout bursts (B) |

No §12.2 row is used on more than one file.

## Closeout

- Floor: prelude include / 16×16 / exact C loads / A packing as documented / saved params exact.
- Gates: see commit; Naga 8/8 via `wgsl_precommit_gate.py`, extraBuffer audit, dead sliders, catalogs, Jest, `SKIP_WASM_BUILD=1` build.
- Real-GPU visual QA: external. cyber-organic Idea 1 and gen-biomechanical-hive-julia ACES floor change the look most.
