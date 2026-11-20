# NOTES — fork C (sonnet/batch-47)

Both files FIRST PASS (no `Ideas:` at HEAD). Coordinator's header-only prelude migration was already in the tree; `Upgraded: 2026-11-20` + `Ideas:` + `A packing:` added by this fork. Saved `params` byte-exact (verified by JSON comparison vs origin/main). Nothing committed. Renders: SwiftShader, `agents/mr.mjs`, `SRC=img` (and `SRC=tex`), 192 px — **no visual QA claim**, structural + numeric only.

Scripts: `forkC_perf.sh` (interleaved HEAD/new timing, uses `agents/mr_perf.mjs`).

---

## spec-temporal-path-tracer — `public/shaders/spec-temporal-path-tracer.wgsl`

**Idea Card ADD (3), each findable by its `// ── Idea n` comment:**
1. Stratified march lattice — jittered 2-px step start (`marchToEdge(..., lattice)`), kernel deepening (§12.1 tactic 1, Monte-Carlo stratification). Removes the concentric quantisation rings HEAD bakes into the converged image.
2. Hit-distance falloff — §12.2F soft inverse-square, 2D law: `clamp((26+12)/(d_px+12), 0.45, 1.25)` on the gathered radiance (the distance `marchToEdge` already found; tactic 3). Colour bleed is local; exposure kept (mean luma 0.196 vs 0.198 on SRC=img).
3. History that can forget — fingerprint (centre + 4 diagonals @5 px mean luma) in the fraction of `A.a`; |Δfp| → `smoothstep(0.025, 0.10)` shrinks the kept sample count (TAA history rejection, fork-C row); bounded 300-sample exponential horizon replaces the 300-frame hard reset; horizon 32 while the pointer light is held.

**KEEP VERBATIM:** 4 params and roles; `marchToEdge` (32 × 2 px, edge test); `edgeStrength`/`edgeNormal`; reflect + roughness jitter; Russian roulette; sky pickup 0.3; mouse-held 30 % pull; white-noise ray angle; raw HDR accumulation, ACES on writeTexture only; depth pass-through.

**A packing:** raw accumulation. `A.rgb` = mean radiance (HDR, not ACES'd). `A.a` = `n + 0.9·fp` (n integer ≤300, fp ∈ [0,1]); HEAD `a = n`. Only this file reads it (as `floor` / `fract`). rgba32float exact; would not survive an A16 harness (`A16=1`), the engine uses rgba32float. writeTexture alpha = source coverage ∪ convergence (≈1 for opaque sources).

**Rescues / HEAD defects:** (a) 300-frame hard reset to 1 spp (full-frame pop) → bounded EMA. (b) history never forgot → ghosting on video; pointer light barely visible (1/300 weight) → fingerprint rejection + short held horizon. (c) converged image printed 2-px quantisation rings (see Idea 1). (d) no bounds guard added. (e) header called the angle "blue-noise" while it was a white hash (comment corrected; behaviour unchanged).

**Not a gain (measured, dropped):** low-discrepancy R1/R2 ray angle — no convergence benefit (hf-noise 0.0180 vs 0.0170 @60 frames; err vs 280-frame reference not better).

**Diff vs HEAD (60 frames, defaults, 192 px, SRC=img):** 39 % of pixels differ > 0.02 in some channel (noise-dominated), 16.6 % after a 5×5 blur; mean|d| 0.022; meanL 0.196 vs 0.198; NaN 0. Stale-history test (`SEEDC=1,1,1,250.5`, 20 frames): HEAD stays a uniform ghost (stdL 0.001); new rejects it wherever the source luma fingerprint differs (stdL 0.30; kept only where fp happened to match — a 1-scalar fingerprint has false negatives).

**Timing (SwiftShader, interleaved HEAD/new, 8 rounds, box loaded):** median ratio 1.14, min-of-rounds 1.09 (cap ≤1.3). Extra work: 5 luma taps + 1 source tap per pixel; the 32-step march dominates.

**Gates:** precommit 1/1; naga-wasm 1/1; dead-slider 0 new; extraBuffer PASS (file doesn't touch it). `Features:` += `upgraded-rgba` (ACES + ideas implemented); JSON `features` += `upgraded-rgba`, description appended, `x-meta.upgrade.params` added (additive).

**Could not verify:** real-GPU look; video re-convergence on a real changing source (only the stale-seed proxy); pointer-held horizon visual (only that it runs, NaN 0).

---

## gen-chrono-erosion-feedback-melting — `public/shaders/gen-chrono-erosion-feedback-melting.wgsl`

**Idea Card ADD (2):**
1. Flow-lane persistence (erosion channels) — §12.1 tactic 4 (second-order `Trail Decay`): `meltW = meltBase·(1 + 0.35·lane)`, `lane = smoothstep(0.3, 0.9, |curlPix|)` (the curl magnitude already computed; tactic 3). Trails run longer along the streaming lanes; calm regions unchanged; Feedback Mix 0 still live-only.
2. Macroblock motion carry — §12.2B datamosh row, stateless: curl also evaluated at the 16×16 block centre (`curlBlk`); weight `smoothstep(0.3, 0.85, |curlBlk|)·0.75` pulls the pixel's curl vector toward the block's, so fast streams tear into rigid blocks. Mouse / vortex / shock terms stay per-pixel.

**KEEP VERBATIM:** 4 params and roles (`decay`, `flowIntensity`, `turbulence`, `feedbackMix` incl. `meltBase = clamp(decay·feedbackMix/0.6)`); curl noise (eps 0.01, uv·3, t·0.1); cursor smudge; ripple vortices (2 s, exp(−1.8 age)); bass>0.6 shock; displaced feedback blend; flow-magnitude colour shift; beat inversion; 1.5 clamp.

**A packing:** display-colour history in `A.rgb` (HDR ≤1.5, pre-ACES), `A.a = 1.0` (unread), as HEAD. ACES only on writeTexture; alpha = source coverage ∪ melt energy (data-moshing convention). dataTextureB untouched.

**Rescues (default look changes — all flagged):**
- Half-texel bias: HEAD used `id/res` (pixel corner) for live + history → each loop iteration shifted the feedback ½ texel up-left and blurred 2×2. Now pixel centre. With low flow + max persistence (`params 0.5,0,0,1`, SRC=tex, 60 frames) Laplacian-std 0.0484 (HEAD) → 0.0856 (new): 1.8× the detail survives the loop.
- Filtering `u_sampler` on rgba32float history → exact `loadBilinear` (4 loads, `_std_sample` verbatim).
- Dead spring: `extraBuffer[133..138]` is re-uploaded as zeros every frame (`src/renderer/webgpu/audioDepth.ts:56`, `extraScratch` 256 floats) → HEAD's spring re-initialised to the raw cursor every frame. Pinned to the raw cursor (identical behaviour); extraBuffer writes removed.
- Dead audio: `plasmaBuffer[1..8].x` never uploaded (only `[0]`) → `bandEnergy` was 0. Now live FFT `extraBuffer[5 + (2^band − 1)]` (octave bins 0,1,3,..,127) averaged with the next bin, ×0.5 as HEAD. Verified it runs (synthetic FFT bins), not that it looks musical.
- ACES on display (A keeps the HDR history). Global tone change: meanL 0.425 → 0.525 on SRC=img, colours paler.
- Not changed (flag): sustained loud audio (sum of bass+mid+treble > 0.7) inverts the loop every frame and collapses the picture to flat grey — at HEAD too (stdL 0.011 vs 0.007).

**Not shipped (measured, dropped for cost):** Catmull-Rom + limiter history resample: Laplacian-std 0.120 (vs bilinear-exact 0.097) at 1.67–2.3× HEAD; axis-cubic (8 loads) 0.107 at 1.4–1.57×. Both over the 1.3× cap.

**Diff vs HEAD (60 frames, defaults 0.5,0.3,0.4,0.6, 192 px, SRC=img):** 99.9 % of pixels differ > 0.02; mean|d| 0.141; 91.6 % after a 5×5 blur (ACES + drift fix + blocks). NaN 0, alpha 1.

**Timing:** median 1.235, min-of-rounds 1.24 (cap ≤1.3). Cost = 4 loads instead of one filtered sample + a second curl evaluation at the block centre.

**Gates:** precommit 1/1; naga-wasm 1/1; dead-slider 0 new (all four sliders read); extraBuffer PASS. JSON: description appended, `features` += `upgraded-rgba`; `x-meta.upgrade.params` already aligned.
