SHADER: gen-neural-fractal
IDENTITY: Julia-style escape fractal where each iteration is a neural layer (sigmoid/tanh/swish activations cycling every 10 iterations), colored by twin orbit traps through OkLab/blackbody/cosine palettes.
KEEP VERBATIM: OkLab helpers, blackbody, cosinePalette, fresnelRim, activation fns, neuralLayer, domainWarp, multiTrapColor, twin orbit traps / sumZ structure / minZ detail, vignette, zoom/iteration/mutation mappings.
ADD (2 native ideas):
  1. Dendritic arborization: stalk trap (distance to the sigmoid midpoint / tanh zero axes) records the iteration of closest approach as branch order; branches only appear once an advancing growth cone (iteration front, pushed by clicks and mouse-hold) has passed them; trunk warm blackbody, tips cool, white growth-cone tip.
  2. Firing-rate glow: fraction of iterations whose activation saturates (|out|>0.9) marks "firing" neurons; they flicker with a treble-accelerated spike train in a cyan/magenta membrane glow.
FLOOR FIXES: bounds check; bass/mids/treble clamped from plasmaBuffer[0] (mids -> structure palette, treble -> spike train); Color Cycling (y) was a dead slider -> now scales palette drift (default 0.5 reproduces old rate); click ripples added as depolarizing stimulus waves (warp domain, boost mutation, advance growth cone); mouse-held strengthens domain pull and shifts juliaC; dataTextureA writeback added; alpha = activation density (trap glow + dendrite + firing) instead of luma; depth = escape-time depth instead of 0; header/uniform comments; JSON params + features.
FORBID: dataTextureB writes, extraBuffer use, plasmaBuffer[>0], generic noise/bloom overlays, replacing the neural-layer iteration.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (none used) / sliders x=zoom, y=color cycling, z=iteration depth, w=mutation live
