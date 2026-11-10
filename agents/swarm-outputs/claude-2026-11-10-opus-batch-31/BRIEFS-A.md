# opus/batch-31 — fork A Idea Cards (written before any idea edit to WGSL)

```
SHADER: color-channel-weave
IDENTITY: the photo rendered as a plain over-under woven cloth whose R/B channels ride offset warp/weft threads
KEEP VERBATIM: 4 params (thread spacing / weave angle / shadow depth / chroma offset) and their mappings; over-under cell parity;
  two-ply yarn twist; exact-C under-thread ghost; click "pluck"; warm warp / cool weft tint; display RGBA in A; B side-channel
ADD:
  1. Jacquard yarn-dye — each crossing cell takes the colour of the source at that cell's centre (the yarn is dyed, not
     printed), blended over the per-pixel sample, so the photo reads as woven picture cells.
  2. Slub yarn — per-thread hash varies each warp/weft yarn's thickness and dye lot (brightness), so threads are
     irregular like real spun yarn instead of a perfect grid.
RESCUE: extraBuffer[133..138] spring is dead (zeroed every frame) → raw mouse (same behaviour, no fake state);
  fftVoice read plasmaBuffer[1..8] which are never uploaded → real FFT bins extraBuffer[5..132].
FORBID: ripples-as-shockwave overlay, IQ palettes, new spring
A PACKING: ACES display RGBA (C read as display colour for the under-thread ghost); B = (warpBright, weftBright, bass, mid)
```

```
SHADER: chromatic-folds-gemini
IDENTITY: hue-gradient fold displacement + hue folding around a pivot, smeared by colour feedback, with a vortex
KEEP VERBATIM: 4 params (fold strength / pivot hue / sat scale / depth influence) and mappings; foldHue; 3-layer hue-gradient
  displacement; branch-cut hue jump; fold-zero darkening; click ripples; pre-ACES display RGB in A with C mix feedback
ADD:
  1. Prismatic fold dispersion — R, G, B are fetched at the displaced UV with 0.8× / 1× / 1.25× of the fold vector,
     so every fold splits colour fringes along its own displacement direction.
  2. Origami crease lighting — the fold displacement direction acts as a facet normal: faces tilted toward a fixed
     key light brighten, away faces shade, so folds read as creased paper.
RESCUE: zoom_config.x is TIME (noise amplitude grew without bound → frame scrambled to flat grey after minutes, stdL 0.031 @300s);
  feedback / ripple strength were read from mouse X / Y (zoom_config.y/z); vortex was centred on ripples[0] (= (0,0) when no click)
  so the advertised "mouse-driven vortex" never followed the mouse → vortex at the pointer, fixed noise/feedback/ripple constants;
  fractal layers 1–2 sampled uv*2 / uv*4 off-texture (clamped → zero gradient outside the top-left quadrant) → mirror-repeat.
FORBID: spring cursor, IQ palette, holographic overlays
A PACKING: pre-ACES display RGB + fold alpha (C is colour history) — unchanged
```

```
SHADER: contour-flow
IDENTITY: image contours advected along their tangents into coherent spectral history ribbons (LIC-style painting)
KEEP VERBATIM: 4 params (flow speed / curl / flow size / direction); fine+broad gradient tangent field; held-pointer vortex;
  click contour fronts projected on tangent; coherence-gated ribbon exponent; two-scale cross-hatch; linear pre-ACES A
ADD:
  1. Streamline integration (LIC smear) — the current-image injection is averaged over a short 4-tap walk along the
     tangent field, so freshly injected colour already lies along the contour instead of as a point sample.
  2. Contour iso-lines — luma quantised into level sets; the iso-line nearest each pixel is drawn as a thin dark ink
     line, so the field shows actual contour lines (the effect's name) that flow carries along.
NOTE: meanL 0 at HEAD was a harness artefact (black input texture); with an image input HEAD renders meanL 0.48.
FORBID: replacing the advection, new palette family, springs
A PACKING: linear pre-ACES painting RGBA (exact-C advection history); ACES on display only — unchanged
```
