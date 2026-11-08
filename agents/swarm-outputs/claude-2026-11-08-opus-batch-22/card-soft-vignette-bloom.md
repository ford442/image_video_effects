SHADER: soft-vignette-bloom (1st pass under batch standard)
IDENTITY: cinematic lens post — bloom pyramid, anamorphic streak, flare/starburst, hex bokeh, superellipse vignette
KEEP VERBATIM: pyramid/streak/flare/starburst/vignette/haze/split-tone/CA/grain chain, params
ADD:
  1. Cursor rack-focus — focal plane = depth sampled under the cursor (was fixed 0.5)
  2. Film halation — wide 8-tap red-orange fringe around highlights, suppressed on the highlight itself; bass lifts it
  3. Lens dirt — static smudges + specks visible only where bloom energy / flare light passes
RESCUES:
  - Bokeh weighted taps by hex SDF measured from the CURSOR → weight 0 away from mouse → frame black wherever depth≠focus. Aperture shape now from tap offset; base weight so dark areas never zero.
  - Bloom radius max(r*scale,1) ≈ 1 px at default → slider dead; now 1+4·r·scale px.
  - Output premultiplied by alpha≈0.3 on non-bloom pixels → frame dimmed to a third. Straight colour, alpha = max(src α, bloom×vignette).
  - dataTextureA never written; now mirrors output.
Stats (256px, 20f, t=3, defaults, harness depth=0): before meanL .130 meanA .42 → after .258 / 1.0; bass=1: .261 → .295; max sliders .085 → .144.
Open: harness depth is flat 0 so rack-focus/bokeh only checked for not-black; real-depth look unverified.
