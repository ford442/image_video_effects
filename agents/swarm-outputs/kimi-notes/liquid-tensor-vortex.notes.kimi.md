# liquid-tensor-vortex — Kimi notes

- **Surprising behavior**: Chromatic aberration tear on mouse vortex (RGB channels split by flow direction) creates a genuinely torn-metal look unlike any existing liquid shader.
- **Audio reactivity**: Bass inflates bubble radius and env-glow flash; mids shift the silver→gold→bronze palette mix in real time.
- **Alpha semantics**: `alpha = mix(0.2, 0.95, folds) * (1.0 - depth * 0.6) * (1.0 - vortex * 0.4)` — folds are opaque metal, deep background is translucent, vortex tears are partially see-through.
