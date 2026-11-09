# NOTES — Fork B (sonnet/batch-25): crystal-illuminator, crystal-mosaic, crystalline-shatter

Cards + mechanism interrogation: BRIEFS-forkB.md (written before any WGSL edit). All stats: minirender_img (SRC=img), SwiftShader, rgba32float — structural proof only, NO real-GPU visual QA. Default params = JSON defaults. 192 px, 24 frames over T0=2..5; idle = cursor 0.5,0.5 up, audio 0; held = cursor 0.3,0.6 down, audio 0.4,0.3,0.2.
Gates (each file): `wgsl_precommit_gate.py` ✅ naga OK / bindgroup compatible / 0 extraBuffer violations / 0 pasted headers; `audit:extrabuffer` PASS; `audit:dead-sliders` PASS (0 new); sliders also checked by hand (every zoom_params.xyzw consumed + visible). Extremes sweep (params 0,0,0,0 and 1,1,1,1, audio 1,1,1, cursor held at 0.9,0.1): nan = 0 on all three. None of the three uses extraBuffer, C, A-state, or any spring — no state, so no long-run/f16/sentinel issue exists in this fork's files.
Timing (384 px, back-to-back, load-noisy because 4 forks render concurrently): round 1 head/new illuminator 21/33, mosaic 19/32, shatter 45/56; round 2 37/40, 25/22, 68/43 ms/frame → no consistent regression (illuminator adds 1 tap + refract/TIR math: ≈ +8 % in the quieter round; the other two within noise).

---------------------------------------------------------------------------------------------------
## crystal-illuminator  (1st pass + compile RESCUE)  — public/shaders/crystal-illuminator.wgsl, interactive-mouse/crystal-illuminator.json
**Kept verbatim:** 4 params + roles (crystal_size → cell density 5..30, ior → quartz→diamond 1.54..2.42, light_intensity → lamp ×2, purity → roughness/absorption/transmission), animated 3×3 Voronoi seeds, per-cell random facet normal + dome blend by roughness, cursor lamp at z .2 with diffuse + spec(32) + 1/(1+10d²), Fresnel-IOR, absorption path length, alpha = transmission clamp(.2,1), depth passthrough, `u.config.y` ripple count.
**A packing:** ACES display RGBA written to A (HEAD wrote none); C not read.
**Ideas (in the diff):**
- Idea 1 (line ~164) Snell vector refraction — `refract(view, facet_normal, 1/ior)` displaced by a 0.16 slab; replaces `n.xy*0.1*(ior-1)`. **Row: Snell vector refraction (§12.2F).**
- Idea 2 (~174) total internal reflection at the critical angle — pavilion normal from a second hash of the same cell, `cosθc = sqrt(1−1/ior²)`; TIR facets show a 0.55× second-bounce sample + second lamp glint and lose 30 % of their transmission (alpha). `ior` now also sets the TIR share (quartz θc 40.5°, diamond 24.4°). Tactic-derived (not a table row).
- Idea 3 (~125) arris bevel — normal tilts toward the 2nd-nearest site inside `edge_dist < .16`, plus an arris glint (pow 12, treble gain). Tactic-derived; promotes HEAD's thrown-away `edge_dist`/`edge_factor`.
- Idea 4 (~227) click strikes the gem — HEAD's click front (decay 1.8, speed .38 kept) evaluated at each cell SITE (width widened 58→14 so a ring spans ~1 facet), per-facet strength; age-bounded (3.5 s), ≤50 ripples. Re-expression of the file's own click code, not a new overlay.
**Rescues:** R1 two compile errors (duplicate `let aspect`; `__finalRGB`) → naga clean, **id must leave `knownFailures` (ratchet 10 → 9 from this file; coordinator edits src/contracts/wgsl_validation.json)**. R3 full-screen rainbow `clockRings` overlay removed. R4 lamp distance/direction aspect-corrected. R5 unused `edge_factor`/`tir` used or dropped; unclamped output now clamp+ACES.
**Default-look change:** there is no HEAD look (did not compile). Versus the minimal-compile-fix scratch copy (the intent): meanL .359→.377, stdL .178→.151, meanA .447→.372 (192 idle); held .345→.384 / .165→.150 / .447→.372. The rainbow rings are gone; seams now read as chamfered arrises; ~half the facets are TIR (default ior .3 → n=1.80, θc 33.7°). meanA lower because TIR facets transmit less — taste knob is the `0.3 * tir` factor on the transmission line.
**Audio / pointer:** bass → lamp power ×(1+.3·bass); treble → arris glint gain; pointer = lamp (raw cursor, as HEAD). Idle cursor 0.5,0.5 lights the centre (HEAD behaviour). Click response verified with a scratch renderer that injects a ripple: age 0.35 → blob of whole facets flash, age 0.7 → ring of whole facets (difference images in scratchpad/forkB/click_diff.png).
**JSON:** features += `audio-reactive`, `upgraded-rgba` (ACES on display + cards implemented); `x-meta.upgrade.params` added aligned to the existing params; `params`/`tags`/description untouched.
**Open:** Snell slab and TIR share are tuned by eye on a synthetic photo (SwiftShader), not on a real GPU; voronoi cells still follow uv (stretched on wide screens, HEAD layout kept) while the lamp is now round.

## crystal-mosaic  (2nd pass)  — public/shaders/crystal-mosaic.wgsl, geometric/crystal-mosaic.json
**Kept verbatim:** 4 params + roles (density 5..40, rotation, chroma = chromatic edge ×0.01, influence), rhombus lattice (`u_frac`/`v_frac`, 0.866 rows), u=v crease (idea 1 of 2026-09) and lead came (idea 2 of 2026-09), rotation `(rot + influence + bass·.1)·.5` about the tile centre, caustics / env-Fresnel / rim / SSS / border / sparkle terms (magnitudes unchanged, still on the tile core), alpha formula, ACES display RGBA in A, depth passthrough.
**A packing:** ACES display RGBA (unchanged).
**Ideas (in the diff):**
- Idea 1 (~156) chamfered tessera refraction + edge dispersion — `bevel` band (borderDist < ~.19) shifts the sample toward the tile centre by `0.12/density` (small-angle thin prism, **not** the Snell row) and splits R/B along that slope; Chromatic Edge slider = amplitude ×1.6, with HEAD's `(1+bass)` / `(1+treble)` factors. Tactic 4 + 5.
- Idea 2 (~200) chamfer faces lit by the cursor lamp — 4 chamfer normals, Lambert relative to a flat tile + Blinn glint (pow 28), lamp = cursor at z .25; strength = `mouseInfluence·2` (0 → no lamp); treble brightens the glint. Tactic 5 / pointer already owned.
- Idea 3 (~126) hand-set tesserae — per-tile hash adds `(h−.5)·rotation·1.4` rad to the rotation (0 keeps the grid aligned) + ±7 % brightness and a warm/cool tint (`tileTint`). Tactic 4 (second-order the param).
**Rescues:** R1 `triCenter` → true tile centre `(i+.5, j+.5)/(density, .866·density)` (HEAD y drifted up to 0.13 uv and odd rows were shifted half a tile the grid never had: rotation pivot AND mouse-influence centre were off their tile); `triID` kept for hashes/colour. R2 HEAD's `edge` is the tile CORE (flat diamond) not an edge — renamed `core`, its terms keep their tuned strengths on the core; only the chromatic split (named for edges) moved to the chamfer. R3 dead radial `chromaticAberration()` branch (≈4e-5 uv) + its `mix` removed → Chromatic Edge slider now visible at its default 0.3. R4 per-frame `hash21(triID + time·.2)` sparkle strobe → smooth per-tile blink (blink⁴·treble·core). Also guarded `pow` base in `caustics` and clamp before ACES.
**Mistake caught during the work:** first attempt moved rim + env-Fresnel onto the chamfer band (≈ 64 % of each tile); their strengths were tuned for the small core, so the picture washed to white (meanL .480→.556). Reverted those two to `core` and narrowed the band; meanL now .471.
**Default-look change:** yes, moderate. 192 idle meanL .480→.471, stdL .185→.198, meanA .971→.969; held .497→.491 / .160→.181 / .990→.987. Grid keeps the photo colours; tiles now show lit chamfer faces, per-tile variation, colour fringes on strong photo edges (disc outline); tile-centre dots remain (caustic/sparkle/SSS). Verified at density 0 and 1 (tile 5 and 40) and with rotation 0 + influence 0 (aligned grid, no lamp).
**JSON:** unchanged (features already truthful: mouse-driven, audio-reactive, upgraded-rgba, chromatic-edges, …); `params` byte-exact.
**Open:** chamfer width 0.19 / lamp-z 0.25 / glint pow are eyeballed; the lamp's specular ring (tiles at ~0.4 uv from the cursor) may read as a faint halo on very large tiles.

## crystalline-shatter  (2nd pass)  — public/shaders/crystalline-shatter.wgsl, image/crystalline-shatter.json
**Kept verbatim:** 4 params + roles, 5×5 Voronoi + per-cell `refVec`, conchoidal ribs (idea 2), facet-tilt Fresnel + sweeping key-light flash (idea 1), crack lines + glint pulse, hairline branch layer (idea 3), iridescent facet tint, semantic alpha, ACES display RGBA in A (C not read), facet-relief depth. Nothing was broken at HEAD → no rescue.
**A packing:** ACES display RGBA (unchanged).
**Ideas (in the diff):**
- Idea 4 (~137) wedge-scaled Cauchy dispersion — per-facet fringe ∝ `wedge = clamp(.25+.95·|refVec|)` (mean ≈ 1) and R/G/B = +0.73 : 0 : −1.27 (n(λ)=A+B/λ² relative to green, mean magnitude 1, so the default amplitude is preserved); same 3 taps. **Row: Cauchy dispersion (§12.2F).**
- Idea 5 (~183) light-piping crack halo with energy taken from the facet — analytic `exp(−edgeDist·9)·edgeGlow·carry`, facet dimmed by `piped = 0.45·halo`, crack tint added back (no new taps); `carry = clamp(glintPulse,0,1)` so only cracks that carry light glow — HEAD's `glintPulse` goes negative in ~⅓ of cells, which renders those cracks BLACK; that dark-crack subset is kept and leaks nothing. **Row: Energy-conserving bloom (§12.2F).**
**Default-look change:** subtle by design. 192 idle meanL .492→.500, stdL .166→.163, meanA 1→1; held .497→.510 / .170→.163. 576 diff vs HEAD: mean |Δ| ≈ 1.7/255, ~5 % of pixels > 8 levels (soft glow on bright crack walls, blue-weighted fringes on steep facets).
**JSON:** unchanged (features already truthful).
**Open:** the halo is quiet at the default Edge Glow 0.6; it scales with the slider. HEAD's `mouseDist` is still not aspect-corrected (left: identity of the proximity falloff).

---------------------------------------------------------------------------------------------------
## Formula names per file (for COORDINATOR_REVIEW dedup)
| File | §12.2 rows used | Tactic-derived ideas |
|---|---|---|
| crystal-illuminator | Snell vector refraction (F) | total internal reflection @ critical angle; arris bevel; per-facet click glint |
| crystal-mosaic | none | chamfer thin-prism refraction + dispersion; chamfer lamp lighting; hand-set tesserae |
| crystalline-shatter | Cauchy dispersion (F); Energy-conserving bloom (F) | — |
Within budget: Snell (illuminator + glass-wall-prismatic), Cauchy (shatter + chroma-lens-iridescence), energy bloom (shatter + glass-bead-curtain-iridescence).

## Housekeeping
- Did not commit/add/stash. `npm run audit:*` rewrote files under reports/ in the shared worktree; I ran `git checkout -q reports/` once to drop that audit noise (it touches no WGSL/JSON/notes).
- Scratch only (not in repo): scratchpad/forkB/ (HEAD copies incl. the minimal-compile-fix illuminator, `minirender_click.mjs` = renderer copy that injects one ripple, montages, diffs).

---------------------------------------------------------------------------------------------------
## Review fixes (after the coordinator's unanchored review) — supersede the numbers/parameters above where they differ
Measured with the reviewer's harness (scratchpad/review2/mr.mjs: WxH sizes, RAW float dump) plus my copies in scratchpad/forkB/rv/ (`mr_edges.mjs` = same harness with a hard-edged checker + diagonal-stripe source; `reg.py` = share of pixels with max-channel |Δ| > thr overall / near (<0.3) / far (>0.4 height units, aspect-corrected)). All at default params, idle cursor 0.5,0.5, audio 0, one frame at t=3, unless stated. Files touched: crystal-mosaic.wgsl, crystalline-shatter.wgsl, this file. No git write ops (and no `git checkout`); `npm run audit:extrabuffer` rewrote reports/ again — left for the coordinator to revert.

### 1. crystal-mosaic — lamp reach + slider range (FIXED)
Reproduced first: lamp on vs off at 512²: 28.2 % of all pixels > 0.1, 33.9 % far; without the lamp new vs HEAD is 3.6 % far. Cause worth knowing: the lamp term `(lamb − lampDir.z)` GROWS with distance (a flat tile's own `lampDir.z` vanishes at oblique angles), so the lamp lit the far field harder than the near field.
Fix: `lampReach = smoothstep(0.55, 0.10, length(lampVec.xy))` (aspect-corrected height units) and `lampAmt = mouseInfluence * 2.0 * lampReach` — the `clamp(…,0,1.5)` is gone, so the Mouse Influence slider acts over its whole range (0 = off, 0.5 = old default strength, 1 = double). Near-field gain 0.9 → 1.3 to keep the lamp clearly visible once it is local. Four falloffs were tried (smoothstep .55/.10, .50/.12, gaussian exp(−9d²), 1/(1+14d²)); smoothstep .55/.10 had the best far/near trade (0.3 % far vs 9.4 % near @ gain .9 → 0.4 % / 21.6 % @ gain 1.3).
After (final file):
| case | all | near d<.3 | far d>.4 |
|---|---|---|---|
| 512², idle, lamp on vs off, >0.1 | 8.5 % | 21.6 % | **0.4 %** |
| 512², idle, lamp on vs off, >0.05 | 19.0 % | 39.7 % | 2.8 % |
| 512×288 (16:9), idle, on vs off, >0.1 | 4.8 % | 22.0 % | 0.1 % |
| 512², cursor (.3,.6), on vs off, >0.1 | 8.2 % | 22.1 % | 0.1 % |
Slider monotone now (cursor .3,.6, near-field share >0.1): influence 0.5 → 22 %, 0.75 → 31 %, 1.0 → 36 % (was flat above 0.75). Lamp-off vs HEAD far share is 3.6 % = the other new ideas (chamfer refraction/dispersion, tile jitter), unchanged by this fix.

### 2. Aspect correction (FIXED, both pre-existing)
`dToMouse = length((triCenter − mousePos) * (aspect, 1))` in crystal-mosaic; `mouseDist = length((uv − mouse) * (aspect, 1))` in crystalline-shatter. Both zones are round on wide screens now (they were ellipses 1.78× wider than tall at 16:9) — and match the already-aspect-corrected lamp. Default-look change at 16:9 idle (aspect fix isolated, same file with/without it):
- crystal-mosaic 512×288 / 576×324: 0.1 % of pixels > 0.1, 1.4–1.5 % > 0.05, meanRGB .472→.468. (Small because the influence zone only scales rotation by `influence·0.5` rad on tiles ~0.03 uv wide.)
- crystalline-shatter 512×288 / 576×324: 1.3 % > 0.1, 3.8 % > 0.05, meanRGB .498→.499 (the extra shatter amount left of/right of the cursor is gone; the centre disc is unchanged).
- crystal-mosaic final vs HEAD at 16:9 idle (all changes of this fork): 10.5 % > 0.1 overall (27 % near, 5 % far). Square 512²: 13.4 %.
Left alone: the SSS glow `exp(-d²·8)` in crystal-mosaic still uses an unscaled distance, but it is multiplied by the (now round) `influence`, so the product is round-limited.

### 3. crystalline-shatter — Ideas 4 and 5 visibility
**Idea 5 (halo) raised.** `exp(−edgeDist·9)·0.45` → `exp(−edgeDist·5)·0.75` (wider and stronger) and the re-added light made honestly energy-neutral: `col*(1−piped) + crackTint*(0.30+0.55·carry)*piped*0.85` (a mid-grey facet nets ≈ 0, dark facets brighten, bright ones dim). Alternatives measured (k, gain, mean shift vs no-halo on the default photo): 9/.45 +.009; 6/.60 +.016; 5/.75 +.023 (looked slightly pale/hazy beside HEAD); 4/.85 +.030 (frosts facets); final 5/.75 with the neutral re-add +.013. Ablation, halo vs `piped = 0`:
| source | >0.10 | >0.05 | mean RGB on / off |
|---|---|---|---|
| default synthetic photo (smooth) | **4.3 %** | **12.9 %** | .503 / .490 |
| hard-edged checker + stripes | 10.7 % | 20.4 % | .462 / .440 |
(Before: 1.4 % / 6.1 % on the default photo.) Target was ≥ 3 % > 0.05: met ×4. Leak check: a debug build outputting the black-crack subset (`glintPulse < 0 && edgeDist < 0.06`, 8,412 px) shows halo-on vs halo-off max |Δ| = 0.0 in RGB and alpha — nothing leaks into black cracks (gating is analytic: `carry = clamp(glintPulse,0,1)` = 0 there). Visual check at 576: glow along the bright cracks, black cracks still crisp.
**Idea 4 (wedge-scaled Cauchy) amplitude left as is; honest ablation** (Cauchy-wedge vs the old symmetric ±chromatic, same taps), >0.1 / >0.05 share of pixels:
| source | Chromatic .4 (default) | Chromatic 1.0 |
|---|---|---|
| default synthetic photo | 0.3 % / 0.4 % | 0.7 % / 1.1 % |
| hard-edged checker + stripes | 13.6 % / 19.3 % | 26.7 % / 32.3 % |
It is a spacing refinement of a fringe that already existed: on the smooth default test photo (two disc edges) it is nearly invisible (0.3 %), on a photo with many sharp edges it changes 14–27 % of pixels. What a viewer can see: blue thrown ~1.7× further than red (0.73 : 1.27) and steep facets fringing more than flat ones. It is not claimed as a strong visual idea; Idea 5 is the visible one of the two.
**DECLINED (as instructed):** `cellScale*(1+bass*0.5)` re-hash — pre-existing, documented in the JSON ("Bass pulses crack new cells").

### Final gates / default-look numbers after the review fixes
Gate (precommit): crystal-mosaic ✅, crystalline-shatter ✅ (naga OK, 0 extraBuffer violations, 0 pasted headers); `audit:extrabuffer` AUDIT PASS; every `zoom_params.x/y/z/w` is consumed by both files and visible (mosaic x density, y rotation + jitter, z chroma dispersion, w influence + lamp; shatter x cellScale, y refraction/tilt/flash/ribs, z chromatic, w edgeGlow/halo).
192 px (idle cursor .5,.5 / held cursor .3,.6 down / audio .6,.5,.7), nan = 0 everywhere; 576 px the same to ±0.001:
- crystal-mosaic meanL / stdL / meanA: idle .472 / .186 / .970 · held .477 / .175 / .970 · audio .494 / .178 / .993. HEAD idle .480 / .185 / .971 (earlier pass of this fork, before the fixes: .471 / .198 / .969).
- crystalline-shatter: idle .504 / .158 / 1 · held .505 / .157 / 1 · audio .517 / .172 / 1. HEAD idle .492 / .166 / 1 (earlier pass of this fork: .500 / .163).
