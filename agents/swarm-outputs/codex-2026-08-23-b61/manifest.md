# Batch 61 — Cyber / Digital / Glitch (2026-08-23)

Branch: `upgrade/batch-61-cyber-glitch`  
Tracker: #531–540

## Cohort

| # | Shader | Category | Key changes |
|---|--------|----------|-------------|
| 531 | spectral-glitch-sort | retro-glitch | Spring gated (0,0), A diagnostics, ACES, held |
| 532 | rgb-glitch-displacement | retro-glitch | textureLoad C, spring, ripples, ACES, A offset state |
| 533 | rgb-glitch-trail | retro-glitch | textureLoad C, 3-band audio, held/ripples, ACES |
| 534 | data-moshing | retro-glitch | textureLoad C, held/ripples, 3-band, ACES |
| 535 | data-moshing-diffusion | retro-glitch | ACES display, A packing clarified |
| 536 | digital-decay | retro-glitch | textureLoad ghost, mouse brush, held/ripples, ACES |
| 537 | vhs-tracking | retro-glitch | ACES, click row tears, semantic alpha |
| 538 | cyber-scan-gabor | advanced-hybrid | Full contract + JSON param names |
| 539 | data-stream-corruption-hdr | advanced-hybrid | textureLoad C, held brush, semantic alpha |
| 540 | pixel-sort-glitch | distortion | Spring epicenter, audio, ripples, ACES |

## Validation

- `wgsl_precommit_gate.py` 10/10 (naga OK, bindgroup compatible)
- `audit:dead-sliders` PASS (0 new)
- `audit:extrabuffer` PASS (0 new)
- Jest 87/87 (586 pass, 1 skip)
- `SKIP_WASM_BUILD=1 npm run build` green
