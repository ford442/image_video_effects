# Batch 61 coordinator review — 2026-08-23

Status: **STRUCTURALLY CLOSED** on tracker #531–540.

## Critical fixes

- **spectral-glitch-sort:** Gated spring `extraBuffer[133..136]` to `(0,0)`; A no longer stores display duplicate.
- **rgb-glitch-displacement / rgb-glitch-trail / data-moshing / digital-decay / data-stream-corruption-hdr:** Replaced filtered `textureSampleLevel(dataTextureC)` with exact `textureLoad`.
- **cyber-scan-gabor:** Full contract from scratch — A write, spring scan-head, audio, held, ripples, ACES; fixed naga (`var processed`, `f32` literals).
- **pixel-sort-glitch:** Fixed naga bool×float in held window mix; added spring epicenter, audio, ripples, ACES.
- **data-moshing-diffusion:** Separated A packing (offset.xy, smearEnergy.z, persistence.w); ACES display only.
- **JSON:** `cyber-scan-gabor` params renamed (`scanWidth`, `gridIntensity`, `colorSpeed`, `gaborFreq`); defaults preserved at 0.5.

## Feedback ownership

| Shader | A packing | Notes |
|--------|-----------|-------|
| spectral-glitch-sort | dispFactor, tearBoost, aberScale, sortEnergy | Spring [133..136] @ (0,0) |
| rgb-glitch-displacement | offset.xy, glitchEnergy | textureLoad C offset history |
| rgb-glitch-trail | intensity, trailHue.rg, persistence | textureLoad C |
| data-moshing | offset.xy | textureLoad C |
| data-moshing-diffusion | offset.xy, smearEnergy, persistence | textureLoad C |
| digital-decay | ghost rgb + corruptionAge | textureLoad C |
| vhs-tracking | row walk, dropout, phase, headBand | textureLoad C row state |
| cyber-scan-gabor | gaborMag, scanPhase, edgeEnergy, trailAlpha | Spring Y [133,135] @ (0,0) |
| data-stream-corruption-hdr | corruption, exposureHistory | textureLoad C |
| pixel-sort-glitch | edgeDir packed, edgeMag, mask | Spring [133..136] @ (0,0) |

B unused throughout. extraBuffer only spectral-glitch-sort, pixel-sort-glitch, cyber-scan-gabor — all `[133..]`, `(0,0)` writer.

## Validation

Gate 10/10; dead-slider / extraBuffer audits PASS (0 new); params exact 10/10; Jest 87/87 (586 pass, 1 skip); `SKIP_WASM_BUILD=1 npm run build` green. Real-GPU visual QA remains external (Cloud VM has no GPU adapter).
