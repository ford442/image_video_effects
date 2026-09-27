SHADER: gen-aurora-borealis-synthesis
IDENTITY (one sentence): a chromatic-split, 20-step fbm volume march of aurora light added onto the input image, drifting with a swirl speed and steered by the mouse as a storm direction.
KEEP VERBATIM: the 20-step `fbm` march along `ray_dir` (step_size = volume_height/steps); the R/G/B split (R sampled with treble, G with mids, B with bass) and the smoothstep(0.4,0.8) thresholds; `fade = 1 - i/steps`; storm-direction mouse in `motion_offset`; `applyGenerativePrimaryControls` tail; temporal persistence mix; saved params byte-exact (x = volume height / Intensity, y = swirl / Speed, z = brightness / Scale, w = Mouse Influence).
ADD (native ideas):
  1. Altitude emission layers — the march step doubles as altitude: 557 nm green base band, 630 nm red upper fringe (boosted to survive the depth fade), blue-magenta lower edge. Replaces the dead plasmaBuffer LUT. The R/G/B split multiplies the palette channelwise, so the chromatic wavelength split is still there.
  2. Curtain pleats — sheared, vertically stretched fbm sampling (x folded by a slow sine of y, y compressed to 0.3, plus a per-altitude y parallax lift scaled by the volume-height slider) plus a fine vertical ray modulation. Higher layers see a shifted noise slice, so the colour layers separate vertically instead of stacking into one hue, and the volume reads as rayed curtains instead of cloud.
  3. Click substorm arcs — each click (age = time - ripple.z, capped by u.config.y and a 4 s life) launches an east-west brightening arc that rises poleward (screen up), with a sharp lower edge and a diffuse upper edge, coloured by the same altitude palette (magenta below the front, green at it, red above), widening as it ages.
FORBID on this file: spring/extraBuffer state, IQ palettes, radial shockwave rings (the arc is a horizontal curtain front, not a ring), sibling ideas from gen-aurora-silk (satin sheen, warp-thread striations, fold occlusion).
A PACKING: aurora-glow layer in A, base image EXCLUDED. A.rgb = linear pre-ACES aurora emission (after ripples), A.a = march coverage. C is read back as this same glow (color history). Deviation from "display RGBA": writing the ACES/base-composited display value would re-feed the source photo into the trail every frame; the glow layer is the honest colour history. writeTexture is still the ACES display composite.

SILENT BUGS FIXED (disclosed):
  a. Colour was read from plasmaBuffer[color_index] (index up to 127) but only plasmaBuffer[0] is ever uploaded, so the aurora colour was ~zero and the effect showed almost only the base image. Replaced by the procedural altitude palette (idea 1).
  b. Ripple loop scaled by ripple.w (always 0) and treated ripple.z (start time) as a radius, so clicks did nothing. Rewritten as age = time - ripple.z, loop bounded by u.config.y (idea 3).
  c. textureSampleLevel with a filtering sampler on rgba32float C replaced by exact textureLoad.
  d. Feedback fed `base_color + aurora` back through A, so the source image was baked into the trail (base added ~1.08x steady-state). A now holds the aurora only.
  e. The march also barely varied in z (total z travel 0.5 vs xy range 10), so every step saw nearly the same noise; the pleat parallax lift gives each altitude a distinct slice.
Mouse Influence (w) at default 0.5 additionally scales the storm-direction drift (factor w*2 = 1.0 at default, so the drift is unchanged there).

DEFAULT LOOK CHANGES A LOT: from almost-only-the-source-image to a real green/red/magenta layered aurora over the image. This is the fix for bug (a), not a regression. No GPU here, so none of this is visually verified.
