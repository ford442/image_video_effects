# sonnet/batch-22 — fork A notes

Shaders: gen-ethereal-quantum-glass-nautilus, gen-radiant-chrono-glass-nautilus, gen-symbiotic-chrono-mycelium-engine (all 2nd pass).
Only the three `public/shaders/*.wgsl` files were edited by this fork. JSON untouched: `features` tags stay truthful (audio drives plume/pulses/buds/tide, pointer pull/offset unchanged), `params` byte-exact (the mycelium JSON still has no top-level `params`; the app feeds 0.5 x4).
Renders: scratchpad `forkA/out/` (288/480/512/640 px, t=2 and t=9, JSON defaults, idle cursor and a moved/held cursor, audio 0 and (0.5-0.9, 0.3-0.6, 0.2-0.9), param extremes). Gates: `wgsl_precommit_gate.py` 3/3 naga OK, `audit:extrabuffer` PASS (no extraBuffer used), dead-slider audit 0 new (scans 2 defs; the mycelium has x-meta only, so its four sliders — density / glow / warp / mouse — were grepped by hand: all read). Real-GPU visual QA: external.

Numbering note: new ideas continue each file's own `Idea n` comment numbering (ethereal 7-9, radiant 7-9, mycelium 3-5); the briefs numbered them 1-3 per file.

---

## 1. gen-ethereal-quantum-glass-nautilus

Kept verbatim: 4 params and roles; the `n/nf/r0/r1` two-whorl tube map, septa plane, siphuncle, voronoi grit, audio `pulse`; iridescence, env refraction, core glow, pearl nacre luster, edge, lip highlight, siphon jet sparkle, pressure fractures; C mix 0.04; ACES display RGBA in A; depth `1 - d/MAX_DIST`.
A packing: ACES display RGBA (unchanged).

RESCUES (default look changes a lot — HEAD was "sand dunes", not a nautilus)
- R1 `uv.y` flipped (+ `mouse_uv.y`, + env-refraction offset sign) — wgsl:169.
- R2 unbounded flaring slab -> finite shell: turn index clamped to the outermost existing whorl `nfMax = floor(kMax - a/TAU)`, `kMax = ln(SHELL_R)/b`, aperture = a step in the outer edge at the mouth angle; bound sphere `BOUND_R` — wgsl:80-96, 117. (First tried an arc-length end-face term: it overestimates far from the shell, the march jumped over everything — the picture was only visible because the unclipped septa/siphuncle sheets drew it. Replaced by the index clamp, `d*0.85` safety.) Septa/siphuncle are pushed away (+2.0) past the aperture.
- R3 Lipschitz-safe aperture lip: `mix(8, lip, gate)` -> same tube with radius blended 0.4 -> 0.5 by the existing gate — wgsl:111.
- R4 camera elevation 26 -> 42 deg (same orbit radius 4.46) — wgsl:183; unconverged rays are no longer hits (wgsl:209); siphon jet anchored at the real mouth — wgsl:296.
- Measured at default, t=2, 288 px: HEAD meanL 0.605 stdL 0.099 meanA 0.467 (flat sand) -> meanL 0.236 stdL 0.286 meanA 0.234 (shell on a dark sea).
- Known leftover: the siphuncle SDF in HEAD sits at `0.22 r0` while the pixel radius is >= r0, so it never contributes (dead in HEAD, left alone); thin dark ring gaps remain where rays graze whorl grooves.

IDEAS (pointable)
- Idea 7 Beer–Lambert shell absorption (§12.2F, row used) — wgsl:256: `chord = 2*0.4*r*cos(theta_t)` (Snell with the Refraction Index slider), `trans = exp(-(1.8, 0.7, 0.25)*chord)` multiplies `envRefr*0.3 + glow`. Outer whorls abyssal teal, apex clear.
- Idea 8 conchiolin flame stripes (organism artifact, no row) — wgsl:265: `fract(k*16 + warp)` on the clamped nearest-existing-whorl growth coordinate `k` (integer stripes per turn: seam-safe), flank-weighted, faded toward the aperture; darkens surface + nacre + transmitted light.
- Idea 9 siphon plume (no row) — wgsl:221: analytic ray/segment closest approach from the mouth along the growth tangent, cone width 0.22 -> 0.56, billow bands, treble/audio gain, visible against the void and in front of the skin only (`step(pS, d)`). No loop, no extra map().
Formula names: Beer–Lambert (§12.2F). Row budget: 1 row on this file.
Default look change: yes (rescue); ideas visible at default: flame stripes yes, Beer–Lambert tint yes (outer whorls bluer), plume faint at silence, strong with treble.
Perf: HEAD vs current back-to-back (192 px, 24 frames, load-noisy): 703/798 ms -> 294/420 ms (bounded shell terminates rays earlier).

## 2. gen-radiant-chrono-glass-nautilus

Kept verbatim: 4 params and roles; `spiral_a` (angle term + 2 ln r + ticking), the 3 strip SDFs and id mapping, septa + scallops, siphuncle + travelling pulse, `chamberTide`, glow accumulation, Fresnel colours, birefringent lamellae, striae, shatter, mids/treble, alpha/depth; gravity-well rotation.
A packing: ACES display RGBA (unchanged).

RESCUES
- R1 angular seam: `a*tightness` -> `a*arms/(1.5 TAU)`, `arms = max(round(1.5*tightness*TAU), 1)` (slider now quantised to whole arms: 0.5 -> 5 arms, range 1..9) — wgsl:87-91. HEAD had a torn cut arc from the centre to the upper left.
- R2 `uv.y` flipped; gravity-well centre flipped in y so the cursor still pulls where it points (idle cursor unchanged) — wgsl:151 and the `mouseDist` line. The swirl is the mirror image of HEAD.

IDEAS
- Idea 7 escapement recoil ring-down — wgsl:83: `ticking += 0.05*exp(-9 f)*sin(32 f)`, `f = fract(4t)`.
- Idea 8 ratchet-toothed septa — wgsl:99: 36 teeth per turn, `septumThick *= 1 + 3.5*saw`, tooth phase advances `ticking*4` = exactly one tooth per beat. Visible as a zipper of white teeth on the septa at larger radii (frame edges / audio frames).
- Idea 9 cameral liquid level — wgsl:48 (helpers), gated into the plasma-bloom accumulation (wgsl:173) and the interior surface colour (wgsl:198): per-chamber flat horizontal free surface (`hash(g_chamber)` level + slow breathing), liquid keeps the plasma, gas dims, bright meniscus line. Reads as flat horizontal cuts across the violet plasma strips, not as a scanline overlay.
Formula names: none (no §12.2 row). Row budget: 0 rows.
Default look change: yes — seam gone, mirrored, dark navy gas segments in the plasma strips. Measured default t=2, 288 px: HEAD meanL 0.558 stdL 0.172 -> 0.503 stdL 0.205 (512 px). Extremes rendered (tightness 0.1 / 1.0, bloom 0 / 5, refraction 1.0 / 2.5, audio on): all finite, nan 0.
Perf: back-to-back 90/80 ms -> 106/108 ms (+20-35%, load-noisy).
Open items: slider quantisation steps are discontinuous; the cameral level range (+-1.6) is world-space, so wide frames show levels on the visible strips only.

## 3. gen-symbiotic-chrono-mycelium-engine

Kept verbatim: 4 params and roles; the 4-fold KIFS gear; stalk radius `0.1 + fbm noise`; chrono lag; helical wrap; smooth_min union; plasma glow; colour mix; wrapLit; alpha/depth.
A packing: ACES display RGBA (C unused) (unchanged).

RESCUES
- R1 `uv.y` flipped (gear was lit from below), mouse y offset flipped — wgsl:155. The drips at the top and bottom of the HEAD render are NOT a duplicate/flip bug: they are the infinite vertical stalk (`length(pos.xz) - 0.1 - noise`) passing through the gear.

IDEAS
- Idea 3 golden-angle fruiting primordia (§12.2E, row used) — wgsl:78 `sdf_buds` + wgsl:190 cap colour: bud i at height `i*0.55`, azimuth `i*2.39996`, domain repetition over the 2 nearest cells (no unbounded loop), radius swells with bass, pale warm caps; early-out beyond 0.8 of the axis.
- Idea 4 cytoplasmic streaming pulses — wgsl:194: `pow(0.5+0.5 sin(|y|*6 - (t-0.55)*2.4), 6)` masked to the stalk axis and out of the gear, bass-weighted; phase uses the same chrono lag as the net.
- Idea 5 twisted three-strand rhizomorph cord (§12.2E additive domain twist, row used) — wgsl:66: the cross-section angle is twisted `CORD_TWIST*y + lag` before the unchanged radius test, 3 lobes of 0.035. NOTE: briefs described this as a twist applied to the fbm domain; at the app's default density (0.5, no top-level params) the noise is far too low-frequency to show a twist, so the twist is applied to a 3-lobed cross-section instead (same row, same domain-twist idea).
Formula names: Golden-angle layout (§12.2E), Additive domain twist (§12.2E). Row budget: 2 rows, once each.
Default look change: yes (lighting from above after R1; stalk ends carry twisted cord, buds, pulses). Measured default t=2, 288 px: HEAD meanL 0.168 stdL 0.251 meanA 0.266 -> 0.172 / 0.254 / 0.269. The ideas live on the stalk beyond the gear (|y| > 1.4), a small part of the frame; the gear itself is unchanged.
Perf: back-to-back 84/96 ms -> 98/106 ms (+10-17% after the early-outs; +20-55% before).
Open items: buds are small relative to the gear; `sdf_wrap` helix and stalk twist both wind with the lag so they can look like one motion.

---

## Formula names per file (for COORDINATOR_REVIEW)
- ethereal: Beer–Lambert (§12.2F)
- radiant: —
- mycelium: Golden-angle layout (§12.2E); Additive domain twist (§12.2E)

## Coordinator to do
- JSON: none needed; ledger `upgrades:record --ids=gen-ethereal-quantum-glass-nautilus,gen-radiant-chrono-glass-nautilus,gen-symbiotic-chrono-mycelium-engine`; generated lists / search index are the coordinator's.
