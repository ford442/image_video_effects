# cyber-rain — Interactivist upgrade notes

- **What changed:** Added a bass audio envelope that modulates fall speed and intensity, temporal wetness accumulation via `dataTextureC`/`dataTextureA`, depth-aware rain occlusion/fog, chromatic aberration driven by depth and bass, and ACES tone mapping. The JSON adds `upgraded-rgba`, `audio-reactive`, `temporal-persistence`, and `depth-aware`.
- **Why:** Rain now reacts rhythmically to audio and leaves wet trails, while depth-aware fog keeps foreground subjects readable in chained slots.
- **Performance concern:** Five-tap vertical blur plus three extra texture samples for chromatic aberration and base; still moderate, but mobile GPUs may feel the extra samples. The hash-based rain remains cheap.
