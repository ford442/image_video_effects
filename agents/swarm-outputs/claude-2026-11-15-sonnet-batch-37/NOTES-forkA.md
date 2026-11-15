# NOTES — fork A (gen-ethereal-cyber-aurora-mantis-shrine, rainbow-cloud)

Both FIRST PASS. Edited only `public/shaders/{gen-ethereal-cyber-aurora-mantis-shrine,rainbow-cloud}.wgsl` and their `shader_definitions/**` JSON. No git commands run. HEAD = 8577b989. Evidence: SwiftShader WebGPU via `agents/mr.mjs`, synthetic photo/depth (`SRC=img`); scratch in `.../scratchpad/forkA/`. **No real-GPU visual claim is made.**

Visibility method (COMMON rule 11): a scratch copy of the final file with ONE idea's contribution removed; metric = % of pixels whose max-channel |Δ| > 0.02 (and > 0.05) between full and idea-off, default sliders, idle cursor, audio 0.

---

## gen-ethereal-cyber-aurora-mantis-shrine

**KEEP VERBATIM held?** Yes for all geometry: mantis capsules/head/arms, lotus petal-fold loop, heart + filaments, material ids 1–4, 4 saved params byte-exact (raw ranges, mappings), orbit camera yaw/time term, click-held warp, chrome/auroral/cyan colour identities, 100-step under-relaxed marcher. Deliberate deviations are the rescues below (R3 mirrors the mist SDF sign — see R3).

**A packing:** ACES display RGBA (`outColor` = writeTexture value; HEAD stored nothing; C is not read for history).

### Ideas (header `Ideas:` line carries all three)
| # | Idea | Where | §12.2 row | Visibility (default sliders, idle) |
|---|---|---|---|---|
| 1 | Aurora curtain sky fused to the lotus `palette()` hue clock (3 folded azimuth sheets, sharp hem, soft top, ray striations) | `auroraSky()` L71–; added to background in `main()` | native | **33.6 %** px > 0.02 (29.4 % > 0.05), mean \|Δ\| 0.117 @576; 31–37 % @192 across t = 0.4–1.5 |
| 2 | Chrome environment reflection: mantis (mat 2) and lotus rim sample the SAME sky at `reflect(rd,n)`, ground-mist tint below the horizon | L322–; mat 2/3 branches | native | 4.4 % px > 0.02 @576, 4.6 % @192 — that is **the whole mantis surface** (it covers ≈ 5 % of the frame); mean \|Δ\| 0.004 over the frame |
| 3 | Heartbeat ring: pulse leaves the heart at `0.55 + 0.6·bass` Hz, travels out through the filaments and washes the body; amplitude = core-pulse slider × (1 + bass) | L298–; heart emissive + mat 2/3 | native | **time-dependent, pointer-/body-local**: 4.9 % (t 0.4) / 6.1 % (t 0.8) / 2.9 % (t 1.2) / 1.3 % (t 1.5) px > 0.02 @192; 6.1 % @576 (t 0.8) |
| 4 (optional) | step-count AO | **not implemented** — frame cost already ≈ HEAD ×1.0–1.2 and the card made it conditional | – | – |

First version of idea 3 was too weak (4.9 / 2.8 / 0.9 / 0.0 % over the same phases); I slowed the ring (3.2 → 2.4·m_scale/beat), widened it (0.28 → 0.42), kept it alive longer (fade 1 − 0.7·phase) and raised the body wash ×2.

### Rescues (card hypotheses R1–R5, all verified at HEAD)
- **R1 CONFIRMED** (code): `textureLoad(dataTextureC,(0,0)).x` used as "audio" in `map()` and `main()`; HEAD never stores A, so it was a dead 0. Now `plasmaBuffer[0].x` (`bassMap` in map, `bass` in main). At idle bass = 0 the heart pulse is bit-for-bit the HEAD expression `pulse·(1+0)`.
- **R2 CONFIRMED**: no `dataTextureA` store, alpha hard `1.0`, gamma `pow(.4545)` instead of ACES. Now ACES(·×1.25) on clamped-≥0 colour, A = display RGBA, alpha = `0.18 + 0.82·cover` (surfaces 1, aurora/mist by their light).
- **R3 CONFIRMED by render + code**: screen rows grow down but `u_cam = (0,1,0)`, so HEAD was upside-down: lotus rendered ABOVE the mantis, mantis head-down, and the "ground" mist was really a ceiling (`mist_d = −p.y + 2`) that read as a floor only because of the flip. `map()`'s own mouse-warp already used `−mouse_uv.y`, i.e. the author assumed y-up. Fix: `uv.y = −uv.y` and `mist_d = p.y + 2 − …` (**the mist SDF sign is mirrored so the mist stays at the BOTTOM of the frame**). **This changes the composition**: mantis now hovers above the lotus (as its `Hovering` comment and y = +1 / −1 offsets say). Screen is a mirror-handed camera (x-symmetric scene, not visible).
- **R4 CONFIRMED**: HEAD, mouse at the bottom edge → `meanL 1.315, stdL 0.025` (camera inside the mist SDF = flat cyan white-out); at the top edge the lotus was seen from below through the mist. New: pitch input is `clamp(select(my·0.12, my, my>0), −0.12, 0.9)·1.5` — idle framing unchanged, cursor lifts the camera freely, only a hair of dip below the horizon (ground at y = −2). New bottom-edge render: `meanL 0.464, stdL 0.114` (shrine seen from above over the fog, not a white-out). Cost: the cursor no longer lets the camera go below the horizon (HEAD's "view from underneath" is gone).
- **R5**: `m_scale = max(zoom_params.x, 0.1)` in `map()` and `main()` (saved min is 0.5, so no real div-by-zero). Also guarded `normalize(q − mouse_pos)` in the click warp (`/max(dist, 0.001)`).

### Sliders (raw ranges, min→max vs default, % px > 0.02, t = 0.8, 192)
mantis-scale 0.5 → 6.6 %, 2.0 → 12.8 % · **lotus-complexity 1.0 / 5.0 → 0.00 % (DEAD, see open items)** · mist-density 0.1 → 36.9 %, 1.0 → 40.0 % · core-pulse-intensity 0 → 6.1 %, 5 → 6.8 % · audio (0.8, 0.5, 0.9) vs idle → 41.3 % (sky brightness, beat rate, heart intensity). `nan` = 0 everywhere, incl. a t = 40 s run with held cursor + audio.

### Default look (192, t = 1.5, 4 frames)
idle: meanL/stdL HEAD 0.214 / 0.233 → new 0.222 / 0.167 (meanA 1.0 → 0.63, alpha is now semantic). held (0.4, 0.6, down): HEAD 0.131 / 0.176 → new 0.257 / 0.200. Composition is vertically re-ordered (R3) and the sky is no longer near-black.

### Cost — trimmed (coordinator message A: first measurement was 1.82x HEAD)
**Final (coordinator spec: 384 px, 12 frames, defaults, ×5 interleaved HEAD/new, box load 16–22):** idle cursor HEAD min/median 2172 / 2794 ms vs new 1949 / 2538 → **0.90 min-ratio, 0.99 median of per-round ratios**; held cursor (0.4, 0.6, down) HEAD 2230 / 2823 vs new 2378 / 2915 → **1.07 / 1.01**. Both ≤ 1.3.

**Driver was the march, not the shading.** Step counts from an instrumented private-counter copy (192 px, steps / 100 rendered to a channel, *pre-trim* new vs HEAD): idle mean 48.0 → 54.2 steps/ray (rays at the 100-step cap 35 % → 40 %), **held 37.9 → 68.8 (cap 17 % → 59 %)**. Rays that end inside the mist (material 1, `dO += max(dS, 0.01)`) burn the whole budget 1 cm at a time; the upright framing (R3) puts the ground mist in view, so far more rays do that than at HEAD, and the held pose (click warp) most of all.

**Trim applied (only this .wgsl):** a *coarse crawl* — while a ray is inside the mist and `dS < 0.01` it advances 4 × 0.01 per iteration instead of 1 (`CRAWL_N = 4`), integrating the mist term `0.05·(0.1 − dS)` for the whole group with a first-order centroid extrapolation of the per-step term (`gHat = g + 0.375·(g − gPrev)`) and the last group clipped to the remaining step budget so the budget (and therefore total path length) is unchanged. Not bit-identical (it is an integral approximation) — pixel diff vs the untrimmed version over 5 scenes (idle/held/top/bottom/beat): **0.00–0.04 % of px > 0.02**; the first version (unclipped last group) overshot the budget and showed 4–12 %, hence the clip. The three ideas are untouched, so their visibility numbers above stand.

| variant (256 px × 4 frames × 9 rounds interleaved, load 20–35) | idle min-ratio / round-median | held min-ratio / round-median |
|---|---|---|
| HEAD | 1.00 / 1.00 | 1.00 / 1.00 |
| new, pre-trim (V1) | 1.13 / 1.22 | 2.36 / 1.69 |
| (4) auroraSky returns 0 — 3 layers × 2 noise3, already early-out for `rd.y ≤ 0` | 1.03 / 1.35 | 3.18 / 1.50 |
| (1)+(2) exact moves: env/skyRefl/auroraSky(refl) only in mat 2/3 and skipped when the weight is 0; ring/heartFlash only in mats 2–4 (max \|Δ\| 0.0011, only the lotus env skip) | 1.15 / 1.84 | 2.97 / 1.62 |
| **coarse crawl (final)** | **0.81 / 0.87** | **1.64 / 1.05** |

Reading: removing the sky (ablation 4) or gating env/ring work (1, 2) did not move the ratio outside the load noise (HEAD alone spans 546–2305 ms) — the sky/env/ring shading is not the cost driver; the crawl is. The 256 px × 4-frame table is noisy under this much load (held min-ratio 1.64 vs round-median 1.05 for the same file), which is why the figures above in bold-spec form (384 × 12, ×5) are the ones to quote. **Coordinator should re-time alone; the sky early-out for `rd.y ≤ 0` (exact) stays.**

### Gates
precommit 2/2 (with rainbow-cloud), `verify-naga-wasm --files` valid, `audit:dead-sliders` new = 0, `audit:extrabuffer` new violations 0 (2 known baseline). Re-run after the trim and the rainbow-cloud fixes: all four pass.

### JSON
Added `features: ["mouse-driven","audio-reactive","upgraded-rgba"]` (all true: orbit + warp; bass drives heart/beat/sky; ACES + cards implemented) and `x-meta.upgrade.params` (raw ranges as saved). `params`, `description`, `tags` untouched.

### Open items
1. **`lotus-complexity` is dead at HEAD and still dead** (0.00 % change at 1 vs 3 and 3 vs 5, side view AND from above, HEAD and new). By loop bound the slider is a no-op above 3 (`i < 4`); layers ≥ 1 refold the already-folded `lp` (they are never reset to the original point) and add nothing visible. Not fixed: any repair re-architects the lotus petal loop that the card says to KEEP VERBATIM and changes the default silhouette. Owner call: reset `lp` per layer so each layer is an independent petal ring.
2. R3/R4 change the composition and the cursor range — eyeball on a real GPU; the aurora palette is the lotus palette (`d = (0.3, 0.1, 0.6)`), so greens/yellows/purples cycle with `time·0.2`.
3. The heart (radius 0.15) sits inside the thorax capsule at the default scale and is hidden at HEAD and now (HEAD geometry); idea 3 therefore shows on the filaments and as a wash on the body rather than as a visible pulsing core.
4. Real-GPU visual QA + thumbnail refresh: external.

---

## rainbow-cloud

**KEEP VERBATIM held?** fbm3d (4 octaves, 2.03 lacunarity, same offsets), the 10 orthographic slices (`ro`, `rd`, `stepSize`), `cloudScale/driftSpeed/iridescence` mappings, mouseScatter, depthFactor + atmFog, iridescent cosine palette, ACES ×1.1, alpha formula, the 4-field A pack. **Deviations (all rescues, see below):** threshold/gain of `density`, the `densityParam` slider mapping (z-low end), the bass-turbulence pivot, the lattice corner offsets inside `noise3d`, hue slope vs density, white god-ray weight, pixel-centre uv, loop direction (mathematically identical compositing).

**A packing:** unchanged 4-field param pack `(cloudDensity, iridescence, depthFactor, alpha)`; **nothing reads it back** (verified: no `dataTextureC` load in the file). ACES on `writeTexture` only.

### The card's premise was wrong — HEAD drew no cloud
At HEAD, default sliders on the synthetic photo: `meanA 0.030` (the alpha floor) and `meanL 0.495` = the tone-mapped source. Density slider 0.5 → 1.0 changes **5.3 %** of pixels (> 0.02) and `meanA` only reaches 0.035. Cause: `density = max(d − 0.35, 0)·2.5` while `d = fbm·densityParam·depthFactor` peaks near 0.4 and averages 0.15–0.25, so the optical depth over the whole 10 × 0.1 march was ≈ 0.01. "Rainbow cloud" had no cloud at any slider setting, and the three planned ideas (phase, self-shadow, corona) all multiply a density that was ≈ 0. **I therefore deviated from the card's FORBID on the 0.35 threshold**; the shape (soft-threshold ramp) is kept, re-centred: `max(d − 0.13, 0)·12`. Default now `meanA 0.242`.

### Ideas (header `Ideas:` line)
| # | Idea | Where | §12.2 row | Visibility @576 (192 within 0.2 pt), default |
|---|---|---|---|---|
| 1 | Henyey–Greenstein forward lobe (g = 0.58) on a **per-pixel view angle** toward a sun at uv (0.74, 0.17); sampling stays orthographic (no parallax change); HEAD's constant `miePhase` stays as the floor | L85– | §12.2F HG | 35.2 % px > 0.02 (1.5 % > 0.05), mean \|Δ\| 0.0155 — broad soft glow toward the sun, not a hard feature |
| 2 | Beer–Powder self-shadow: marching deep→near makes the optical depth of the slices between sample and sun a free running sum (`sunT = exp(−0.9·τ_behind)`), powder `1 − exp(−2.5·density)` thins fringes. **No extra fbm tap** (card allowed one; this is the same compositing as HEAD, reordered) | L107– | native (Beer–Powder) | 76.6 % px > 0.02, 36.3 % > 0.05, mean \|Δ\| 0.039 |
| 3 | Corona irisation as **concentric coloured rings** around the sun: hue offset `0.5·sin(24·angDist)` and brightness `1 + 0.6·cos(24·angDist)`, both × `veil` (= 1 − smoothstep(0.15, 2.4, density)) × `exp(−1.2·angDist)` and the existing `iridescence`. The ring phase is a *periodic* function of angle — the first version used a hue offset linear in angle (`6.5·angDist·thin`), which is zero at the sun and 3–4 hue cycles away, so any per-pixel change in `thin` shifted the hue by whole cycles (grainy speckle far from the sun; reviewer-found) | L136–145, in the loop | native (diffraction corona; not thin-film) | **70.3 % px > 0.02, 13.7 % > 0.05, mean \|Δ\| 0.030** vs idea-off at 576 / t = 1.5 (first version 23.8 % / 3.9 %; periodic variant with the old `thin` gate only 2.2 % — the gate was too tight for this scene, so it was widened). In an amplified (×5) difference image the speckle is gone and smooth rings centred on the sun read clearly; in the final frame they are soft pastel arcs |

### Rescues (not in the card — found while measuring)
- **Dead optical depth** (above). Companion retune: god-ray white weight 2.0 → 0.35, iridescent term ×2.4, hue slope `density·2.0 → density·0.6` (density gain ×5 made the hue cycle 6× faster), so the veil reads as iridescent rather than milky white.
- **`noise3d` lattice seams.** HEAD's corner offsets were (x +57, y +113, z +1) while the cell index strides are (x 1, y 57, z 113), so neighbouring cells never shared corner values: **every lattice boundary in all three axes was a hard discontinuity** (visible as sharp rectangular patches the moment the cloud existed — seen in my first render, gone after the fix). The octave structure and constants are unchanged.
- Pixel-centre uv `(gid + 0.5)/dims` (HEAD used the texel corner).
- **Bass re-randomised the cloud (reviewer-found).** `turbPos = cloudUV·turbulence` scaled the absolute coordinate including the time drift, so every beat displaced the pattern by `(turbulence−1)·drift` — growing with uptime. Now `turbPos = cloudUV + (turbulence−1)·(pos − c)·cloudScale + …` with `c = (0.5·aspect, 0.5, 0.5)` (swell about the screen centre). Reproduced at 576 / saved defaults (before): bass 0 → 0.2 mean \|Δ\| 0.030 at t = 3 s vs 0.045 at t = 303 s (p95 0.077 vs 0.122). After the fix alone: **bass = 0 output bit-identical to before (max \|Δ\| 0 at t = 3 and 303)**, and bass 0 → 0.2 is 0.0217 vs 0.0220 (t = 3 / 303), 0.6: 0.037 / 0.042 — still clearly visible (62 % / 56 % px > 0.02 with the final corona) but no longer grows with uptime (final file: 0.0210 / 0.0203).
- **Density slider dead below ≈ 0.25.** HEAD-mapping `mix(0.15, 0.9, z)` kept `d` under the 0.13 cloud threshold for z < ≈ 0.2 (z = 0 and 0.1 changed 0.0 % of px vs a no-cloud render). Re-mapped to `0.3·(1 + z + z²)` — same z = 1 endpoint (0.9), same default (z = 0.5 → 0.525; max \|Δ\| 6.6e-7 vs the old formula, float rounding), but z = 0 now shows 2.5 % of px > 0.02 vs no cloud, z = 0.1 5.4 %, z = 0.25 31 % (was 0 / 0 / 6.1 %).

### Sliders (min → max vs default, % px > 0.02, 192)
cloud_scale 0 → 87.6 %, 1 → 88.9 % · drift_speed 0 → 72.6 %, 1 → 80.8 % · density 0 → 82.5 % vs default (re-mapped, see Rescues), 1 → 99.7 % (meanA 0.38) · iridescence 0 → 85.1 % (meanA 0.048), 1 → 85.0 % (meanA 0.404). All live. Held cursor + audio (0.8, 0.5, 0.9): `meanL 0.559`, `nan` 0; 60-frame run: `meanL 0.558`, `nan` 0; t = 40 s: `nan` 0. No state, so no `A16` run needed.

### Default look (192 = 576)
idle: meanL/stdL/meanA HEAD 0.495 / 0.166 / 0.030 → new 0.576 / 0.175 / 0.242. held + audio: HEAD 0.495 / 0.166 / 0.030 → new 0.559 / 0.171 / 0.204 (after the task-2 corona/bass/density changes). This is a large intended change: from "tone-mapped photo" to "photo under a visible iridescent veil".

### Cost
Interleaved HEAD/new, 384 px, 12 frames, saved defaults, ×5, box load ≈ 30: HEAD min/median 475 / 567 ms vs new 428 / 556 → **0.90 min-ratio, 0.97 median of round ratios** (≤ 1.3). Same four-octave fbm per slice, no extra tap; the corona change adds a `sin`/`cos`/`exp` per slice. Coordinator should re-time alone.

### Gates
precommit pass, `verify-naga-wasm --files` valid, `audit:dead-sliders` new 0, `audit:extrabuffer` new 0 (re-run after the bass/corona/density changes).

### JSON
`features` unchanged (all already true: mouse scatter, bass/mids, ACES + cards). Added `x-meta.upgrade.params` only (round-trip of the file was byte-identical before the edit).

### Open items
1. The sun position (uv 0.74, 0.17) is a literal; there is no sun slider (no new params). The HG lobe is deliberately gentle (35 % of pixels, 1.5 % > 0.05).
2. Powder/self-shadow assumes the sun is BEHIND the veil (back-lit, silver-lined edges) and shadows along the view axis only; there is no lateral shadow direction. A lateral cue would need an extra tap per slice (≈ +25–50 % cost).
3. All numbers are from a synthetic gradient photo and a synthetic depth map; on a real photo the veil colour interacts with the content — real-GPU / real-photo QA is external.

## §12.2 rows used by fork A
Henyey–Greenstein (rainbow-cloud only). Everything else native. No row is shared with another file.
