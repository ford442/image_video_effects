# Shader notes

- `gen-crystal-lattice-growth`: added exact HDR history, secondary crystallisation fronts from click timestamps, single-pass ACES, and raw-A / mapped-display separation.
- `gen-crystalline-chrono-dyson`: replaced four filtered C samples with clamped integer dispersion loads, added ACES, generated hit depth, semantic coverage, and quasar click fronts.
- `gen-crystalline-mandala-bloom`: retained the mouse-anchored polar fold while adding exact temporal bloom, expanding crystal rings, and raw HDR A history.
- `gen-crystalline-nebula-weaver-void-spider`: added the missing bounds guard, centered aspect-correct mouse field, full three-band nebula response, exact C feedback, semantic alpha, and display RGBA in A instead of diagnostics.
- `gen-cyber-organic-liquid-neon-pulsar`: preserved the biomechanical raymarch and magnetic mouse warp; mids and treble now affect spectral emission, clicks excite field rings, feedback stays exact, and ray distance supplies depth.
- `gen-cyber-terminal`: made all four advertised sliders live through grid density, procedural glyph sharpness, phosphor brightness, and scanline bloom; added three-band tint/detail, exact phosphor history, ACES, alpha, and emission depth.
- `gen-cybernetic-aether-moth-chrysalis`: removed the filtered C-as-audio shortcut, routed three-band audio into core/shell/fibers, restored A feedback and depth output, and added timestamped chrysalis flares.
- `gen-cybernetic-crystalline-neuro-lattice`: removed ripple-age-as-audio, routed real three-band audio through gyroid/node detail, preserved held-pointer bending, and added exact temporal links, ACES, semantic alpha, click waves, A history, and depth.
- `gen-cybernetic-ferro-coral`: preserved the Batch 36 domain-warped FBM, Turing bands, ripple spikes, and temporal packing while replacing legacy extra-buffer FFT reads with the required regional three-band envelope.
- `gen-cybernetic-liquid-chrome-engine`: preserved the conveyor camera, piston surge, liquid-chrome smear, and mouse orbit; click impulses now kick the conveyor and ring the housing without changing its established A/C packing.

All definitions now expose four named `params` aligned to their live x/y/z/w controls. The void-spider definition's prior `updatedParams` order was corrected from `Void/Web/Gravity/Plasma` to the shader's actual `Web/Gravity/Plasma/Void` mapping.
