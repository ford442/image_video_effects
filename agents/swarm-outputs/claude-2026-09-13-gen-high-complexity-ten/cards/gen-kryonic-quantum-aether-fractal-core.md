# Idea Card — gen-kryonic-quantum-aether-fractal-core

```
SHADER: gen-kryonic-quantum-aether-fractal-core
IDENTITY: a glacial-blue raymarched fold-and-scale (sorted abs-fold) fractal core slowly tumbling in a black void,
  wrapped in volumetric blue/magenta aether fog; pointer yaws the view and locally melts the core into a smooth sphere.
KEEP VERBATIM: fold() sorted-abs mirror, 5-iteration scale/offset/rotate map(), audio noise shatter offset,
  smin melt sphere under the pointer, 80-step half-step volumetric march + glow accumulation, calcNormal,
  dif/spec/fresnel/chromatic-edge shading, void fog mix, treble tint, t/10 depth, slider roles
  (x Fractal Scale, y Shatter Intensity, z Glow Strength, w Thermal Melt).
EXISTING IDEAS: none named (2026-06-07 pass was header/audio hygiene; no ACES despite the tag).
ADD:
  1. Frost-rime orbit trap — the fold loop's minimum orbit radius is re-evaluated once at the hit point and
     paints icy white rime on the most tightly folded crystal tips, deepening to glacial blue in the recesses;
     native because it is the fractal's own iteration data turned into "hyper-frozen" surface frost.
  2. Aether shatter veins — the minimum distance to the fold's mirror planes (|x-y|, |x-z|, |y-z|, where the
     sorted-abs fold stitches its shards together) becomes thin cyan→magenta plasma cracks, width and brightness
     driven by Shatter Intensity and treble, thawed out inside the pointer melt; native because the description's
     "shatter into luminous aether-plasma shards" happens exactly along these fold seams.
FLOOR: ACES on display RGB (tag claimed it, file lacked it); melt `if` → select with a safe smin k.
FORBID: spring cursor, click ripples, IQ cosine palette, a different fractal (Mandelbox/Menger swap), conveyors, dataTextureB.
A PACKING: ACES display RGBA (C not read; A is display history for the engine).
```
