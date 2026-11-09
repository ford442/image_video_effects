# NOTES — Fork D (sonnet/batch-25): frost-reveal-crystal, chromatic-mosaic-projector

All numbers are minirender/SwiftShader (rgba32float unless stated, `A16=1` = real rgba16float state). No real-GPU visual QA claimed.
Scratch + evidence: …/scratchpad/forkD/ (renders m_*.png, phase_emu*.py, mr.mjs = SEEDC/A16/MPATH harness, ab_*/e*_ ablations).
JSON: both files UNTOUCHED (frost already carried `upgraded-rgba`/`audio-reactive`/`mouse-driven`, all now true; projector's features all still true; no idea-named tags added; `params` byte-exact).

---------------------------------------------------------------------------------------------------
## 1. frost-reveal-crystal (1st pass) — `public/shaders/frost-reveal-crystal.wgsl`

**Kept verbatim:** 4 params + roles; C/A raw packing (mask, phase, orientation, impurity) — ACES only on writeTexture; frost regrowth + melt (`mask` update); mouse seeding with radial orientation; click melt/shock-freeze rings; fbm frost + uv wobble; hue-wheel crystal colouring; interface highlight; alpha formula; depth passthrough; audio roles (bass → regrowth, mids → supercooling, treble → interface).
**A packing:** unchanged raw sim state; texel (0,0) = (0,0,0,SENT=0.6182) is a state sentinel (invisible corner). impurity (A.a) is never updated at HEAD (pure function of uv) — kept as is.
**Formula names:** Isotropic 9-point Laplacian (§12.2D, frost-only row). Ideas 2/3 are tactic-derived (no row).

| # | Idea (in diff) | Where | Evidence |
|---|---|---|---|
| 1 | six-fold lattice anisotropy → hexagonal ice plates, on an isotropic 9-pt stencil | `lap9` L141, `sobel/frontConf/lattice6/reactRate` L176-182 | slider 0 = disc, 0.5/1 = hexagonal plate (m_frost_star8.png); `anisotropy` was dead at HEAD |
| 2 | forward-scatter frost (4-tap ring, radius ∝ mask·pattern, static per-pixel rotation = grain) | L249-262 | 576 px: dark disc is frosted/fogged, HEAD razor-sharp (frost576_crop.png) |
| 3 | meltwater meniscus (∇mask from loaded neighbours → bead refraction + lit glint/shade) | L230-246, shading L268 | thin lit arc on the melt window at idle (m_frost_cmp.png new_a) |

**Rescues:**
- R1 late-start/stale C — sentinel L16/L94-100, seed on no sentinel, no sim step on the seed frame (`live`), (0,0) loads remap to (1,0), sentinel written L277. TEST: `SEEDC=0.8,0.6,0.4,0.9` and a foreign-sentinel `SEEDC=0.3,0.9,2.0,0.7371` at T0=5 are BIT-IDENTICAL to a clean start (PNG `cmp`); HEAD with the same C differs (meanL .542 vs .537).
- R2 dead spring removed (extraBuffer[133..138] re-zeroed every frame, thread-(0,0) writer raced the readers → the live app already ran the raw cursor; minirender showed a spring that does not exist). Honest raw cursor. No extraBuffer code left (audit: 0 violations).
- R3 dead crystal growth. HEAD reaction and diffusion were both ×growthRate≈0.007: numpy emulation of the exact HEAD update, seed r 0.030 → 0.033 after 1200 frames; minirender 600-frame idle = the same tiny rosette. Now r = 0.66·growth_speed and D = min(0.6·r, 0.2) px²/frame (SUPERSEDED by Review fix 4: first build had fixed D = 0.2 and r = mix(0.06, 0.6, x)), capped 2.2 (explicit-Euler stability at phase≈1): front creeps ≈0.03–0.10 px/frame at 192 px (emulated). R3b orientation inheritance (grown pixels adopt the highest-phase neighbour's orientation; HEAD left them at 0 = one magenta hue). R3c click-ring seeds set the radial orientation like the mouse seeds.

**Default look (honest):** the first seconds are the same frost; what changes is structure. T0=2/24-frame COLD start: HEAD meanL .516 / stdL .166 / meanA .369 → .535 / .150 / .408 (HEAD never seeds at T0=2 so its mask grows from 0; new seeds at mask 0.5 — that is R1, not a tint). Steady state (T0=0, 1200 frames idle): HEAD .535 / .149 / .411 → .536 / .146 / .438. Visible change: crystals now GROW (20 s idle: hexagonal hue-wheel crystal fills the melt window; HEAD: still the tiny seed), frost obscures instead of washing, melt window has a lit rim. Held+moving cursor over 20 s paints crystal along the path (f32 == f16 at 8-bit, mean|Δ| 0.0000).
**Gates:** naga OK (precommit gate), `audit:extrabuffer` PASS (0 new), dead sliders by hand: x growth (mask + reaction), y melt radius, z max_opacity, w anisotropy (lattice6 + anisoFactor) all live; NaN 0 at sliders 1,1,1,1 / 0,0,0,0 / 1,.5,0,1 with held cursor + audio 0.9 in A16. Idle cursor (0.5,0.5) unchanged (window at centre as HEAD). Cost ≈1.2× HEAD (1.35 / 1.28 / 0.98 over 3 back-to-back rounds at 384 px, load-noisy).
**Open:**
- Crystals are never thawed (HEAD neither), so after ~30 s at 192 px (≈130 s at 720p; texel-based, so slower in uv at high res) the whole field is crystal beneath the frost; re-selecting the shader re-seeds. Taste call: a slow sublimation term would be the next idea.
- Crystals are a hexagonal plate with straight hue wedges (the radial-angle hue field is quantised by the 8-neighbour inheritance), not branching dendrites — a plain Allen–Cahn has no Mullins–Sekerka tip instability; would need noise/undercooling.
- `depth-aware` tag is HEAD's (depth is only passed through) — left alone. Everything A16 verified by emulation only, not a real rgba16float GPU.

---------------------------------------------------------------------------------------------------
## 2. chromatic-mosaic-projector (2nd pass) — `public/shaders/chromatic-mosaic-projector.wgsl`

**Kept verbatim:** 4 params + roles; crossed conveyors; per-cell projection direction from the cursor; the 3 channel offsets and the wavelength step (idea 2026-10-09); the diffraction fringe (idea 2026-10-09, now actually on the border); belt runner; blackbody tint; click blast palette; trail mix; ACES + IGN dither; layered alpha compositor; premultiplied output; gravity warp + held boost.
**A packing:** unchanged — pre-ACES trail RGB + feedbackAlpha in A, C read as colour history (exact textureLoad).
**Formula names:** none from §12.2 (no Cauchy, Airy/ghost, bloom). Tactic-derived: lenslet lateral colour (tactics 2/5), dome glint (tactic 5), grout window (tactic 5); border distance = tactic 1.

| # | Idea (in diff) | Where | Ablation (576 px, % px |Δ|>0.05 / >0.15) |
|---|---|---|---|
| 2026-10-09 | cell-boundary diffraction fringe — now on the true border | `fringeEnv/fringePhase` L209-213 | (rescued, see R1) |
| 3 | lenslet lateral colour (R/B ±seed→pixel·cellChroma) | `latOff` L190-198 | 10–12% / 1.2–1.7% |
| 4 | lenslet dome glint (lamp-side specular dot per cell, treble sparkle, lamp falloff) | L225-231 | 7.6% / 1.2–1.8% |
| 5 | unlensed grout window (source passes undisplaced in the border band; colour + alpha) | `groutMask` L204-207, alpha L259 | 10–11% / 0.3–0.8% |

**Rescues:**
- R1 true border distance. HEAD's `voronoi()` returned distance to the SEED and every "edge" term used it: colour ×0.65 and alpha→0.1 at each seed (a dot lattice at 192 and 576 px), and the 2026-10-09 "cell-boundary fringe" was concentric rings around the seed (visible at cellSize .1: HEAD rings-around-dots vs new tiles with parallel fringe, m_cmp_big.png). `voronoi()` now returns `Vor{d1, id, edge, lc}`: second-nearest in the same 9-tap loop, exact bisector distance `dot(0.5(p1+p2), (p2−p1)/|p2−p1|)`, plus the seed→pixel vector. edgeFade / edgeLayer / fringeEnv / fringePhase use `edge`. Default look changes (below).
- R2 bass no longer rescales the lattice (`cellSize·(1+bass·.25)` re-hashed every cell). MEASURED bass 0.4 vs 0: HEAD 21.1% of px >0.1 (mean|Δ| .0457) → new 3.0% (.0261); (HEAD with only that term removed: 0.34%). Bass now jostles the seeds: `voronoiDistort·(1+bass·0.35)`.
- R3 click ring distance is aspect-corrected (HEAD's was an ellipse on non-square canvases).
- Floor: `max(color, 0)` before trail/ACES — measured no visible change at HEAD (mean|Δ| .0006), kept for the new additive terms.

**Default look change (yes):** 192 px idle HEAD meanL .257 / stdL .114 / meanA .736 → .228 / .108 / .672; held+audio .280 / .104 / .749 → .252 / .100 / .685. The dot lattice is replaced by tile borders with grout + edge darkening (more of the image is near a border than near a seed), hence ~11% darker. Treble 0.4 now moves 11.7% of px >0.1 (HEAD 6.1%) — the dome glints are treble-reactive by design.
**Gates:** naga OK, extraBuffer PASS (file has no extraBuffer), dead sliders by hand (x cellSize, y chromatic, z distort+conveyor, w angle+decay, all live); NaN 0 at 1,1,1,1 / 0,0,0,0 / .05,1,1,0 with held cursor + audio 0.9. Cost ≈1.2× HEAD (1.20 / 1.14 / 1.32 over 3 rounds at 384 px).
**Open:** grout "window" reads as a grey band rather than a clean bright gap on this synthetic photo (premultiplied alpha + edgeFade darkening); throw/magnification idea was tried and dropped as invisible (see BRIEFS amendment 2); the 3×3 Voronoi search misses the true nearest seed above ≈0.5 seed jostle — FIXED by Review fix 2 (total jostle soft-capped at 0.55).

---------------------------------------------------------------------------------------------------
## Housekeeping for the coordinator
- `scripts/wgsl_precommit_gate.py` rewrote `reports/wgsl_precommit_report.json` (revert it; I may not checkout).
- No other file touched; no commits/adds.
- `upgrades:record`: both files get the ledger entry; `--ids=frost-reveal-crystal,chromatic-mosaic-projector` form for just this fork.

---------------------------------------------------------------------------------------------------
## Review fixes (coordinator follow-up, 2026-11-09) — evidence in scratchpad/forkD/ (mr2.mjs = review2 harness, sc_*/v3_*/v7_*/fz_*/f5_* renders, phase_emu4.py)

| # | Finding | Verdict | Change | Evidence |
|---|---|---|---|---|
| 1 | projector: C/alpha history unvalidated, `feedbackAlpha` unclamped | FIXED | `prev` = select(0, clamp(prevRaw), prevOk) with prevOk = rgb ∈ [−0.01, 8], a ∈ [−0.01, 1.01] (a NaN fails every comparison → invalid → zero); `feedbackAlpha` clamped to [0,1] | SEEDC=50,50,50,50 / NaN / Infinity / 1e30 at 12 frames: BIT-IDENTICAL to clean (meanL .216, meanA .655); HEAD with 50s: meanL 1.463 / meanA 1.634. In-range SEEDC=0.5,0.5,0.5,0.5 cannot be told from real history: 12 frames mean\|Δ\| 0.0197 (max .047, meanL .236 vs .216), 24 frames 0.0005 (meanL .227 vs .226) — decays at the effect's own trail rate |
| 2 | projector: 3×3 search wrong at high distort | FIXED (capped) | total jostle = min(raw, 0.45) + 0.10·tanh(max(raw − 0.45, 0)/0.10): linear to 0.45 (slider 1, no audio = 0.496 vs 0.5 before), ceiling 0.55; 5×5 declined (25 vs 9 neighbours, far above the 1.25× budget) | 3×3 vs 7×7 at 256 px, % px >0.05: default 0.02, slider 1 0.72, +treble .4 1.68, +treble 1 2.84, +bass 1 +treble 1 3.61 (uncapped HEAD-style 1.0–1.35: 19.6 / 44) |
| 3 | projector: fringe period ~1–2 px at 576/1024 | FIXED | `cellPx = min(res)/cellSize`; fringe frequency = clamp(TAU·cellPx/3.5, 20, 78) rad/cell (period ≥ ~3.5 px; 78 only on big cells) and `fringeFade = smoothstep(5, 12, cellPx)` (no fringe where a cell is < ~5 px, i.e. 192 px at the default 37 cells) | fringe_sizes.png: 192 (fringe off), 576 and 1024 show soft bands, no fine concentric stripes. Remaining: fine fan lines near a few Voronoi vertices (two-nearest-seed bisector is discontinuous there; inherent) |
| 4 | frost: seed shrinks at speed 0 / flattens at low speed + anisotropy 1 | FIXED (small change) | growthBase = 0.66·growth_speed; reaction = growthBase·anisoFactor·lattice6; D = min(0.6·growthBase, 0.2) (diffusion scales with reaction → critical nucleus radius stops growing as the slider drops). Speed 0 = frozen exactly like HEAD | emulation (shader equations, 192 px): speed 0 area 112 → 112 px² (old: 72 / 33 / 0 at frames 100/200/300); axis ratio at anis 1, speed .1/.2: old 2.31 / 2.02 → new 1.13 / 1.25 (default speed .5: 1.30). Default speed .5 unchanged: area 1084 vs 1086 px² @300 frames; real shader 20 s idle vs previous build mean\|Δ\| 0.0001 (0 px >0.05). fz_speed*.png |
| 5 | frost: `live*(…)` does not stop NaN/Inf in inherited C | FIXED | `live` is now a bool; phase step = select(0, step, live); `gm` = select(0, ∇mask, live); orientation adoption already `live &&`; `atan2(sobel)` only reaches the lattice term through select(0, cos6θ, frontConf > 0) (0·NaN impossible, atan2(0,0) never used) | SEEDC=NaN / Infinity / 1e30 / 0.8,0.6,0.4,0.9 / NaN,0,0,0.6182 at T0=5 (late start) and NaN at T0=0 (cold): all BIT-IDENTICAL to clean |

**Declined:** nothing outright. In-range leftovers in the projector (finding 1, 0.5-valued C) are intentionally kept as history — they are indistinguishable from legitimate trail; they converge within 24 frames. Frost's sentinel scheme already covers its own C.
**New default-look numbers** (minirender, T0=2, 24 frames, 3 s; HEAD → first build → fixed):
- frost 192 idle .516/.166/.369 → .535/.150/.408 → .535/.150/.408; held+audio .520/.165/.479 → .538/.156/.513 → .538/.156/.513; 576 idle .536/.150/.408; 576 held+audio .538/.156/.513; cold start T0=0 192: .536/.150/.408; 20 s steady idle .536/.146/.438 (unchanged).
- projector 192 idle .257/.114/.736 → .228/.108/.672 → .226/.109/.671 (fringe now off at 192); held+audio .280/.104/.749 → .252/.100/.685 → .247/.102/.684; 576 idle .218/.112/.666; 576 held+audio .235/.108/.678.
**Gates:** naga OK both; audit:extrabuffer PASS (0 new); dead sliders PASS and by hand (all 4 sliders live in both); NaN 0 everywhere; timing back-to-back at 384 px under load avg ≈5: frost 1.26/1.18/1.26/1.11×, projector 0.98/1.22/1.73(outlier)/1.31× HEAD (median ≈1.2×).
**Housekeeping:** `reports/wgsl_precommit_report.json` is rewritten again by the gate (revert it). No other file touched.
