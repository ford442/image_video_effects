# Optimizer Notes: gen-fireworks-horse-tail

## Key Performance / Pipeline Changes

- **Hex-bokeh trailing glow** on brocade sparks for soft willow-like falloff.
- **Gravity-drag spark physics** with `sparkPos` and shared `GRAVITY` constant.
- **Temporal persistence** from `dataTextureC` blended into trailing tails.
- **Depth compositing** via depth texture read/write each frame.
- **dataTextureA** feedback for long golden tail persistence.
- **Mouse spawns personal horse-tail burst** at cursor on interaction.
- **Audio reactivity**: bass lengthens trails; treble brightens spark cores.
- Standardized fireworks helper toolkit (`hash2`, `softGlow`, `palette`, `acesToneMap`).

## Line Count Delta

- Original: ~104 lines
- Upgraded: ~170 lines
- Delta: +66 lines
