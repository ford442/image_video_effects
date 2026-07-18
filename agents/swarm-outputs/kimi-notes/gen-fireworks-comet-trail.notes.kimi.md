# gen-fireworks-comet-trail — Kimi retry notes (Batch 16, R4)

## What changed
- Full rewrite via Kimi retry (2026-07-18): 7 parallel comet shells with hex-bokeh glow, star-field backdrop, and treble-driven peel sparks + ring burst.
- Audio: bass scales launch rate/energy, treble adds peel-spark count and brightness; mids read but lightly used.
- Temporal: `dataTextureC` feedback for trail persistence (`prev*mix(0.88,0.95,trailLen)`), `dataTextureA/B` store persistent state.
- ACES + IGN dither; premultiplied alpha final write.
- JSON def gained `features` (was empty).

## Validation
- `naga` OK; `wgsl_precommit_gate` OK.

## Params
- p1 = speed, p2 = trail length, p3 = head brightness (bass-boosted), p4 = color shift.
