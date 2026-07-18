# gen-ethereal-cyber-chrono-nebula-phoenix — Kimi retry notes (Batch 16, R3)

## What changed
- Full rewrite via Kimi retry (2026-07-18, quota restored): domain-warped FBM nebula, chrono-orbit strange-attractor glow, SDF phoenix silhouette.
- Audio: bass drives nebula brightness/warp strength, mids morph the attractor (`a` coefficient) and exposure, treble drives edge shell + sparkle.
- ACES tone map + IGN dither; semantic alpha = density + shell + chrono emission.
- Manual follow-up: converted final `writeTexture` store to premultiplied alpha (`color * alpha, alpha`).
- JSON def gained a `features` array (was missing).

## Validation
- `naga` OK; `wgsl_precommit_gate` OK.

## Params
- p1 = wingspan (0.05–0.5 clamp), p2 = plasma/chrono mix.
