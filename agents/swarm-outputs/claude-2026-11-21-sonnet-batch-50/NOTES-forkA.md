# NOTES — fork A (sonnet/batch-50): gen-alpha-aurora, aurora-borealis-loom

Baseline = worktree file at start (prelude-migrated by the coordinator; pixel-identical to origin/main). Cards and mechanism interrogation: `BRIEFS-forkA.md`. VM = SwiftShader; no visual QA claim beyond what the renders below show.

---

## gen-alpha-aurora (2nd+ pass; `Upgraded: 2026-06-06, 2026-09-27, 2026-11-21`)

**ADD (all three findable by `// ── Idea n:` comments in the WGSL):**

1. **Emission-altitude layering** — 630 nm red crown lobe (≈1.4 band-widths above each band centre, `exp(-((up-1.4)^2)/0.7)`, bound to the existing rays × flame, structured by the existing `detailMask`) and an N₂ pink skirt (`exp(-((hn-1.7)^2)/0.18)`, below the shipped green hem at hn = 0.9) whose strength is `0.12 + 0.88·bass` (harder precipitation reaches lower). Not a §12.2 row (domain mechanism).
2. **Beer–Lambert horizon extinction (§12.2F)** — `skyT = exp(−τ_rgb·(X−1))`, τ = (0.10, 0.19, 0.38), Young airmass `X = 1/(cosZ + 0.025·exp(−11·cosZ))`, `Z = uv.y·1.45` (top = zenith, bottom ≈ 83°). Multiplies the accumulated aurora colour (bands + hem + fringes + atmospheric glow) and the stars. Relative to the zenith, so the top of the sky is unchanged. `atmoFalloff` kept verbatim.
3. **Flaming-aurora packets** — brightness packets that climb each existing ray: `flameS = 0.5+0.5·sin(2π·h(rayCell,band) + 2.6·hn + t·(2+3h)·(0.6+bandSpeed))`, `flame = 0.1 + 2.4·flameS²` (peaky, mean gain 1.0) multiplies `rayAmp`.

**KEEP VERBATIM:** the 4 params and their roles (band_speed, color_temperature, band_density, atmospheric_glow; JSON `params` untouched), 4-band loop, `curlNoise` deformation, Gaussian profile/width law, `dwfbm3` detail mask, `spectralColor`, ripple boost, `atmoFalloff`, curtain rays, green lower hem, star field, 0.15 persistence mix with exact C load, soft tone map, depth pass-through, ACES on `writeTexture`.

**A PACKING:** unchanged — pre-ACES display RGBA (soft-mapped colour + band alpha), read back as colour; ACES only on `writeTexture`.

**Rescues (loud):**
- **Mouse Y was inverted.** HEAD `(0.5 − mouse.y)·0.4` with `mouse.y = 0` at the top moved the bands DOWN when the mouse went UP. Measured alpha centroid y (0 = top), mouse at y 0.1 / 0.9: HEAD 0.719 / 0.466 (up→down), new 0.465 / 0.720 (up→up). Default mouse (0.5) is unchanged.
- **Dead bass envelope.** `extraBuffer[133]` is re-uploaded as 0 every frame (`writeExtraBuffer` writes all 256 floats), so `bass_env(0, bass, 0.15, 0.02)` = 0.15·bass: every `smoothBass` use (band speed, width, audio boost) ran at 15% strength. Now `smoothBass = bass`; the helper and the `extraBuffer[133]` read/write are removed. Audio response ×6.7 under music; silent default unchanged. **Open call for the coordinator:** this makes the audio look noticeably stronger than at HEAD (audio test 0.9/0.5/0.4: meanL 0.20 HEAD → 0.22 new, meanA 0.167 → 0.19); if you want HEAD's calm response, scale by 0.5.
- **CA tint** (`r + caStr`, `b − caStr/2` after ACES) could write negative blue on black; clamped ≥ 0 (display only).

**Diff vs HEAD:** see "Measured" below. **Gates:** precommit ✓, naga-wasm ✓ (1/1), dead-sliders 0 new, extrabuffer PASS (no extraBuffer use left).

---

## aurora-borealis-loom (2nd pass; `Upgraded: 2026-09-28, 2026-11-21`)

**ADD (labelled Idea 4 and Idea 5 in the file so they do not clash with the shipped Ideas 1–3; no §12.2 row used):**

4. **Plain-weave interlacement** — over/under parity per crossing cell, `overWeft = (floor(uv.y·D) + floor(uv.x·0.8D)) & 1`; the thread that is "under" is hidden across its whole cell span (`1 − 0.8·smoothstep(0.5, 0.15, |fract(·) − 0.5|)`), so every thread reads as alternating dashes in a checkerboard instead of HEAD's `max(weft, warp)` line lattice. Applies to `weft`, `warp`, `weftSlub`, `warpSlub`; bare-warp cloth below the fell is untouched (no weft there).
5. **Selvedge hem** — `auroraCurtain` now returns `(curtain, ridge)`; the ridge is `smoothstep(0.18w, 0, ||edge| − 0.8w|)` (the signed edge distance HEAD already computed and discarded), lit in the curtain's hue (35% toward white), only on woven cloth (`× woven`, so it vanishes below the fell) with a bead at every pick (`0.5 + 0.5·thread`), ×0.4 ×`patchGain`.

**KEEP VERBATIM:** the 4 params and roles (JSON `params` untouched), `auroraCurtain` waves and vFade, five curtain positions/widths/hue law, `weftPattern`/`warpPattern`, Idea 1 (fell + reed beat-up), Idea 2 (slub yarn + pools), Idea 3 (pulsating patches), ion streaks, nodes, stars, mouse pull, bass swell, atmospheric noise, trail `flowDir`/`histCoord` and the `0.85 + 0.03·bass` decay, semantic alpha, depth.

**A PACKING — CHANGED to fix a packing lie:** raw HDR RGB (pre-ACES, pre-CA) + semantic alpha; ACES on `writeTexture` only. HEAD stored post-ACES display RGBA and read it back as HDR energy.

**Rescues (loud) — two independent HEAD defects that each leave the effect broken:**
- **R1 — the conveyor never wraps; the curtains vanish after ~6 s.** `uv.x += warpT·curtainFlow·0.35` is unbounded; curtains, ion streaks and nodes sit at fixed x in [0, 1). Single frames at T0 = 0 / 3 / 8 / 30 s (saved defaults): HEAD = five curtains / two / **none / none** (meanL 0.183 / 0.102 / 0.047 / 0.046, stars + the fell arc only; it never returns). New: five curtains at every time (meanL 0.195 / 0.203 / 0.195 / 0.194). Fix = period-1 x distance in `auroraCurtain`, ion streaks and `ionizationNodes` (identical to HEAD while |uv.x − xPos| < 0.5).
- **R2 — the HDR trail loop is bistable and washes the frame to grey.** `fbCol = clamp(col + prev·0.85, 0, 5.5)` with `prev` = previous POST-ACES display and an ACES inside the loop (toe slope > 1 above x ≈ 0.1 × gain 0.935): any pixel above ~0.1 ratchets to a ~0.7 attractor, and the advection smears that across the frame. Frames 1 / 4 / 12 / 40 at the harness step: meanL 0.081 / 0.526 / 0.741 / 0.740, stdL 0.124 → 0.026. At a real 60 fps cadence (90 frames over 1.5 s) HEAD ends at **meanL 0.761, stdL 0.037** (flat grey); new ends at **0.253 (T0 = 0) / 0.267 (T0 = 8), stdL 0.167 / 0.188**. Fix = A stores the raw HDR value, trail is peak-hold `max(col, prev·decay)` (same advection, same decay), ACES/CA on the displayed value only.
- **R3 — CA tint** now applied to the displayed value only and clamped ≥ 0 (HEAD could feed negative blue into ACES; the catalog ACES maps negatives to bright).

**Open calls:** (a) the trail is a peak-hold now, not a sum — moving light leaves a decaying tail (≈ 6 frames) but overlapping trails no longer add; if the coordinator wants additive-looking pile-up, raise the decay, do not re-add the sum. (b) `fast-motion` is still in the JSON `features` although nothing in the file opted into a fast-motion brief (curtains scroll at ≈ 0.16 u/s); left untouched, flagged for §8 hygiene.

**Gates:** precommit ✓, naga-wasm ✓ (1/1), dead-sliders 0 new (all four sliders read: weave-density, hue-speed, ionization, curtain-flow), extrabuffer PASS.

---

## Measured

(filled in below)

SwiftShader, `agents/mr.mjs`, saved JSON defaults, first panel (raw RGB) compared, `max|Δchannel|`:

| file / view | mean abs Δ | >2% of px | >5% | >15% |
|---|---|---|---|---|
| alpha-aurora, 320 px, 6 fr, t≈2, no audio | 0.035 | 46.2% | 30.2% | 2.5% |
| alpha-aurora, same, audio 0.9/0.5/0.4 | 0.103 | 63.2% | 54.8% | 27.5% (includes bass ×6.7 rescue) |
| loom, 256 px, 1 frame, T0=0 | 0.023 | 18.1% | 13.9% | 5.6% |
| loom, 256 px, 1 frame, T0=2 | 0.076 | 23.9% | 20.7% | 14.6% (HEAD already losing curtains) |
| loom, 90 frames at 60 fps cadence | — | 100% | 100% | 100% (HEAD = flat grey wash, new = structured) |

Per-idea ablation (new vs the same file with that idea switched off, same frame): alpha Idea 1 (crown+skirt) 30.4% of px >2%; Idea 2 (extinction) 42.7%; Idea 3 (flame) 17.7% (8.8% >5%); loom Idea 4 (interlacement) 9.4% (6.4% >5%, 1.9% >15%); Idea 5 (selvedge) 11.5% (9.4% >5%, 4.2% >15%).

Timing (interleaved `mr_ab.mjs`; box load average 45–76 on 8 cores while five forks and a C++ build ran, so treat as order of magnitude; **coordinator should re-time on a quiet box**): alpha-aurora paired-median new/HEAD = 0.98, 1.02, 1.18 (load spike), 1.00 → ≈ 1.0× (the added work is ~15 ALU ops/band against ~4,500 hashes/pixel). loom paired-median = 1.18, 1.25, 1.08 (min-ratio 0.94–2.04, unusable) → est. +5–15% (one `i32` parity, 2 smoothsteps, 5 selvedge smoothsteps, no new loads); frameMs ≈ 100–200 ms at 256 under load.

Stress (no NaN, no blank, no saturation): params 0,0,0,0 and 1,1,1,1, audio 0 and 1/1/1, mouse at the edges, an injected click ripple (alpha). loom at max audio/params: meanL 0.441 stdL 0.21 (peak-hold trail is stable at decay 0.88).

Not verifiable here: how the red crown / pink skirt / extinction tint actually look on a real GPU and a real monitor (colour amplitudes were tuned by eye on SwiftShader renders: crown 0.22, skirt 0.28, τ = 0.10/0.19/0.38); real-GPU visual QA remains external.
