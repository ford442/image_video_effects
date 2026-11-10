# Fork D Idea Cards (written before WGSL edits)

SHADER: infinite-fractal-feedback
IDENTITY: perpetual polar zoom tunnel with 3-layer spiral sampling + kaleidoscope mandala, accumulative alpha feedback, mouse focal point.
KEEP VERBATIM: polar fract zoom, spiral twist, 3-layer loop, kaleido mix 0.6, accumulativeAlpha(), 4 param roles.
ADD:
  1. Recursive zoom echo — C is loaded (exact textureLoad) at the pixel pulled toward the focal point by a zoom-rate step, so history falls into the tunnel instead of being re-folded at sampleUV; that is the "infinite" in the name.
  2. Per-generation hue drift — each echo generation is hue-rotated by colorShift, so depth reads as a spectral spiral of copies.
  3. Mandala spoke seams — thin glow on the kaleidoscope segment boundaries (angle distance to segment edge), pulsed by treble.
FORBID: springs, IQ palette stamp, new modes.
A PACKING: display RGBA (accumulated), unchanged.
HEAD bugs: mouse divided by resolution (uv already) → focal stuck; u.zoom_config.x read as audio; ripples/clock rings in centered uv vs 0..1 ripple uv; filtered C sample; no ACES.

SHADER: interactive-pixel-wind-structure
IDENTITY: image pixels blown along structure-tensor orientation, mouse vortex, ripple turbulence, chromatic split, feedback trails.
KEEP VERBATIM: smoothTensor, eigenvector, vortex, ripple turbulence, chroma offsets, 4 params.
ADD:
  1. Coherence-gated wind — anisotropy (λ1-λ2)/(λ1+λ2) scales the push so flat areas sit still and edges/textures stream.
  2. Real LIC streaks — 6-tap line integral along the flow (header promises LIC, code had none), mixed by turbulence.
  3. Held-pointer gust — mouse down widens/strengthens the vortex and drags trails longer.
FORBID: ripple shockwave rings, palettes.
A PACKING: display RGBA.
HEAD bugs: filtered C sample (textureSampleLevel on dataTextureC); alpha passthrough → semantic.
