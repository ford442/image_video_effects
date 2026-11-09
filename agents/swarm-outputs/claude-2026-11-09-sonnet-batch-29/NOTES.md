# NOTES — sonnet/batch-29 (glass / iridescence / kaleidoscope / optical, 10 shaders)

Cards: `BRIEFS.md` (written before any idea edit). Harness: SwiftShader WebGPU single-dispatch render harness (scratchpad; rgba8 source, f16 history round-trip like a 16-bit tier, A→C copy per frame). **Structural / PNG evidence only — no real-GPU visual QA claimed.** Every number below is `meanL` (mean luma of `writeTexture`) HEAD → new on a synthetic photo, 384² unless noted; 70/70 renders (10 shaders × HEAD/new × default/stress/zero + a 640×384 stress each) have 0 NaN / 0 Inf in `writeTexture` and in A.

Plumbing (own commit, `1774aa7d`, no `Upgraded:` bump): 7 files migrated to `#include "_prelude.wgsl"` with `scripts/migrate_to_prelude.py --naga` (V1–V5 proofs green).

Rescues R1 (spring state never persisted), R2 (audio index), R-phase (time × audio) are reported **separately from the ideas** and are not counted as upgrade.

| § | id | Ideas added (grep `Idea n` in the WGSL) | rescues | meanL default / stress |
|---|---|---|---|---|
| 1 | static-reveal | 3 head-switching noise · 4 tape dropout bursts | – | .7203→.7236 / .6014→.6042 |
| 2 | selective-color | 3 chroma-plane hue+sat window (5-tap key) · 4 mono-stock grain | – | .5367→.5360 / .5411→.5409 |
| 3 | aero-chromatics | 1 edge-tangent flow · 2 spiral outflow | R1 glide in A(0,0) + exact bilinear · R2 audio index | .2929→.2922 / .4886→.5037 |
| 4 | chroma-depth-tunnel-prismatic | 1 ring-joint dispersive rim · 2 chromatic flight lag · 3 depth-integrated Beer–Lambert | R1 · R-phase | .3645→.3543 / .3009→.3301 |
| 5 | fractal-kaleidoscope | 4 seam-weighted dispersion · 5 per-bounce defocus | – | .4340→.4342 / .5036→.5036 (smooth photo; see below) |
| 6 | gen-apollonian-gasket | 7 conformal hairlines · 8 generation-delayed pulse | R1 | .4881→.5111 / .5796→.6323 |
| 7 | luminescent-glass-tiles | 4 Cauchy lens dispersion · 5 hammered decentring | – | .5285→.5282 / .5223→.5222 (smooth photo; see below) |
| 8 | divine-light-iridescence | 1 sun corona (Airy) · 2 Henyey–Greenstein lobe · 3 stratified march | – | .6471→.6481 / .6879→.6874 |
| 9 | gen-belousov-zhabotinsky | 5 isotropic 9-point Laplacian · 6 Schlieren front relief | – | .4690→.4695 / .4691→.4695 |
| 10 | interactive-kuwahara | 4 structure-tensor sector alignment · 5 stroke-edge pigment pooling | – | .4349→.4325 / .4422→.4403 |

Formula rows used (§12.2): Dropout bursts (B), Density-weighted grain (A), Cauchy dispersion (F), Airy disc (F), Henyey–Greenstein (F), Isotropic 9-pt Laplacian (D), Structure tensor (A), Beer–Lambert (F). No row on more than one file in this batch.

Two ideas fall outside §12.2's rows and are the files' own vocabulary: aero-chromatics' edge-tangent flow / spiral outflow, apollonian's conformal-derivative hairline / generation pulse.

---
## 1. static-reveal
**Kept verbatim:** 4 params and roles; depth-scaled mask decay in C.a/A.a; tracking band + hHold; snow / perlin chroma noise; acqFlash; vignette tint; vertical-hold roll + blanking; multipath ghost; R/B tracking shift; ACES; alpha.
**A packing:** display RGB + reveal mask in alpha (HEAD's, unchanged).
**Ideas:** 3 — `footZone` shear on `dUV` (bottom 7 %), `switchLine` at y = 0.935 with per-column field-rate snow. 4 — per-scanline-cell dropouts, 270 lines, 6 Hz event windows under `sin(π·fract(6t))`, start x per line, `exp(−11·dx)` tail. Both gated by `(1 − mask)`; brushed picture stays clean.
**Visible in render:** white dropout streaks across the snow, bright switch line near the bottom edge; luma +0.003.

## 2. selective-color
**Kept verbatim:** 4 params; six mask generators + max blend; chromatic split at the boundary; depth Sobel edge tint; hue-window concept and contour; ACES; alpha.
**A packing:** ACES display RGBA (HEAD's).
**Ideas:** 3 — `cosSim(chroma(pixel), chroma(key))` with chroma = rgb − luma, `smoothstep(0.74, 0.97)` (≈ ±14–42° of hue), gated by pixel chroma and a saturation window, key = 5-tap cross; neutral key (`lenK < 0.03`) falls back to HEAD's RGB distance (blend `smoothstep(0.03, 0.10, lenK)`). 4 — `√(L(1−L))` grain at 24 fps on `(1 − combinedMask)·desatStrength` only. **Tuning note:** first pass used `smoothstep(0.5, 0.92)` and a red key admitted the orange horizon (≈ 28° away); tightened after viewing.
**Visible in render:** the pale sky no longer takes colour through the RGB-distance quirk; grain in the grey field only.

## 3. aero-chromatics
**Kept verbatim:** 4 params; luma-scaled velocity; radial pointer wind; upward drift; click gusts; chromatic advection; injection; decay; alpha; **HEAD's sample-position convention** (`uv = pixel/res`, no +0.5 — the half-texel averaging *is* the smoke's diffusion).
**A packing:** raw smoke trail + alpha (no ACES, as in HEAD); texel (0,0) = (windSource.xy, 7, fract(time)), masked on every history read.
**Ideas:** 1 — 4-tap luma gradient (2 px) gives the edge normal; the velocity's component along it is removed (`·edgeStrength·0.85`) in pixel space. 2 — tangential `perp(mouseDir)` term at 40 % of the radial push (first pass 55 % smeared the sun into a halo in an orbit test; trimmed).
**Rescues:** R1 `extraBuffer[133..137]` spring never persisted (verified in `audioDepth.ts`: whole buffer re-uploaded each frame) → glide rate 8 in A(0,0), exact `textureLoad` bilinear replaces the filtering sampler on C. R2 `bass` was `plasmaBuffer[1].x` and the 8 band flutters `plasmaBuffer[2..8].x` (not audio) → `[0].xyz` mapped across the bands.
**Proof the plumbing is neutral:** with all three ideas/glide ablated and audio 0 the rescue-only build equals HEAD to four digits (orbit, 60 frames: meanL 0.3663 / 0.3663, stdL 0.1902 / 0.1901). With audio live, wind and flutter now respond (stress .4886 → .5037) — HEAD's audio was dead.

## 4. chroma-depth-tunnel-prismatic
**Kept verbatim:** 4 params incl. their multi-uses; polar mapping; `cauchyIOR` / `refractUV` / `wavelengthToRGB` four-band sum; packets, helix, click fronts, centre fog, bass throat; 0.08 C persistence; ACES; alpha.
**A packing:** ACES display RGBA; texel (0,0) = (cursor glide.xy, 7, fract(time)), skipped by the C persistence mix.
**Ideas:** 1 — `jointRim += band colour · exp(−26·min(fract(v), 1 − fract(v)))` inside the existing band loop, per band's own refracted v. 2 — `bandUV = tunnelUV − (i − 1.5)·speed·0.04` (zero at rest). 3 — `pathLength = 1 + 1.4·(1 − smoothstep(0, 0.55, radius))` multiplies the absorption exponent.
**Rescues:** R1 cursor glide (rate 6.5 = √42 = HEAD's spring ω). R-phase: `speed·(1+bass·0.45)·time`, `time·(13+bass·5)`, `time·(9+mids·6)` jumped the phase by `time·Δaudio` on every change → audio now scales packet gain / helix push; `time` has a constant rate.
**Honest limit:** at 384 px the default ring density moiré hides the rims; they read on a sparse tunnel at 768 px (Ring Density 0).

## 5. fractal-kaleidoscope
**Kept verbatim:** 4 params; fold, `chamberChain`, integer crossfade, reflection loss, seam / conveyor / click / slick terms, 0.26 folded-uv feedback, ACES, transmission alpha, depth.
**A packing:** ACES display RGBA, alpha = mirror-path transmission (HEAD's).
**Ideas:** 4 — `sampleSplit` offset ×(1 + 2.5·seam) per branch. 5 — `sampleSoft`: 4 taps on a ring of radius 0.0009·min(bounces, 6), rotated per pixel by interleaved-gradient noise, blended by `bounces·0.16` (≤ 0.7).
**Honest limit:** on the smooth synthetic photo the two ideas are invisible (mean |Δ| 0.1/255 at 1024²) because the folded region is low-frequency; on a high-frequency image they are clear (mean |Δ| 11.2/255, 73 % of pixels > 8): crisp inner wedge, progressively softer reflections. The defocus radius is in uv units like HEAD's `chromaticOffset`, so it grows with output resolution.

## 6. gen-apollonian-gasket
**Kept verbatim:** 4 params; the five seed circles; inversion loop + pointer inversion; every existing colour term; 0.05 feedback; aberration; A written pre-ACES; single ACES.
**A packing:** linear RGB + alpha pre-ACES (C read as colour); texel (0,0) = (pointer glide.xy, 7, fract(time)), skipped by the feedback mix.
**Ideas:** 7 — accumulate `dScale *= r²/|q−c|²` (clamped 1e12) through every inversion incl. the pointer's and the spin's complex scale √(c'²+s²) (HEAD's spin is `[[cos(a+mids), −sin a],[sin a, cos(a+mids)]]`, a similarity — kept, not "fixed"); `hair = 1 − smoothstep(0, 1.2 px, minDist/dScale)`, faded for `dScale` 150…4000 (copies tighter than a pixel). 8 — `pow(½+½·sin(1.6t − 0.9·invCount), 5)·(0.6 + 0.8·bass)` scales `val` ×(1 + 0.3·pulse) and the hairline.
**Tuning note:** first pass (1.6 px, fade 3e3…3e5) turned the packed centre into a white fill; narrowed to 1.2 px and an earlier fade.
**Rescue:** R1 glide rate 8.
**Open for GPU QA:** the packed centre is brighter/busier than HEAD (+5 % luma default).

## 7. luminescent-glass-tiles
**Kept verbatim:** 4 params; grid, `scale = 1 − luma·refractStr·2`, mouse + ripple twist; border darkening; Fresnel / absorption / transmission alpha; Ideas 1–3; 0.07 display-space C mix; depth; ACES. (Header gained the missing `Upgraded:` line from the ledger: 2026-10-04, 2026-11-01.)
**A packing:** ACES display RGBA (HEAD's).
**Ideas:** 4 — `channelScale = 1 − lensPower·cauchyScale(0.12·lensPower)`; green is exactly HEAD's `finalUV`, red/blue re-scale `lensUV`. 5 — `hammerShift = (hash22(cellID) − 0.5)·0.22·lensPower`, sampling only (`border` keeps `distUV`).
**Honest limit:** invisible on the smooth sky of the synthetic photo; clear on a high-frequency image (red/blue fringes inside magnified tiles, tiles showing different parts of the picture).

## 8. divine-light-iridescence
**Kept verbatim:** 4 params; 14-step march, 0.94 decay, luma gate; `beamPattern`; `thinFilmColor`; golden/iridescent mix; halo; treble sparkle; ripple offset; 0.065 history; ACES; depth passthrough.
**A packing:** ACES display RGBA; B unused (HEAD's).
**Ideas:** 1 — `airy(x)` = (2·J1(x)/x)² with a Numerical-Recipes J1 (rational < 8, asymptotic ≥ 8), `x = 38·d/λ_rel`, λ_rel = (1.18, 1.0, 0.82), ring part only (`smoothstep(0.04, 0.10, d)·exp(−3.2d)`), ×16. 2 — `hgN = (1−g)³/(1+g²−2g·cosθ)^1.5`, g = 0.62, tanθ = 1.4·d, `forwardLobe = mix(0.6, 1.5, hgN)`. 3 — IGN jitter of the march start within one step.
**Verified:** my f32 port of J1 matches the true J1 (numerical integral) to 9e-7 for x ∈ [0.01, 1000]. **Doc trap:** the `airy` snippet in `SHADER_UPGRADE_BATCH.md` §12.3 F1 returns −56.5 at x = 8 (true value 0.2346); its truncated series is only valid below x ≈ 3. Not edited here — flagged for the coordinator.
**Visible in render:** HEAD's 14 stepped ghost copies behind the coloured blobs and on the horizon dissolve into smooth streaks; a pastel red-outside / blue-inside ring around the light.
**JSON:** `upgraded-rgba` added to `features` (ACES + ideas now real); `public/shader-lists/advanced-hybrid.json` regenerated.

## 9. gen-belousov-zhabotinsky
**Kept verbatim:** 4 params; kinetics; seeding; pacemaker gradient; colour ramp, refractory shading, phase hue, annihilation cusp, spiral-tip glow; mouse seed; ACES + hue clamp + IGN dither.
**A packing:** raw sim (a, b, waveFront, alpha) in A; (lapA, lapB, oxidized, front²) in B — HEAD's, unchanged; `lapA/lapB` stay Laplacians (now 9-point, same scale).
**Ideas:** 5 — `lap9 = (0.2·Σedge + 0.05·Σcorner − centre)·5/6` (4 extra loads). The 9-point sums to 0.3·∇² against HEAD's 0.25, so 5/6 keeps Da/Db strength; stability bound ε·Da ≤ 1 unchanged (max 0.34·2 = 0.68). 6 — `frontGrad = (e.r − w.r, n.r − s.r)/2`, `relief = clamp(−dot(grad, (−0.6, −0.8))·2.6, ±0.8)`, `col·(1 + 0.5·relief) + warm·max(relief, 0)·0.22`.
**Visible:** viewing A directly after 300 frames, HEAD's spiral arm edges show pixel staircases; the 9-point build has smooth edges, same pattern.

## 10. interactive-kuwahara
**Kept verbatim:** 4 params; four sector means/σ; `1/(1+σ^8)` weights; impasto from sector-luma slope; canvas weave; wet runner / packets / click clarity; ACES; 0.14 C wet-trail mix; alpha.
**A packing:** ACES display RGBA (C read as colour).
**Ideas:** 4 — 3×3 luma grid at 1.5 px → four 2×2 gradients → J; `α = ½·atan2(2Jxy, Jxx − Jyy + 1e-9)·smoothstep(.25,.75,coh)·smoothstep(1e-4,5e-3,trace)`; sector offsets rotate by α; the impasto slope is rotated back so the light stays upper-left. 5 — `strokeEdge = smoothstep(.5,1,(wmax − wmin)/wmax)·smoothstep(.05,.18,sectorSpread)`, `finalRGB·(1 − 0.2·strokeEdge·stylization)`.
**Tuning note:** first pass without the `sectorSpread` gate produced dark ~8 px squares wherever a noise speck made one sector "decisive" (ablation: they came from Idea 5, not the rotation); gated by the tonal spread of the sector means.
**Visible:** on a striped test image HEAD's square blocks become leaf-shaped blobs following the diagonals; a soft dark rim sits at the circles' boundaries.

---
## Closeout gates (coordinator)
- naga-wasm 10/10 valid; `wgsl_precommit_gate` 10/10 (0 pasted headers, 0 extraBuffer violations); `audit_extrabuffer` PASS (0 new); `audit_dead_sliders` 10 defs, 0 new dead.
- `node scripts/generate_shader_lists.js` ran (only `advanced-hybrid.json` changed, the `upgraded-rgba` tag).
- Vitest 203 files / 1822 passed (1 skipped); `npm run build` ok (installed with `npm ci --ignore-scripts`: `onnxruntime-node`'s postinstall download is blocked in the sandbox). The build's `gen` step also rewrote `public/shader-search-index.json` — not committed: the diff is 10 entries that are not from this batch plus the global mean (pre-existing drift on main), none of the ten ids changed.
- `upgrades:record --ids=<the ten>`: 10 `upgraded` entries, thumbnails marked stale.
- Real-GPU visual QA: external. Open: apollonian centre busyness; aero spiral strength; kuwahara pooling on real noisy photos; kaleidoscope / glass-tile effects on real photos (invisible on smooth content by design); tunnel rims at real resolution.
