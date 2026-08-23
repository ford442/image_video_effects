# Batch 59 — Cyber & Digital (2026-08-23)

Branch: `upgrade/batch-59-cyber-digital`  
Tracker: #501–510

## Summary

Ten cyber/digital shaders upgraded to the full 13-binding contract: ACES tone map,
semantic (unpremultiplied) alpha, `plasmaBuffer[0].xyz` + bins 1..8, held-pointer via
`zoom_config.w`, capped click ripples (`min(u32(u.config.y), 50u)`), exact
`textureLoad(dataTextureC)` on feedback paths, extraBuffer writes only in [133..138]
from pixel (0,0). B unused throughout.

## Validation

- `wgsl_precommit_gate.py` 10/10 (naga OK, bindgroup compatible)
- `audit:dead-sliders` PASS (0 new)
- `audit:extrabuffer` PASS (0 new)
- `audit:audio-mappings` 24/24
- `generate_shader_lists.js` clean
- Jest 84/84 (550 pass, 1 skip)
- `SKIP_WASM_BUILD=1 npm run build` green

## Shaders

| # | Shader | Lines (before→after) | Key changes |
|---|--------|----------------------|-------------|
| 501 | cyber-ripples | 212→215 | Capped ripple shockwaves, held tighten, FFT band shimmer on rings |
| 502 | cyber-scan | 234→250 | textureLoad C, ACES, semantic alpha, click scan bursts, held widen |
| 503 | cyber-trace | 187→139 | textureLoad C, ACES composite, semantic alpha, spring [133..138] |
| 504 | cyber-organic | 260→274 | Unpremult alpha, ripple pulses, held reveal, thin-film rim |
| 505 | cyber-rain | 205→177 | Removed extraBuffer[0..7]; spring [133..138]; EMP ripple loop; fixed config.y misuse |
| 506 | digital-glitch | 293→315 | 16×16, textureLoad C error mask, ripples, held, ACES |
| 507 | digital-haze | 198→189 | ACES, held clear radius, textureLoad C haze residue, semantic alpha |
| 508 | digital-reveal | 166→138 | textureLoad C, spring gated (0,0), ACES, held brush |
| 509 | edge-glow-mouse | 136→141 | C trail, ripples, held, mids/treble CA, FFT bands |
| 510 | ferrofluid | 142→123 | ACES, semantic alpha, mids/treble domain runners |
