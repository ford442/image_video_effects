# NOTES — fork A (sonnet/batch-52): temporal-frequency-decomposition, spatio-temporal-3d-conv

Harness: `agents/mr_hist.mjs` (8-layer ring of outputs, FFT bins, [133..255] zero), scratch copy with `NOISE=` for noise tests. HEAD = coordinator head/ copy. All numbers SwiftShader, no real GPU, no visual-QA claim.

## temporal-frequency-decomposition  (header: Upgraded += 2026-11-22; Ideas += "DC-detrended DFT")

- **IDENTITY / KEEP VERBATIM:** single-frequency temporal DFT over the history ring, 4 params + roles, Hann window (Idea 1), phase→hue (Idea 2), `textureNumLayers` ring depth, cursor lens (boost ×1.8, widen), click tuning-fork pings, 8-band voices, alpha formula, A = display RGBA.
- **ADD (1 idea):** Idea 3 **DC-detrended DFT** (`X' = Σw·x·e^{-iωt} − μ·Σw·e^{-iωt}`, μ = Σw·x/Σw; 3 extra scalar/vec3 accumulators on the SAME 7 taps). Hann (N=8) leaks 29 % of a still pixel into the response at the default 0.1625 c/f (65 % at 0.1, 90 % at 0.05; 0 % at ≥0.25). Static pixels now give 0 at every frequency.
- **Rescues (change the default look — LOUD):**
  1. Static leakage (this IS Idea 3's visible effect): HEAD tinted the whole frame orange-yellow with its own DC and lit the lens into a red blob over a still background (corner/centre cursor comparison, STATIC=1). Default render vs HEAD: RGB differs on 100 % of px, mean |Δ| 0.183 (HEAD's glow was ~0.14–0.38 everywhere); mean alpha 0.543 → 0.330 (alpha carries energy·2.5, so the floor is now baseBlend·0.3 + bass·0.2). On a 1-layer ring HEAD's "DFT" was the picture itself (meanL 0.54 vs 0.11).
  2. **Dead FFT voices:** `plasmaBuffer[1..8]` is never written by the engine (only `[0]`, `audioDepth.ts:62-72`); voices were identically 0. Now 4 taps of each band's 16-bin slice of `extraBuffer[5..132]` ×0.4. At silence identical to HEAD; with audio left bands shimmer per bin. (63 catalog shaders read `plasmaBuffer[1..8]` — library-wide dead audio, outside this fork.)
  3. **Lens limit cycle:** `pow(e, 1−0.25·lens)` replaced by `e·mix(1, smoothstep(0.04,0.35,e), 0.5·lens)` (dead-zone sharpen, never above the ×1.8 gain). 120-frame run: HEAD/earlier NEW left a persistent glow ghost where the disc crossed the lens; now gone (cmp_long3.png).
  4. **ACES on the emitted glow only** (P-ACES b), clamped ≥ 0, photo path untouched; `upgraded-rgba` tag kept (now true). ACES lifts mid glow ≈1.3–1.5× and rolls off above ~0.7.
  5. Header truth: the spring in `extraBuffer[133..137]` is zeroed every frame (lens = cursor 1:1), `extraBuffer[0..2]` ARE bass/mid/treble; A packing line added.
- **A packing:** display RGBA = writeTexture, unchanged; the ring holds this shader's own outputs so the analysis sees its own glow (documented).
- **Diff vs HEAD @defaults:** RGB 100 % of px (see above — intentional). Silence / FFT off / D=8,4,1 / bass 2: nan 0. Pings verified (yellow blob at the click on the stock 1-layer harness; HEAD glowed the whole frame).
- **Timing (interleaved, ring populated, loaded box 13–20):** @128: paired-median 1.03 / 1.15; @256: paired-median 1.00, p25 1.22, min 1.54 (outlier). Expected ≈1.1× (3 accumulators + 4 buffer loads + aces). Coordinator should re-time on a quiet box.
- **Dropped:** spectral purity idea (see BRIEFS amendment).
- **Not done (engine/user calls):** spring state in `extraBuffer[133..]` cannot persist, so the "sprung" lens is a raw cursor; fixing it needs state outside the zeroed range (engine decision).

## spatio-temporal-3d-conv  (header: Upgraded += 2026-11-22; Ideas += 2; `upgraded-rgba` removed)

- **IDENTITY / KEEP VERBATIM:** 3×3 Gaussian × T history frames, 3 modes (NR / motion blur / temporal sharpen, thresholds 0.33/0.67), 4 params + roles, NR bilateral-in-time (Idea 1) + variance-driven strength (Idea 2), `tw` profiles, bass→strength, treble→NR decay, ring-depth guard, A = display RGBA.
- **ADD (2 ideas):**
  - Idea 3 **linear-light shutter integration (motion-blur mode only):** trail accumulated as `max(rgb,0)²` with the same 0.85^age weights, mixed with `current²`, back via `sqrt` (γ≈2 stand-in). Blinking/bright things keep their light in the streak (long-exposure look). NR and sharpen branches untouched.
  - Idea 4 **noise-gated temporal coring (sharpen mode only):** `residual · smoothstep(nF, 2nF+0.002, rms(residual))`, `nF = noiseSigma + 0.004` (idea 2's estimator, no new taps). Noise a sensor adds to the boosted output −51 % (error 0.0373 → 0.0183); a clean moving scene keeps ~88 % of HEAD's transient boost (slow motion partly reads as noise — known cost).
- **Rescues:** (a) HEAD motion-blur diverges (meanL −3.59 / meanA −11.2 at p4=1.0, bass 2) — `mix` extrapolation past 1 + ring feedback; trail weight now `clamp(strength·0.8, 0, 0.95)` (not 1: weight 1 starves the live frame and an empty ring stays black). (b) `upgraded-rgba` removed from header `Features:` and JSON `features` (no ACES; passthrough, P-ACES a/c).
- **A packing:** display RGBA = writeTexture, unchanged.
- **Diff vs HEAD (clean moving scene, defaults except mode):** NR mode **0.00 %** (bit-identical); motion blur 18.4 % px (mean |Δ| 0.010, max 0.178); sharpen 19.0 % px (mean 0.0065, max 0.184). D=8/4/1, silence, bass 2: nan 0.
- **Timing:** @128 paired-median 0.57–1.05; @256 sharpen 1.11, MB 0.74 (noisy box). Negligible added maths.
- **Could not verify:** real-GPU look; NR path is unchanged so no new risk there.

## Gates (both files)
precommit 2/2 (naga OK, bindgroup OK, 0 extraBuffer violations, 0 pasted headers) · naga-wasm 2/2 valid · dead sliders 0 new (2 defs scanned) · extrabuffer audit PASS · saved `params` byte-exact (JSON diff = description text + 3d-conv features tag only).

## §12.2 rows used
None (both files used domain-native mechanisms): row-ownership list not touched.
