# opus/batch-31 — fork A notes (color-channel-weave, chromatic-folds-gemini, contour-flow)

Measurement: `minirender_img.mjs` with `SRC=img` (synthetic sinusoid + two discs test image), 256², JSON default params.
Δ% = share of pixels whose max |ΔRGB| > 0.02 between the file and the same file with that idea switched off.
Timing: 512², 40 frames, SwiftShader (noisy), HEAD vs new.
NOTE: the plain `minirender.mjs` never uploads an input image (readTexture is black) — that is why contour-flow
showed meanL 0. With an image HEAD renders meanL 0.48. Not a shader bug.

## color-channel-weave — Upgraded 2026-11-10
- Kept verbatim: 4 params + mappings, over-under parity, two-ply twist, exact-C ghost, pluck, warm/cool tint, B side-channel.
- A packing: ACES display RGBA (unchanged).
- Idea 3 Jacquard yarn-dye (cell-centre colour, channel-offset fringe kept): Δ 9.0 % @ default spacing 0.25, 29.6 % @ spacing 0.
- Idea 4 slub yarn (per-yarn thickness + dye lot, mean ≈1.05): Δ 69 %.
- Rescues: dead extraBuffer[133..138] spring removed (it always fell back to the raw pointer — same behaviour, no fake state);
  `fftVoice` read plasmaBuffer[1..8] (never uploaded → 0) → extraBuffer[5..132] FFT bins.
- Timing: 52–57 ms vs HEAD 65–141 ms (≈1.0×, noise-dominated).

## chromatic-folds-gemini — Upgraded 2026-11-10
- Kept verbatim: 4 params + mappings, foldHue, 3-octave hue-gradient displacement, branch cut, fold-zero darkening (re-thresholded),
  ripples, C feedback mix.
- A packing: pre-ACES display RGB + fold alpha (unchanged).
- Idea 3 prismatic fold dispersion (R/B at ∓ prism width along the fold-only direction): Δ 12.9 %.
- Idea 4 origami crease lighting (fold direction · key light, ±55 %): Δ 43.5 %.
- Rescues:
  - `zoom_config.x` is time → noise amplitude grew unbounded (HEAD @ t=300 s: stdL 0.031, flat grey). Now fixed 0.0015 (new @300 s stdL 0.153).
  - feedback / ripple strength were read from mouse X / Y → fixed 0.875 / 0.0025 (mid of HEAD's ranges).
  - vortex centred on ripples[0] (= (0,0) with no click) → under the pointer (the advertised mouse-driven vortex).
  - octaves 1–2 sampled uv·2 / uv·4 off-texture (zero gradient outside the top-left) → mirror-repeat (octave 0 unchanged).
  - fold-zero darkening: 0.02 threshold only cleared while the runaway noise inflated foldMag, so with sane noise it dimmed
    ~70 % of the frame by 0.7 (HEAD meanL 0.22 at t=2 s, falling). Now measured on the fold-only vector, threshold 0.0015, cap 0.4
    → meanL 0.35.
- JSON: features += `upgraded-rgba` (ACES + implemented cards). Saved params untouched.
- Timing: 67–68 ms vs HEAD 56–57 ms (≈1.2×).

## contour-flow — Upgraded 2026-11-10
- Kept verbatim: 4 params, fine/broad tangent field, held vortex, tangent-projected click fronts, coherence-gated exponent,
  two-scale cross-hatch, linear pre-ACES A.
- A packing: linear pre-ACES painting RGBA, ACES display only (unchanged).
- Idea 4 streamline (LIC) injection, 7 taps along the tangent: Δ 52.7 % (feedback amplifies; visually a softer, contour-aligned grain).
- Idea 5 luma iso-line ink contours (3+4·flowSize levels, ~1-texel width via slope division, display + alpha only): Δ 16.8 %.
- Rescues: none (HEAD fine; the meanL-0 report was the black-input harness).
- Timing: 111 ms vs HEAD 108 ms (≈1.03×).

Gates (all three): wgsl_precommit_gate 3/3, verify-naga-wasm --files OK ×3, dead-sliders 0 (3 defs scanned), audit:extrabuffer PASS.
Real-GPU visual QA: external.
