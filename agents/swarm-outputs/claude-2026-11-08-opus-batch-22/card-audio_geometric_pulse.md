SHADER: audio_geometric_pulse (1st pass)
IDENTITY: neon kaleidoscope of nested morphing circle/hex/triangle SDFs pulsing to bass, FFT rings, click hex rings
KEEP VERBATIM: param ids/mapping, kaleidoscope fold, shape-morph mix, central pulse wave, click rings
ADD:
  1. Receding echo tunnel — C re-sampled zoomed toward the pattern centre; each pulse leaves shrinking ghosts (bass deepens)
  2. Lattice nodes — white-hot flares where neighbouring shape edges cross (mids feed them)
  3. Bevelled gem facets — SDF gradient on filled shapes lit by a slowly orbiting light
RESCUES:
  - neonGlow(dist) ignored SDF sign → every shape rendered as a solid fill; now |dist| line + soft halo (neon look restored)
  - edge width 0.003 was sub-pixel → pixel-scaled
  - extraBuffer[133..136] spring never persisted + only invocation 0 read it → mouse dead; now direct cursor
  - band rings read plasmaBuffer[1..5] (never uploaded) → bass/mids/treble spread over 5 rings
  - depth write was length(colour) → source depth passthrough
Stats (384px, 20f, t=3): defaults meanL .335 solid star → .186 legible neon lines; audio .505 wash → .282.
