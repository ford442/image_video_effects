# ripple-blocks-v2.0 — Kimi notes

- **Surprising behavior**: Golden-ratio detuned interference (sin(f) + sin(f*φ)) creates organic beating patterns that feel alive under music. The domain warp tears the rigid grid into flowing tissue.
- **Audio reactivity**: Bass inflates global env (cell scale pulse), mids shift color temperature (warm→cool), treble triggers hash-based sparkles on cell edges.
- **Alpha semantics**: `alpha = select(0.1, 0.85 + abs(scaleMod)*0.15, inBounds) * (1.0 - depth*0.3)` — background cells are translucent ghosts, foreground cells are opaque metal, depth fades distant cells.
- **Performance**: 3 texture samples, ~6 noise evaluations, uniform branch on warpAmt. Should maintain 60fps@1080p.
