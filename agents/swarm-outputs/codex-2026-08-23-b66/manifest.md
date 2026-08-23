# Batch 66 — Cyber Glitch & Data FX (2026-08-23)

Branch: `cursor/batch-66-cyber-glitch-21c9`  
Tracker: #521–530

## Summary

Ten cyber/glitch/data shaders upgraded with **fp128 base+mantissa** extended-precision
math (Knuth two-sum / Dekker expansion), **two shader-specific fast-motion families**
each (closed-form racing packets + history-advected smear via exact `textureLoad`
from `dataTextureC`), full 13-binding contract (ACES, semantic alpha,
`plasmaBuffer[0].xyz` + bins 1..8, held-pointer via `zoom_config.w`, capped click
ripples `min(u32(u.config.y), 50u)`, `@workgroup_size(16, 16, 1)`, bounds guard).
`extraBuffer` writes confined to `[133..138]` from pixel `(0,0)` only.

## Validation

- `wgsl_precommit_gate.py` 10/10 (bindgroup compatible; naga skipped on VM)
- `audit:dead-sliders` PASS (0 new)
- `audit:extrabuffer` PASS (0 new)
- `audit:audio-mappings` 24/24
- `generate_shader_lists.js` clean
- Jest 84/84 (559 pass, 1 skip)
- `SKIP_WASM_BUILD=1 npm run build` green

## Shaders

| # | Shader | Key changes |
|---|--------|-------------|
| 521 | `cyber-glitch-hologram` | fp128 fringe phase + UV advection; racing scan carrier; C smear; clicks/held |
| 522 | `cyber-physical-portal` | fp128 Kerr spin integration; rim runners; throat C smear; click EMP |
| 523 | `data-scanner` | fp128 triple scan fronts; vertical packet; 8×8→16×16; C smear; ACES |
| 524 | `data-slicer` | fp128 slice phase; horizontal packet; continuous jitter; C smear |
| 525 | `data-stream` | fp128 strip flow; per-strip head packets; spring [133..138]; C trails |
| 526 | `digital-moss` | fp128 growth rate; wired sliders; scan pulses; spring brush; exact C CA |
| 527 | `glitch-cathedral` | fp128 DCT phase; rose-window pulse; click fractures; held quant |
| 528 | `glitch-pixel-sort` | fp128 sort displacement; exact C melt; streak packets; filtered C fix |
| 529 | `glitch-slice-mirror` | fp128 seam; fracture packet; C smear at seam |
| 530 | `scanline-cyberpunk` | fp128 glitch offset; phosphor runner; depth clobber fixed; ACES |
