# gen-fireworks-crossette — Kimi retry notes (Batch 16, R6)

## What changed
- Full rewrite via Kimi retry (2026-07-18): rising shell → central flash → 16-spark peony ring → 4-arm crossette split with per-arm sub-sparks.
- Audio: bass scales energy and accelerates arm split (`splitWait * (1 - bass*0.35)`), mids modulates split delay, treble brightens sub-sparks.
- Temporal: `dataTextureC` feedback (`prev*0.925`); A/B store persistent state.
- ACES + centered IGN dither; premultiplied alpha final write.
- JSON def already had correct `features` — left as-is.

## Validation
- `naga` OK; `wgsl_precommit_gate` OK.

## Params
- p1 = power, p2 = split delay, p3 = arm spread, p4 = hue shift.
