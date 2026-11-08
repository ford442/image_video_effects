SHADER: spec-distance-field-text (1st pass)
IDENTITY: grid of procedural SDF runes overlaid on the source, colour-cycling with glow, shadow and phosphor trails
KEEP VERBATIM: 4 rune SDFs, hashed grid, domain warp, mouse reveal, click ripples, trail feedback, params
RESCUES: runes drew at ~6% of their cell (pulse/gridScale applied twice) -> fill the cell; spectral pick read plasmaBuffer[1..4] (never written) -> bass/mids/treble/sqrt(bass*treble); A-rune upside-down (y-up glyphs on y-down uv)
ADD: 1. bevelled runes — central-difference SDF gradient + rounded ridge profile, lit from the cursor
     2. distance contour halos — iso-lines of d marching outward, period from Glow Radius, bass speeds/extends
     3. rune ignition — per-cell hashed schedule regrows the stroke from a hairline with a white-hot flash (mids rate)
FORBID: spring cursor, palettes, extra ripple layer
A PACKING: rgb = phosphor trail colour (read back through C), a = glyph SDF d (unchanged)
