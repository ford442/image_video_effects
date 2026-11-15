# NOTES — fork D (gen-audio-reactive-spiral-galaxy, gen-audio-reactive-aurora-ribbons)

Both FIRST PASS. HEAD = origin/main 7f6ce638 (nothing of fork D's files was touched by the prelude migration; both already used `#include`). SwiftShader WebGPU only — no real-GPU visual claim. Harness defaults sliders to 1,1,1,1; every number below passes the **saved defaults** (galaxy 0.55,0.5,0.45,0.4 · aurora 0.55,0.5,0.45,0.35). "Visibility" = % of pixels whose max-channel |Δ| (RGB of writeTexture, premultiplied as the file writes it) exceeds 0.02 between the file and a scratch copy with that idea zeroed, 1 frame, identical audio. Scratch: `.../scratchpad/forkD/` (`gvar.py`/`avar.py` generate the zero-switch copies, `cmp.py`, `track.py`, `polar.py`).

---
## 1. gen-audio-reactive-spiral-galaxy

**KEEP VERBATIM held:** log-spiral model `a − armPhase − log(r)/tightness` (now as one signed offset to the nearest of the evenly spaced arms), `arms = 2 + floor(mix(2,5,p2))`, `orbit = time·(0.12 + mids·0.25 + p3·0.2)` as pattern speed, `tightness = 0.18 + bass·(0.22 + p1·0.15)`, core, star colour endpoints (blue 0.5/0.7/1.0 → amber 1.0/0.75/0.45), 96-star loop, treble sparks line (unchanged), C trail mix with p4, depth fade, `hue_preserve_clamp` + ACES + IGN, premultiplied `col*alpha`, alpha formula, 4 params (ids/names/defaults/ranges byte-exact — JSON diff touches only description, `features` (+`upgraded-rgba`), and an additive `x-meta.upgrade.params`).
**A packing:** raw HDR trail colour (RGB) + bassEnv (A) — unchanged, it is what C is read as; ACES only on writeTexture. Not newly ACES'd.

### Rescue R1 — dead arm stars — CONFIRMED
HEAD `pos = (cos(a+armPhase), sin(a+armPhase))·(r+jitter)+jitter` is the pixel's own radius at an angle rotated by `orbit+armPhase`; and the glow is evaluated against `uv`, not the parallax-shifted `p`. Measured at HEAD (192², defaults, 1 frame, star-loop contribution on vs removed): **0.00 % of pixels change at 10 of 13 sampled times** (t = 0.5, 1, 1.5, 2, 3, 4, 5, 7, 8, 9, 10); the stars flash only when `orbit+armPhase ≡ 0 (mod 2π)` for some arm: 0.70 % of pixels at t = 0.05, 3.02 % at t = 6 (one bright arm arc, hard-clipped at the atan2 seam). So at rest HEAD draws core + a small pinwheel dust pattern; **the arms did not exist** (`g_head_6.0.png` shows the single strobe arc).
Fix: stars are placed on their own radius `ri = 0.08+h.y·0.55` and angle `armPhase + log(ri)/tightness − orbit + delta`, glow evaluated against `p`. Because 96 point stars alone cannot paint a galaxy, the loop's intended band×radial sum is restored as a continuous **arm body** (`armBand·radialBody`) built from the same offset the dust/HII/star colours use — documented in the header as part of the rescue. Jitter: HEAD's `hash22(fi, time·0.1)` re-rolled every frame (frame-hash strobe); replaced by a smooth `sin/cos` wobble with the same treble scaling. Star size raised (0.005 + hy·0.009 + treble·0.003, plus a 15 % ×3-radius PSF wing): HEAD's 0.002–0.006 is sub-pixel at ≤ 576 px. Radial early-out `|r − ri| > 0.07 → continue` (hy is one hash) keeps the loop cheaper than HEAD's.
### Rescue R2 — filtering sampler on rgba32float history — CONFIRMED by code
`textureSampleLevel(dataTextureC, u_sampler, pixel/res)` → `textureLoad(dataTextureC, pixel, 0)` (line 155). HEAD's `pixel/res` sat on a texel corner, i.e. a 2-texel bilinear blur of every trail frame; trails are now crisper (default-look change, small).
### Open (not changed): `arm_tightness` (p1) is dead at silence — it only enters as `bassEnv·p1·0.15`. Card said keep the model; owner's call.
### Open (not changed): `orbit = time·rate` multiplies absolute time, so a change in mids/p3 snaps the whole pattern by `Δrate·time` radians (big after minutes). HEAD behaviour, KEEP VERBATIM.

### Idea 1 — differential rotation, flat rotation curve (native) — `public/shaders/gen-audio-reactive-spiral-galaxy.wgsl:118-145`
Ω(r) = 1/(1 + r/0.1) per star; arm pattern speed is `rate`; star angle offset from its arm centre line `delta = scatter + (rate − Ω)·time`. Star colour/brightness by `inArm = exp(−armOffset(delta)²·18)` (blue + bright in the arm, amber + dim between), so stars visibly change colour as they cross arms.
- **Proof (per-star tracking, stars-only copy, 576², t = 2.0 → 2.15, bass = 0):** 82 stars tracked. Measured d(angle)/dt vs expected −Ω(r): r̄ 0.16 → −0.363 / −0.392; 0.27 → −0.259 / −0.267; 0.39 → −0.208 / −0.205; 0.50 → −0.153 / −0.168 rad/s. With the idea zeroed (rigid, Ω = rate) all four bins sit at −0.19…−0.20 (expected −0.21).
- **Visibility (defaults, 1 frame, idea zeroed):** 192²: 3.65 % (t = 1.5), 3.86 % (t = 8); 576²: 3.62 % / 3.84 %; >0.005: 8–10 %. (Before the star-size/PSF-wing change it was 1.4 %: 96 sparse stars cover ~0.7 % of the frame, so this idea is star-layer-limited by construction.)
### Idea 2 — density-wave colour sequence (native) — `:94-116, :147-149`
All functions of the signed arm offset `s = off·6` (σ units of HEAD's arm band, + = concave/inner side): dust lane Gaussian at s = +1.15 (replaces HEAD's `sin(a·arms − log(r+0.05)·3)` lane, which followed a different spiral); pink HII knots (hash-thresholded cell blobs in (r, s), locked to the pattern) at s ≈ +0.35; blue young body centred s = −0.2; amber old disc between arms. Dust darkening 0.55 at lane centre.
- **Visibility (defaults, idea reverted to HEAD dust + uniform body/star colour + no HII):** 192²: 11.9 % (t = 1.5), 12.8 % (t = 8); 576²: 12.9 % / 12.9 %; >0.005: ~26 %.

**§12.2 rows:** none borrowed (both native; Golden-angle not used). **Default-look change** (576², 20 frames, silent): meanL 0.041 → 0.074, meanA 0.193 → 0.28 (the arms now exist); with audio 0.6/0.4/0.5 meanL 0.17. nan = 0. See also the 60-frame A16 table below.

---
## 2. gen-audio-reactive-aurora-ribbons

**KEEP VERBATIM held:** `ribbonField` structure (fbm warp → sinusoid → curtain → shimmer noise at `uv·(24,6)`), ribbon count `mix(3,7,p2)`, baseAmp/baseFreq audio mapping, `auroraPalette` + hue clock (`fi·0.11 + mids·0.35 + time·0.04 + p1·0.2`), treble sparkle, C trail mix with p4, depth fade, `hue_preserve_clamp` + ACES + IGN, premultiplied `col*alpha` and the alpha formula, 4 params byte-exact (JSON diff: description, `features` +`upgraded-rgba`, additive `x-meta.upgrade.params`).
**A packing:** raw HDR trail colour + bassEnv in A — unchanged; ACES only on writeTexture.

### Rescue R1 — filtering sampler on rgba32float history — CONFIRMED by code
`textureSampleLevel(dataTextureC, u_sampler, pixel/res)` → `textureLoad(dataTextureC, pixel, 0)` (`:131`); same half-texel-blur removal as the galaxy.

### Idea 1 — asymmetric curtain profile (native) — `:63-67`
`exp(−max(dy,0)·k·2.6 − max(−dy,0)·k·0.55)`; peak 1 at dy = 0 as HEAD; sharp below the border (uv.y is DOWN so dy > 0 = below), long fade above. Total 1-D energy 2.2/k vs HEAD 2/k.
- **Visibility (defaults, silent, 1 frame, idea reverted to `exp(−|dy|k)`):** 192²: 42.6 %; 576²: 42.5–45.0 % of pixels > 0.02; mean|dA| 0.069 (alpha follows coverage).
### Idea 2 — altitude emission colour (native, spectral) — `:115-123`
Red (1.0, 0.22, 0.12) mixed in with height above the border (`smoothstep(0, 0.25, −dy)`, weight 0.7), violet-blue (0.35, 0.35, 1.0) in a thin band under it (0.6); the hue clock still drives the body. RGB only (alpha unchanged by design).
- **Visibility (defaults, silent):** 192²: 26.2 %; >0.005: 84 %. (Earlier 0.85-weight/0.35-ramp version: 38 % at 192² silent, 76 % with audio — softened because it made the top of every curtain a muddy brown wash.)
### Idea 3 — fold limb-brightening (native) — `:68-73`, applied to colour only (`rf.z`), **not** to coverage/alpha
`limb = min(1 + 7·slope², 2)/1.3`, `slope = amp·freq·cos(arg)` (analytic d(wave)/dx; the fbm warp derivative is ignored). Flat stretches ≈ −23 %, steep folds up to +54 %. First version (limb inside `field`, linear gain) leaked into alpha and the premultiplied write double-counted it (meanL 0.29 vs HEAD 0.163 under audio); fixed by moving it to colour only.
- **Visibility (defaults, silent):** 192²: 5.0 % of pixels > 0.02 (39 % > 0.005 — at default amp 0.08 the slopes are small); with bass/mid/treb 0.8/0.5/0.9: 64 %.

**§12.2 rows:** none (all native; the red/green/violet are the real auroral emission lines, not a palette stamp). **Default-look change** (384², 60 frames, A16): silent meanL 0.0733 (HEAD) → 0.084 (+15 %), meanA 0.304 → 0.337; with audio 0.5/0.4/0.3 meanL 0.163 → 0.209 (+28 %); maxRGB ≥ 0.98 stays 0 %; nan = 0. Looked at `a_new_60_idle.png` / `a_head_60_idle.png`: curtains read as hanging sheets with a hard base and a faint warm top fringe; HEAD reads as symmetric soft bands.

---
## 3. Cross-cutting evidence

**Default-look change (writeTexture meanL / meanA, A16, 384², 60 frames, tEnd 4 s, saved defaults, HEAD → new):**

| | silent | audio 0.5/0.4/0.3 | held cursor (0.4,0.6,1; 192², 20 fr, silent) |
|---|---|---|---|
| galaxy | 0.0415 / 0.193 → 0.0777 / 0.289 | 0.1016 / 0.261 → 0.1559 / 0.374 | 0.043 → 0.079 |
| aurora | 0.0733 / 0.304 → 0.084 / 0.337 | 0.163 / 0.353 → 0.209 / 0.391 | 0.067 → 0.077 |

`maxRGB ≥ 0.98`: 0.00 % in every run; **nan = 0** in every run (incl. A16). I looked at `g_head_576.png` / `g_new2_576.png` / `g_new2_aud.png` / `gA_new_idle.png` (galaxy) and `a_head_576.png` / `a_new_576.png` / `a_new_60_idle.png` / `a_head_60_a16.png` (aurora). The mouse is a plain parallax / sky shift in both files (no held-only path), so "held cursor" = parallax moves the whole picture; nothing new to verify. Neither file reads ripples, so no click case. The harness's circular crescents in every frame are its synthetic depth map (present at HEAD too), not shader output.

**Per-slider sweep (128², 12 frames, % of pixels with max|Δ| > 0.02 vs the default frame; min→max):**
- galaxy, audio 0.5/0.4/0.3: arm_tightness 69.4 / 64.8, arm_count 52.7 / 61.9, spin_rate 51.4 / 54.6, trail_persistence 6.6 / 9.5 — all live.
- galaxy, **silent**: arm_tightness **0.00 / 0.00 (dead at silence — HEAD behaviour: p1 only enters through `bass·p1·0.15`; the dead-slider audit does not flag it)**, arm_count 40.5 / 49.4, spin_rate 36.9 / 40.0, trail 5.7 / 6.6.
- aurora, silent: ribbon_intensity 34.9 / 15.3, ribbon_count 88.1 / 95.6, wave_frequency 39.0 / 50.3, trail_persistence **0.00 (>0.005: 21.9 %) / 2.15 %** — live but faint at a 12-frame window: trail only changes the history blend, as at HEAD.

**Cost (min-of-drained-frames, interleaved HEAD/new, 5 rounds, 192², silent, median of per-round min ratios; machine load average 45–70 from sibling forks, so noisy):** galaxy **1.07×** (per-round 1.33, 1.07, 1.06, 0.98, 2.21); aurora **1.10×** (1.37, 0.87, 1.06, 1.37, 1.10). The galaxy radial early-out (`hy` is one hash; ~7 of 96 stars survive per pixel) is why the star loop did not get dearer. Coordinator should re-time alone.

**Gates (each file):** `wgsl_precommit_gate.py --files` ✅, `verify-naga-wasm.mjs --files` ✅ (1 valid, 0 invalid), `npm run audit:dead-sliders -- --files …` 0 new, `npm run audit:extrabuffer` PASS (no extraBuffer use in either file). The two audit runs rewrote `reports/dead_sliders_audit.*`, `reports/extrabuffer_write_audit.*`, `reports/wgsl_precommit_report.json` — **coordinator: discard those**, I did not touch them with git.

## 4. Open items / honest limits
1. `arm_tightness` is dead at silence (galaxy) — kept per the card. A one-line fix would be `tightness = 0.18 + p1·0.06 + bass·(0.22 + p1·0.15)`, which moves the silent default pitch 0.18 → 0.21.
2. galaxy `orbit = time·rate` snaps the whole pattern by `Δrate·time` when mids/p3 change (HEAD, KEEP VERBATIM). Stars use `(rate − Ω)·time`, so they snap with it.
3. Differential rotation is a position-only idea on 96 sparse stars: ~3.7 % of the frame at default; it will read as slow drift (inner stars ≈ 0.29 rad/s relative, corotation ≈ r 0.38 at default spin).
4. Silent default pitch of the galaxy is HEAD's tight 10° log spiral (ring-like in the first second); open arms appear with bass. Real-GPU look unverified.
5. The HII knots are a hash-cell field on (r, s); they are locked to the pattern, not to a star. At 192² they are 1–2 px pink dots; they read best ≥ 384².
6. Aurora Idea 3 uses the analytic sinusoid slope only (fbm warp derivative ignored), so it brightens by the nominal fold, not by the warped one; at silent default it is a 5 % effect and the folds it picks are the nominal ones. Under audio it is +28 % mean luma by design (idle +15 %).
7. Aurora's red top fringe at 0.7 weight is physically the O 630 nm line; on the default pink/violet hues it reads as a warm fade rather than distinct red. Not retuned further.
8. No real-GPU visual claim. SwiftShader and numpy-free proofs only.
