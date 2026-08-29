# Batch 60 — Heat / Echo / Elastic / Electric (2026-08-23)

Branch: `upgrade/batch-60-heat-echo-elastic`  
Tracker: #521–530

## Summary

Ten shaders upgraded to the full cohort contract: ACES tone map, semantic
alpha, `plasmaBuffer[0].xyz` + bins 1..8 where useful, held-pointer via
`zoom_config.w`, capped click ripples (`min(u32(u.config.y), 50u)`), exact
`textureLoad(dataTextureC)` on feedback paths, extraBuffer writes only in
`[133..]` from pixel `(0,0)`. B unused throughout. `edge-glow-mouse` is a
deliberate second polish after Batch 59.

## Validation

- `wgsl_precommit_gate.py` 10/10 (naga OK, bindgroup compatible)
- `audit:dead-sliders` PASS (0 new) — focused 10 ids
- `audit:extrabuffer` PASS (0 new)
- `audit:audio-mappings` 24/24
- Params / `updatedParams` exact 10/10
- `generate_shader_lists.js` clean
- Jest 85/85 (570 pass, 1 skip)
- `SKIP_WASM_BUILD=1 npm run build` — see COORDINATOR_REVIEW

## Shaders

| # | Shader | Lines | Key changes |
|---|--------|-------|-------------|
| 521 | heat-haze | 144→160 | Dual-octave convection, hotter runners, Schlieren CA, held nozzle, FFT shimmer, ACES |
| 522 | heat-haze-mirage | 240→209 | Stronger TIR fold, amber caustics, held press, spring [133..137] kept |
| 523 | echo-ripple | 203→206 | Ripple cap 12→50, thin-film harmonics, held gravity bowl |
| 524 | echo-trace | 154→220 | **Kalman [0..8]→[133..141]**; exact C; held brush; click pulses; ACES |
| 525 | edge-glow-mouse | 141→187 | 2nd polish: oil-slick neon, tangent packets, ring clicks |
| 526 | elastic-strip | 161→192 | Nested bevel ribs, dual pluck packets, soap-film, held punch |
| 527 | elastic-surface | 171→204 | **textureLoad C** RG/BA state; caustic lighting; audio; ACES display |
| 528 | electric-contours | 150→198 | Click charge sparks, held boost, corona, A=field diagnostics |
| 529 | ember-drift-dissolve | 166→196 | **textureLoad C** advection; held furnace; ACES display |
| 530 | energy-shield | 161→186 | Cap 50; exact C trail; held hex tighten; oil-slick; ACES |
