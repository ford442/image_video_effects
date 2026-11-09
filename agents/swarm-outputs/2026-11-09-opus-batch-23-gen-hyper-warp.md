# gen-hyper-warp — opus/batch-23 (3rd pass)
Keep: fBm domain warp, flow-advected prismatic feedback, etched isolines, palettes, saved params.
- reaction rims: |luma(fresh) - luma(history)| marks where the feedback is still reacting; a thin color2 rim glows there (bass thickens it, Detail scales it). Display-only — kept out of A so the loop can't accumulate it.
- flow-compass hue: palette phase += atan2(r - 0.5)/TAU (full period, seamless at the wrap), so each current carries its own hue band.
HEAD bug: none found.
