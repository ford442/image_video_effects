# NOTES — fork C (gen-abyssal-geode-matrix, gen-flame-fractal-attractor)

Base = HEAD of sonnet/batch-38 (origin/main 7f6ce638 + header-only prelude migration of two other files; neither of mine was touched by it).
Evidence: SwiftShader WebGPU via `agents/mr.mjs`, `SRC=img`, **saved defaults passed explicitly** (abyssal `0.5,1.0,0.8,1.0`; flame `0.55,0.45,0.7,0.65`), `A16=1` for the flame (it feeds C). Visibility = % of pixels whose max-channel |Δ| > 0.02 between "idea on" and "idea multiplied to zero" scratch copies (`sed`-generated, in my scratch dir). No real-GPU claims. Scratch: `/tmp/claude-0/-root-image-video-effects/3bc05086-3a8b-4229-9600-41329cbd28af/scratchpad/forkC/`.

---

## 1. gen-abyssal-geode-matrix — FIRST PASS

**KEEP VERBATIM held?** Yes for the geometry: the abs-fold + `rot` loop, `iters = max(1, 4w)`, domain repetition c=4, `sdOctahedron`, `getNormal`, the 100-step marcher and `glow += 0.01/(0.01+dS²)`, forward camera, `lightDir`, base colour (0.05,0.15,0.25), emissive cyan·bass + magenta·mids × glowIntensity, the four params with RAW ranges. Three deliberate deviations, each from a measured defect: (a) the well's world anchor (Rescue 5; the well block moved into `foldedStart()` shared by `map()`/`trapAt()`), (b) a per-step distance fade `max(1 − dO·0.05, 0.12)` on the glow accumulation, (c) the glow scale (Rescue 3).
**A packing:** ACES display RGBA (HEAD stored nothing; nothing reads C). Depth = `coverage·exp(−dO·0.12)` (near = 1). Alpha = `0.10 + coverage·0.72 + glowLum·0.18`, clamped 0.10–0.98.

### What HEAD actually looked like (render, 192 px, saved defaults)
| case | HEAD | new (final) |
|---|---|---|
| idle (bass=mid=treb=0) | **meanL 0.000** — an exactly black frame (every pixel, hits included) | meanL 0.174, alpha mean 0.84 |
| bass/mid/treb 0.8/0.5/0.9 | **meanL 12.84, stdL 9.7** — raw unclamped HDR, a white frame | meanL 0.387, alpha mean 0.87 |

### Rescues (card R1–R4 + one more) — all confirmed at HEAD
- **R1 confirmed:** `ao = 1.0 − f32(MAX_STEPS)/100.0` is exactly 0.0; the lit-surface term `baseCol·diff·ao` is black (HEAD's idle frame is exactly 0 even where rays hit). Replaced by Idea 3.
- **R2 confirmed:** `emissive = cyan·bass + magenta·mids` is 0 at silence → black frame, `glowIntensity` does nothing without audio. Idle floor `cyan·(0.25+bass) + magenta·(0.10+mids)`.
- **R3 confirmed:** with audio the raw glow sum gives meanL 12.8 (white). Scale `0.04` + the per-step fade put default exposure mid-range. **Default-look change: black / white → a lit cavern.**
- **R4 confirmed (source):** only `writeTexture`, alpha a bare `1.0`, no ACES, no depth, no A. Fixed (see packing).
- **R5 (not on the card) — the gravity well is dead after ~10 s.** HEAD anchors it at world z = 0 (radius 2) while the camera flies `z = −3 + 0.5t`; past t ≈ 10 s every ray starts beyond z = 2 and never touches it. The y was also flipped against the ray convention (`0.5 − mouse.y`, no aspect), so the well was not under the cursor even at t = 0. Measured, held cursor vs free: **HEAD t≈0 85 % of pixels differ, t≈20 exactly 0.00 %.** Fix: `gWell = ro + vec3(mouseUv·3, 3)` (a `var<private>` set in `main`, +y-down like `uv`). New: **t≈0 68.9 %, t≈20 17.1 %**; cursor x = 0.2 vs 0.8 (t≈20, held) differs by 15.9 % (measured on the pre-trim source). This changes `map()`'s well block (3 lines), which the card said to keep verbatim — flagged. Geometry/fold untouched.

### Ideas (final source, `public/shaders/gen-abyssal-geode-matrix.wgsl`)
Visibility, idea on vs multiplied to zero, 192 px, saved defaults (idle / bass-mid-treb 0.8/0.5/0.9):
1. **Orbit-trap mineral veins (§12.2E)** — `trapAt()` (line ~77-107): the same fold loop as `map()`, run **once at the hit** (not every step), `trap = min(trap, |p.x−p.y| / (2s+0.1))`; at the hit (~176) `vein = 1 − smoothstep(0, 0.025, trap)`, amber (1.0,0.62,0.22) × `(0.55 + treble·0.9)`, lit by `(0.4 + 0.6·diff)`. **18.4 % / 20.3 % of pixels**, mean |Δ| 0.022 / 0.041. At 576 (measured on the pre-trim source, identical maths): 18.3 % / 20.4 %. Four trap definitions were compared as thresholded masks: `length(p.yz)/(s+0.15)` is dominated by the last, tiny iteration (median 0.146, ≈1 everywhere at `exp(−3t)`), `|p.x−p.y|` gave the most line-like filaments. Treble modulation is in but not measured separately.
2. **Beer–Lambert deep-water absorption (§12.2F)** — (~160-175) `σ = (0.30, 0.09, 0.04)`, `absorb = exp(−min(dO,24)·σ)` on the surface, `absorbGlow` (cap 14) on the glow, + teal in-scatter fog `(0,0.03,0.06)·(1−exp(−min(dO,40)·0.15))`. **83.9 % / 100.0 % of pixels**, mean |Δ| 0.126 / 0.307 (576, pre-trim: 80.8 % / 99.9 %).
3. **Step-count AO (§12.2E, snippet E2)** — `aoFive` (line ~109), strength 3.4, 5 extra `map()` calls at the hit. **28.6 % / 15.3 % of pixels**, mean |Δ| 0.017 / 0.010 (576, an earlier strength of 2.4: 22.2 % / 12.4 %, i.e. size-independent). Weakest idea by mean |Δ|; strengthened once, not iterated.

§12.2 rows: orbit trap, Beer–Lambert, step-count AO. No springs, ripples, IQ palette.

### Sliders (min→max, held cursor, mild audio): % of pixels with |Δ| > 0.02
gravityPull 84.7 · fractalSpeed 97.2 · glowIntensity 100.0 · fractalDetail 96.8 (measured on the pre-trim source; `map()`'s fold body is unchanged by the trim). All four live.

### Cost (SwiftShader, min of drained frames, interleaved HEAD/new, 192 px, audio 0.8/0.5/0.9)
Load average on the VM swung 8 → 77 from sibling forks, so treat as indicative; **the coordinator should re-time alone.**
- Final source, 5 rounds at load ≈ 10–26: **median 1.25×** (only the median and the last round, 0.85, were kept; per-round spread not recorded). Variants vs HEAD in the same run: no-AO 1.14×, no-vein 1.10×, neither 1.13× — i.e. each idea is within noise of ~+5–10 %.
- Earlier runs under load 40–77 gave medians 1.46–1.60× (pre-trim 1.32× in the same quiet-ish window) — load, not the shader. Before the trim, the vein trap ran inside `map()` on every march step; now it runs once at the hit (`trapAt`), and the glow fade is a linear `max(1 − dO·0.05, 0.12)` instead of an `exp2` per step (that brightened the frame: meanL idle 0.147 → 0.174, audio 0.324 → 0.387).
- Every pixel is a hit in this lattice (hit fraction 1.0 at 192 px), so the 5 AO + 1 trap evaluations are paid per pixel, vs ≤ 100 march steps.

### Gates
`wgsl_precommit_gate.py --files` ✅ · `verify-naga-wasm.mjs --files` ✅ 2/2 valid (both of my files, final sources) · `audit:dead-sliders -- --files gen-abyssal-geode-matrix gen-flame-fractal-attractor` 0 new · `audit:extrabuffer` PASS (0 new). NaN 0 in every render whose stats I printed.

### Open items
- Every ray ends as a "hit" (`dO < MAX_DIST`), including rays that exhaust 100 steps at a grazing surface (HEAD's rule, kept), so `coverage` ≈ 1 and alpha varies mostly through glow, not sky-vs-surface.
- Glow scale / fog / AO constants were tuned by eye at 192 px; real-GPU look is external. Amber veins are thin: they resolve at 576, not at 192.
- The well is 3 units ahead of the camera, radius 2 (HEAD's radius). `gWell`'s distance is the one number to change if the owner wants a larger/closer well.

---

## 2. gen-flame-fractal-attractor — 3rd pass

**KEEP VERBATIM held?** Yes: the 36-iteration loop and every accumulator (creaseAcc, evenDen/oddDen, lineTrap, capture/contour), the four `mix` ranges, held vortex, click embers, ACES on writeTexture, `≤ 8` clamp, semantic alpha, depth; the `riseCoord` exact load + wobble kept, with the rise *distance* made resolution-relative (see Idea 4).
**A packing (changed truthfully):** HEAD was "raw HDR display RGBA". The log-density display is applied to the fresh `hdrColor` BEFORE the history mix, so A is now **log-density display-linear HDR RGBA, ≤ 8** (still fed back through C as colour; ACES on writeTexture only). Header and JSON `feedbackPacking` updated.

### The card's premise was wrong — what HEAD actually is
The card assumed "dense cores clip flat". Measured at HEAD, saved defaults, idle:
- **99.13 % of pixels have max-channel ≥ 0.98 after ACES, meanL 0.981, p50 1.000 — from frame 1** (not a feedback runaway: frame 1 is already 100 %; the 576 run is 99.10 %). The committed `public/thumbnails/gen-flame-fractal-attractor.png` (made in the real app) is also 100 % ≥ 0.98, so this is not a harness artifact.
- Cause: the IFS is contractive, so after ~15 iterations every pixel's orbit sits on the same attractor and the late iterations add a **pixel-independent plateau**. At frame 1: `orbitDensity` 3.2–4.8, `density` 1.8–2.5 (±15 %), `creaseAcc` 3.0–5.7; final HDR ≈ (8 [the clamp], 3.9, 3.4), lum ≈ 4.75 everywhere → ACES white. Plateau lum vs Ember Bloom slider: 1.9 (slider 0) → 4.75 (0.65) → 5.7 (1.0).
- With loud audio (0.8/0.5/0.9) the trap exponent `4.5 + 2·audio.x` steepens and the frame has structure (lum p5/50/95 = 0.32/0.89/1.82), but HEAD is still bright: meanL 0.773, 53.8 % of pixels ≥ 0.9.
- A pure log curve cannot restore structure that is not in the data at silence, and **the card's "meanL within ±10 % of HEAD" cannot hold** (HEAD = 0.98 = white). I treated the display transfer itself as the fix.

### Ideas (numbered 3 and 4 in the file; the 2026-10-10 pass owns Idea 1/2) — `public/shaders/gen-flame-fractal-attractor.wgsl`
3. **Log-density flame display with vibrancy (native, Draves)** — lines ~110-121. `hdr' = mix(perChannelLog, dens·(logLum/lum), 0.75)`, `K = 4`, reference 30 (`flameNorm = 1/log(1+K·30)`); a fixed reference, so Ember Bloom keeps a monotonic range.
   - **% px with max-ch ≥ 0.98 (60 frames, A16, 192 px):** idle HEAD **99.13 % → 0.00 %**; audio 0.20 % → 0.00 %. 576 px (24 frames): idle 99.10 % → 0.00 %; audio 0.24 % → 0.00 %. (≥ 0.9: HEAD 100 % / 53.8 % → 0 % / 0 %.)
   - **meanL:** idle 0.981 → 0.685; audio 0.773 → 0.473. p50 max-channel idle 1.000 → 0.831.
   - vs "idea off" (HEAD transfer): 100 % of pixels, mean |Δ| 0.375 idle / 0.355 audio (576: 0.375 / 0.343). It is a transfer function — the whole-frame default-look change, not a local overlay.
   - What you see: with audio a swirling magenta / orange / purple flame with real contrast; at silence a pale salmon field with the attractor's faint swirl and two dark ember knots (HEAD: white). **Silent frames still have low contrast** — see open item 1.
4. **Blackbody cooling of rising embers (§12.2F) + ember persistence** — lines ~13-14, ~124-135. History is multiplied each frame by `exp(−(0.004, 0.022, 0.07)·COOL_GAIN)` (blue dies first), HEAD's `mix` weight is kept, then **`max(hdr, cooledHist·EMBER_KEEP)`**; the `riseCoord` offset is `round(res.y/96)` px (= 2 at 192 px, HEAD's value; 6 at 576; 11 at 1080), wobble amplitude `0.75·that`.
   - **The card's literal form (tint only) is invisible, measured:** 60 frames, audio on, tint on vs off: **0.00 % of pixels > 0.02; mean R/B 1.624 → 1.639 (+0.9 %).** HEAD's history weight is 5.5–12 % per frame, so a trail is 2–3 px long and carries nothing to redden; the 2026-10-10 "rising ember" idea is itself nearly invisible for the same reason.
   - Added persistence (deviation from the card; same noun and what the previous pass claimed): embers outlive their frame, rise, redden and dim for ~10–25 frames. First setting (gain 1.5 / keep 0.86): audio 4.0 % px (persistence alone 6.5 %, cooling on top 2.1 %), idle 0.78 %. Shipped gain 2.5 / keep 0.92.
   - **Resolution defect found at 576 px:** HEAD's fixed 2 px/frame rise is ~0.2 % of the frame height per frame at 1080p. Measured with the fixed rise: 192 px 9.9 %, **576 px 1.4 %** of pixels. With the resolution-relative rise (identical at 192): **192 px 9.95 %, 576 px 10.98 %** (audio, 24–40 frames, mean |Δ| 0.0135 / 0.0137). Idle: ≈ 0.8 % (192) / 0.6 % (576, measured before the rise scaling, not re-measured).
   - Idle is low because the silent frame is a plateau: nothing is brighter than the embers' own history, so `max` has nothing to preserve. Visible, subtle, audio-driven — report as such.

§12.2 row used: blackbody. Log-density is native to flame fractals, not a table row.

### Other checks
- Sliders (min→max, mild audio, 20 frames, A16): Attractor Strength 91.1 % · Orbit Speed 97.8 % · Curl 100 % · Ember Bloom 100 % of pixels > 0.02. All live.
- Held cursor vs idle: 76.5 % of pixels.
- Click ring (a patched copy of the harness in my scratch dir injects one ripple): with audio, ring vs none **HEAD 0.70 % → new 0.74 %** of pixels > 0.02 — unchanged. At silence both 0.00 % (the ring adds +0.42 on a plateau of ~8; on the log display ≈ 0.017 per pixel, below threshold) — a pre-existing invisibility, not a regression.
- NaN 0 in every render whose stats I printed.

### Cost
Added per pixel: a `log` of a vec3, a scalar `log`, a vec3 `exp`, a `max`; no loop changes, no extra loads. Interleaved min-of-drained-frames, 6 rounds, 192 px, audio on, **under VM load 24–77**: median **1.11×** (round ratios 0.78 … 1.67 — pure noise at this load). The coordinator should re-time alone.

### Gates
`wgsl_precommit_gate.py --files` ✅ · `verify-naga-wasm.mjs --files` ✅ · `audit:dead-sliders` 0 new · `audit:extrabuffer` PASS (all run on the final source).

### Open items (owner's call)
1. **The silent frame still has almost no structure.** The plateau is intrinsic to the accumulators the card said to keep (contractive map + late iterations + the `4.5` trap exponent). A real fix — weight late iterations down, subtract a tail-iteration plateau, or steepen the trap exponent at silence — changes the saved-default look and breaks "accumulators verbatim", so I did not. The previous pass's contour filaments and rising embers sit at ≈ 6 % of the plateau at silence (contour's HDR contribution ≈ +0.46 vs a plateau of 8 — reasoned from the HDR scale, not rendered in isolation).
2. Display reference (K = 4, 30) and the persistence constants were chosen by eye at 192 px; real-GPU look is external. Ember Bloom now compresses less at the high end than before.
3. Ember persistence is frame-rate dependent (per-frame constants), like HEAD's history mix. The resolution-relative rise changes the ember motion at real working sizes (HEAD: ~2 px/frame at any size).
4. Reports side effect: the gates rewrote `reports/dead_sliders_audit.*`, `reports/extrabuffer_write_audit.*`, `reports/wgsl_precommit_report.json` in the worktree — not part of this fork's work; the coordinator discards them (and I did not use `git checkout`).
