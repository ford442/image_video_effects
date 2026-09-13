SHADER: gen-hyper-warp
IDENTITY: two-layer fBm domain warp (q -> r -> val) mapped through two cosine palettes, with a centered radial burst and a stabilized, flow-advected sharpen feedback loop.
KEEP VERBATIM: rand/noise/fbm kernel and octave counts; q/r/val warp chain; two palettes + smoothstep(0.4,0.6) blend; radial burst; stabilizeHistory + cold-start seed; opacity 0.85 blend, CA, vignette; slider roles (Intensity=warp amp, Speed=time mult, Scale=palette freq/hue, Detail=feedback mix); saved params.
EXISTING IDEAS (2026-09-06):
  1. first-warp fold caustics (mid-range |q-0.5| band brightens)
  2. second-layer flow stretch (|r-q| shear adds mid-palette glow)
ADD:
  3. Warped level-set etching — thin anti-aliased isolines of final_val (count follows Scale) darken/brighten as contour engraving; native because the level sets of the warped fBm scalar are the literal structure the warp chain bends.
  4. Flow-dispersed feedback — the flow-advected history is loaded per channel with red lagging and blue leading the green tap along the flow direction (spread grows with flow speed and bass), so the reaction-diffusion echo splits into prismatic trails along the warp flow; native because it extends the existing flow-advected C read rather than adding a new field.
FORBID: spring cursor, click ripple shockwaves, new IQ palette, conveyors, replacing fBm with another fractal, touching dataTextureB/extraBuffer.
A PACKING: raw HDR history RGBA (unchanged): A.rgb = pre-ACES chromatic, vignetted color clamped [0,6]; A.a = coverage alpha. C read with exact textureLoad as rgb history.

## Notes
- Kept verbatim: rand/noise/fbm kernel + octave counts, q -> r -> val chain, both palettes and blend, radial burst, Ideas 1-2, stabilizeHistory + cold-start seed, opacity/CA/vignette, slider roles, saved params (JSON params byte-exact; only description refreshed).
- A packing: unchanged raw HDR history RGBA (A.rgb = pre-ACES chromatic vignetted color clamped [0,6], A.a = coverage). C read via exact textureLoad only; no textureStore(dataTextureC).
- Idea 3 (warped level-set etching): public/shaders/gen_hyper_warp.wgsl ~L205-215, after Idea 2. Scale -> isoline count, Intensity -> etch depth, stretch -> line width, fold/mid -> lip highlight.
- Idea 4 (flow-dispersed feedback): ~L169-182, per-channel exact loads at flowVec -/+ flowDir * dispersePx (flow speed + bass widen). Card draft said 0.7x/1.3x scaling; changed to an additive pixel offset because scaling a 1-4px flow rounds away to nothing.
- Floor fixes: removed duplicate `Upgraded:` lines (single 2026-09-13); renamed noise() local `u` that shadowed the uniform; guarded aspect division with max(resolution.y, 1.0). Audio already plasmaBuffer[0].xyz; alpha already semantic; ACES on display only; all 4 sliders live.
- Gates: naga "Validation successful"; wgsl_precommit_gate --files: 1/1 passed, 0 extraBuffer violations. No GPU visual QA.
