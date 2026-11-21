# NOTES — fork D (liquid-smear) — sonnet/batch-51

Files touched: `public/shaders/liquid-smear.wgsl`, `shader_definitions/liquid-effects/liquid-smear.json` (description sentence only). Nothing else; not committed.

## Salvage check (coordinator request)
`git log -S'Ideas'` and `git log --all -G'^//  *Ideas'` on the file return nothing; Jules-bot `9b5cd56e` never touched it. HEAD is the intact 2026-08-23 "Batch 58B + tensor-guided precision pass" text (`cc170f24`, 245 lines); `9418838b` (prelude migration) changed header lines only. No earlier upgraded version exists, so nothing to salvage.

## Idea Card — see BRIEFS-forkD.md (written before any WGSL edit; the card was kept, only constants were retuned)
IDENTITY: the live photo as wet pigment that the pointer rakes along its stroke, edge-guided, bleeding per FFT band, splatting on clicks.
KEEP VERBATIM (verified): 4 sliders + roles (`strength`/`size`/`decay`/`mix`), saved params byte-exact (JSON `params` untouched), spring constants, strokeDir/guidedDir, 5-tap normal bleed + monotone clamp, exact-load bilinear history, cold-start seed, click splat loop, refresh, tints, fibre sin, ACES, semantic alpha, depth pass-through, A packing.
**Proof of "kept": with a static, silent pointer the new file is bit-identical to HEAD** (192², 60 frames, saved defaults: rgb max |diff| 0, alpha |diff| 0). Clicks: rgb max |diff| 1/255.

## Rescues (loud)
- **R1 — dead pointer velocity + racy brush position (engine-faithful harness).** HEAD kept the spring in `extraBuffer[133..136]`, which `writeExtraBuffer` zeroes before every dispatch. Instrumented HEAD (speed and `mousePos` written to RGB), held pointer sweeping x 0.15→0.85: `speed` max **0.000** everywhere (persisting buffer: 0.745) → `strokeDir`, `dragLen`, `offset` all 0, i.e. **the pointer drag never happened in the engine**, only click splats moved pigment. In that run **70.4 % of invocations read `mousePos == (0,0)`** (they race invocation (0,0)'s write; schedule-dependent — an idle run on the same box happened to read the pointer). Fix: the 4 floats (smoothed pos, smoothed vel) ride in texel (0,0) of A→C; every invocation recomputes the identical spring step from last frame's texel (deterministic), invocation (0,0) alone stores it; `loadC()` redirects every history load of texel (0,0) to (1,0) so state is never read as pigment; an empty/out-of-range/non-finite texel restarts from the raw pointer. After: speed **0.745 at every pixel** (uniform, = persisting-buffer value), `mousePos==(0,0)` for **0 %** of pixels. Cost: one extra broadcast load per pixel + a `select` per history load; one texel of pigment sacrificed in a corner (its history reads texel (1,0)).
- **R2 — per-band FFT was a constant 0.** `band = plasmaBuffer[bandIdx+1].x`; `writePlasmaBuffer` only fills `plasmaBuffer[0]`. Now `0.5·(extraBuffer[5+4b] + extraBuffer[5+4b+1])` (engine FFT bins, 0..1). Silent audio → identical to HEAD; with a synthetic bass-heavy spectrum HEAD-vs-new differs on 11.6 % of pixels (max 12/255): bleed is now audio-responsive as the header always claimed.
- Not changed (found, left alone): drag magnitude calibration (`speed·0.02` per frame lets pigment outrun the pointer ~1.9× at strength 1 held); HEAD's `normalDir`/`bleedPx` are built in uv components and applied as pixel components (not screen-perpendicular when aspect ≠ 1 — harness is square so unmeasured); `depth-aware` tag is a pass-through only (depth is read and re-written, never used).

## Ideas (all three consume quantities the file already computed; marked `// ── Idea n` in the WGSL)
1. **Bank and wake** — §12.2D shallow-water continuity. `rho = clamp(1 − ∇·offset, 0.6, 1.6)`, divergence analytic from `brushFalloff`'s derivative (aspect-correct; no extra taps). Feeds `thickness` (alpha) and a Beer–Lambert shade `exp(−(rho−1))` on the pigment *inside* the Mix Strength blend, display-only (A stays plain pigment, so no feedback accumulation). Ahead of the brush rho>1 (denser, darker), behind <1 (thin). Verified by a debug channel on a diagonal stroke: bank ahead, wake behind.
2. **Bristle rake** — §12.2C stroke tangent (direction, not just magnitude). Across-stroke coordinate in the brush frame (aspect-corrected), 1-D smooth bristle profile `rake ∈ [0,2]`, mean 1, scales drag length per lane; lanes with `rake<1` (gaps) also pull fresh plate through the existing `refresh` term in proportion to drag intensity. Lane field checked on a diagonal stroke: lanes run parallel to the motion, fixed in the brush frame. `hash11`/`pcg`/`u32ToUnit` copied verbatim from `_std/_std_hash.wgsl`.
3. **Speed-thinning** — §12.2C `R = R0 / (1 + 0.35·|v|)`: Brush Size stays the radius at rest, fast flicks rake with a narrow brush.

Formula rows used: shallow-water continuity (§12.2D), stroke tangent / speed-thinning (§12.2C). None shared with other forks' claims.

## A packing
Unchanged: pre-ACES pigment RGB + alpha (≥0.02) in A, read back as C colour. Exception: texel (0,0) = (smoothed pos xy, smoothed vel xy). B untouched; extraBuffer[0..132] untouched, no `[133..255]` use; extraBuffer[5..132] read-only (engine FFT).

## Honest visibility (SwiftShader, no real GPU — not visual QA)
HEAD's smear is intrinsically gentle: on a photo-like noise source at strength 1 / mix 1 / persistence 1 the whole drag (rescued file, moving vs static pointer) moves the picture by only **3.7/255 mean (max 36) in the stroke strip**; the saved defaults (mix 0.19) are subtler. The ideas scale with that. Ablation, each idea switched off in turn vs the full file (256², photo-like source, held sweep, mix 1): pile-up 3.6 % of px >3/255 (max 12); bristles 1.7 % (strip mean 1.5, max 13); thinning 4.3 % (max 24). The bristle lanes are the weakest: repeated per-frame bilinear history resampling low-passes narrow lanes, and the aggregate lane signal is not strongly directional on this source (dy/dx ≈ 1) even though the lane field itself is correct. A real photo with detail will show more; a real-GPU look is required. Retunes made during verification: lane depth 0.5..1.5 → 0..2 plus the bare-lane `refresh` term (lane diff doubled), shade coefficient 0.6 → 1.0.

## Diff vs HEAD (rescue-only baseline, photo-like source, held sweep)
Full vs rescue-only: 5.1 % of px >3/255 (max 18). Rescue-only vs HEAD(engine): 32.7 % >3/255 — mostly the revived drag, i.e. the *intended* look that HEAD never showed in the engine.
Diff size: +119/−40 lines; 62 of 159 changed lines are comment-only; the rest are R1/R2 plumbing (~40) and the three ideas (~35).

## Gates
on the final file: `wgsl_precommit_gate.py` 1/1; `verify-naga-wasm.mjs` 1/1; `audit_dead_sliders.py --files liquid-smear` 0 new dead (all four sliders read, lines 153–156); `audit_extrabuffer.py` PASS. (The audit scripts rewrote `reports/dead_sliders_audit.*` and `reports/extrabuffer_write_audit.json` — shared generated files; coordinator to discard.) no NaN in any render (idle, clicks, FFT, held sweeps, strong settings).

## Timing
`agents/mr_ab.mjs 256 40` held pointer, audio 0.3/0.2/0.1, saved defaults, HEAD vs new interleaved, 4 rounds on a loaded box (four forks + another session's job): paired-median ratios **1.02 / 1.15 / 0.98 / 1.33** (median **≈1.09×**), min-of-frames ratios 1.06 / 0.99 / 1.15 / 1.22 (median ≈1.10×). Round 4 is the loaded-box outlier; the cap is ~1.3×, so this is inside it on the median but the coordinator should re-time on a quiet box. No data-dependent branches were added (everything is `select`/`mix`/`clamp`), so cost does not depend on pointer motion; the extra work is one broadcast C load, 9 `select`s on history loads, the analytic divergence and one 1-D hash lerp per pixel.

## Could not verify
Real-GPU look; non-square aspect (harness is square — aspect math written correctly but unmeasured); real adapters without `float32-filterable` (loads are exact `textureLoad`, unchanged); behaviour when an effect chain hands this shader a C texture still holding another effect's data (guarded by the state-validity test, a 1-in-many chance of a one-or-two-frame glitch if the foreign texel happens to look like a valid state); the `extraBuffer` engine fix (`writeExtraBuffer` writing only `[0..132]`) is a user decision and out of scope.
