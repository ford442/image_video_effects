# Grok 4.7 — ASCII / glyph / digital-rain twelve (cursor/batch-29)

Written before WGSL edits. Second pass where a file already named ideas: the new pair is additive and uses nouns already in that file. No new spring. No shared IQ palette, ripple stamp, or white-hot leader copied onto a file that does not already have one.

Formula cap: no §12.2 row on this batch. The ideas are device artifacts of the terminal cell, the LCD well, the Bayer tile, the wiper, and the rain column. Citing a shared formula would turn those into one overlay.

```
SHADER: ascii-decode
IDENTITY: the photo as a seven-glyph matrix; the pointer is a round lens that shows the photo inside and the matrix outside.
KEEP VERBATIM: Grid Size / Decode Radius / Matrix Speed / Effect Strength; character() indices 0–6 (empty, dot, plus, slash, X, box, solid); luma quantized to that index; decodeMask smoothstep; strength mixes back to the photo
MECHANISM INTERROGATION:
  tactic 2: a terminal cell has a margin, and a column highlight falls instead of lighting the whole column.
  tactic 3: decodeMask is a soft edge and is only used as a linear mix. The mid-value of that edge is thrown away.
  tactic 6: C is unread. Last frame's green is the phosphor a matrix column would leave.
ADD:
  1. falling column head — the existing column hash still decides which columns rain; the highlight is a short run of cells falling down that column. Matrix Speed still owns the rate
  2. cell gutter — a dark margin at the cell edge so the seven shapes sit in a terminal cell
  3. decode rim — where decodeMask is mid-range, the glyph is inked onto the photo instead of a linear dissolve
FORBID: a spring, click rings, a second green palette, a segment font (gen-cyber-terminal owns that)
A PACKING: ACES display RGBA. C is last frame's display, read only to hold a little matrix green on the encoded side
```

```
SHADER: ascii-flow
IDENTITY: eight procedural glyphs swept by a flow field, with a pointer repel, a held vortex, and a typed-cell wake.
KEEP VERBATIM: Intensity / Speed / Scale / Detail; hash flow; repel and held vortex; click fronts; ink-coverage ramp; coverage-weighted blend; typed-cell wake; exact C residue
MECHANISM INTERROGATION:
  tactic 7: flow is a vector. The glyphs are still drawn in axis-aligned cell space.
  tactic 3: the upstream sample is one tap. Flow length is computed and only used to push that one offset.
ADD:
  1. flow lean — the cell UV shears along the flow vector before draw_glyph, so stems lean downstream. Intensity still scales how hard the field pushes
  2. upstream streak — a second sample further upstream mixes in by flow length, so fast cells smear. The near tap stays
FORBID: a new spring, another wake term, another cosine palette
A PACKING: ACES display RGBA (unchanged; C is colour history)
```

```
SHADER: ascii-glyph
IDENTITY: photo luminance picks cross or dot glyphs in a cell grid, with a sprung lens that refines type under the pointer.
KEEP VERBATIM: Glyph Size / Brightness / Color Amount / Density Boost; bass_env cell size; spring lens in extraBuffer[133..136]; click scramble; bass character swap; cross-or-dot SDF; phosphor smear on index change; CRT scanline
MECHANISM INTERROGATION:
  tactic 4: Brightness is a global ink scale. The spatial version of "how much glyph" is stroke weight, and luma is already computed for density.
  tactic 3: lensDist and lensRadius exist only to build lensBoost. The rim of that lens is invisible.
ADD:
  1. stroke weight from luma — bright cells get a thicker cross or dot. Density Boost still decides whether a glyph exists; Brightness still scales the ink
  2. lens bezel — a dark ring at the existing lens radius, so the finer type sits in a window
FORBID: a second phosphor smear, a new scanline, moving the spring
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: gen-cyber-terminal
IDENTITY: falling segment-glyph rain on a curved CRT, with a white-hot leader, column gaps, a bottom restart flash, and phosphor history.
KEEP VERBATIM: Grid Density / Glyph Sharpness / Character Brightness / Scanline Bloom; 3×5 segment font; leader bit; column gaps; wrap flash; CRT bulge; raw HDR history in A
MECHANISM INTERROGATION:
  tactic 2: a curved CRT bows its scanlines with the glass, and the corners misconverge.
  tactic 3: the bulge is applied to the rain UV and then ignored by the scanline, which still uses the flat frame.
ADD:
  1. barrel scanlines — the scan mask uses the curved uv so the lines bow with the glass. Scanline Bloom still scales the bloom
  2. corner misconvergence — red and blue glyph taps shift apart by the existing bulge, so corners fringe and the centre stays registered
FORBID: a new leader colour, a spring, a second rain sheet
A PACKING: raw HDR display RGBA history in A (unchanged). ACES on writeTexture only
```

```
SHADER: matrix-curtain
IDENTITY: a vertical curtain of matrix glyphs centred on the pointer, with a hashed birth, a bright head band, a ghost, and phosphor dragged from the pixel above.
KEEP VERBATIM: Rain Speed / Column Density / Curtain Width / Phosphor Glow; column hash and noise velocity; gol_state birth; scan at fall 0.12 and ghost at 0.35; phosphor from C one pixel up; click fronts; held vortex; A stores brightness, curtain, glyph, alpha
MECHANISM INTERROGATION:
  tactic 2: a rain head is a full glyph and the tail thins to a stem. A curtain has a hem at its edge.
  tactic 3: glyphStroke is a full cross at every fall. curtainMask's edge is only a smoothstep.
ADD:
  1. tail stem — near the scan head the cross stays; farther down the trail only the vertical stem remains
  2. curtain hem — a bright thread where curtainMask is mid, so the band has an edge. Curtain Width still sets where that edge sits
FORBID: a spring, a segment font, rewriting gol_state into a real cellular automaton, ACES on the stored fields
A PACKING: raw fields in A (brightness, curtainMask, glyph, alpha). C is that packing. ACES on writeTexture only
```

```
SHADER: pixel-rain
IDENTITY: the photo scrolls in green-tinted columns with three parallax rain sheets, a glitch kick, and a trail from last frame.
KEEP VERBATIM: Rain Speed / Glitch / Density / Trail Fade; spring in extraBuffer[133..138]; three rainLayer sheets; glyph tail; column blank; click splash; exact-C trail mix
MECHANISM INTERROGATION:
  tactic 2: a drop has a bright core and a dimmer shoulder. The existing head is one flat green band.
  tactic 3: the three sheets use different densities but the same x origin, so their columns stack.
ADD:
  1. head core — inside the existing rainPhase band, a narrower core goes near-white and the shoulder stays the green already there. Glitch still scales both
  2. sheet stagger — each rainLayer shifts sideways by a fraction of its own column pitch so the three sheets do not share column edges
FORBID: a new spring, another column-blank, another glyph-tail term
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: spectral-rain
IDENTITY: photo streaks of chromatic rain at a sprung angle, each column voiced by its own spectrum bin.
KEEP VERBATIM: Rain Density / Chromatic Strength / Trail Length / Rain Angle Scale; spring on angle and speed in extraBuffer[133..137]; per-column plasma bin trail; click splash; R/G/B sample split
MECHANISM INTERROGATION:
  tactic 2: a streak has a sharp head and a soft chromatic tail. drop is one smoothstep used for both.
  tactic 7: colSpeed is a per-column rate and it only scales time. Faster columns should also slant.
ADD:
  1. streak core — the tip of dropNoise stays sharp and bright; chromatic displace uses the tail behind it. Trail Length still sets how long that tail is
  2. column slant — faster columns add a small x-coupled phase, scaled by Rain Angle Scale, so speed reads as a lean inside the rotated field
FORBID: a second spring, a glyph font, a green matrix palette
A PACKING: ACES display RGBA (C unread). Adding ACES on the display write; A matches that colour
```

```
SHADER: cyber-rain
IDENTITY: neon rain on wet glass, cleared by a sprung wiper, with vertical wet blur, bloom, drops, streaks, and a wetness trail.
KEEP VERBATIM: Rain Intensity / Wet Blur / Neon Bloom / Wiper Size; spring wiper in extraBuffer[133..138]; bass envelope in A.a; five-tap vertical blur; drop and streak hashes; EMP rings; wet trail from C; corner chromatic split
MECHANISM INTERROGATION:
  tactic 5: a drop on glass is a bead, not a lit cell. A wiper blade pushes a lip of water at its radius.
  tactic 3: wiper is a disc mask. The radius is computed and then only used as a smoothstep.
ADD:
  1. beaded drop — the same hash still gates the drop; inside the cell the light is a round bead low in the cell plus a dimmer body
  2. wiper lip — a thin bright ring at the existing wiper radius, the water the blade is pushing. Wiper Size still owns that radius
FORBID: a second EMP, glyph rain, a matrix green replacement of the blue rain colour
A PACKING: pre-ACES wet-trail RGB in A.rgb, bass envelope in A.a (unchanged). ACES on writeTexture only
```

```
SHADER: cyber-rain-interactive
IDENTITY: three parallax sheets of ROM glyphs falling in columns, pushed by the pointer, with a racing head packet and a smear from last frame.
KEEP VERBATIM: Rain Speed / Density / Glitch / Trail Len; fp128 column phase; 8-glyph ROM; two drops per column; depth weights; head packet; EMP rings; spring-free pointer push; dropout; exact-C smear
MECHANISM INTERROGATION:
  tactic 2: on a real trail the head character changes every tick and the body holds. Both currently share one charStep.
  tactic 3: the far sheet is only a weight. Its glyphs are the same green as the near sheet.
ADD:
  1. head glyph flicker — the cell at the head uses a faster character step; the trail behind it keeps the slow step. Glitch still scrambles both
  2. far-sheet grey — the far layer's ink moves toward the photo luma, so depth reads as a farther, duller sheet
FORBID: a spring (this file is the spring-free twin of cyber-rain), a second ROM, a white-hot leader colour
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: retro-gameboy
IDENTITY: the photo quantised to the four-green DMG palette in round LCD dots, with a block grid and a ghost of last frame.
KEEP VERBATIM: Pixel Size / Contrast / Grid Strength / Shadow Offset; four palette greens; depth-scaled block; chromatic edge taps; shadow sample; round LCD dots; mouse contrast and brightness; scanline from mids
MECHANISM INTERROGATION:
  tactic 2: an STN LCD rises slower than it falls. The ghost mix is symmetric.
  tactic 5: the gap between dots on a DMG is the unlit darkest green, not a black multiply.
ADD:
  1. slow rise — when this frame's luma is above last frame's, the existing persistence holds longer; darkening snaps faster
  2. unlit well — where the LCD mask is open, the gap mixes toward palette index 0 instead of multiplying toward black
FORBID: a spring, a new palette, replacing the round dots
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: flip-matrix
IDENTITY: a grid of flaps that hinge toward the pointer, showing a front face, a mirrored back face, and a cam notch as they cross 90°.
KEEP VERBATIM: Grid Density / Effect Radius / Flip Intensity / Tile Gap; hover arrival and held drive; click update wave; projected height; back-face mirror; cam notch; bevel and specular
MECHANISM INTERROGATION:
  tactic 5: a flap hinge has a metal pin, and an open flap shadows its own gutter.
  tactic 3: sineAngle drives the cam darkening and is not used as a pin or a cast shadow.
ADD:
  1. hinge pin — a narrow bright line inside the existing hinge, visible when the flap is open (sine large). The cam notch still darkens the wider hinge
  2. gutter shadow — outside the flap, the cell darkens as the flap opens, so the gap reads as a cast shadow. Tile Gap still sets the gap width
FORBID: a spring, a second hinge axis, a new material palette
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: bayer-dither-interactive
IDENTITY: ordered Bayer dither of the photo, finer away from the pointer, with interleaved-gradient assist and per-channel matrix rotation.
KEEP VERBATIM: Bit Depth / Contrast / Dither Spread / Pixel Scale Max; 8×8 Bayer; IGN mix; G/B channel rotation; neighbour error diffusion; bass palette steps; phosphor dot and scan halo
MECHANISM INTERROGATION:
  tactic 1: error diffusion of a sub-level residual flickers. The error vector is already computed.
  tactic 5: an 8×8 Bayer tile has a visible seam on real prints when the spread is high. The tile edge is only the matrix index.
ADD:
  1. error coring — neighbour error below a fraction of one level does not diffuse. Influence still gates how much of the rest is applied
  2. tile seam — pixels on the 8×8 boundary darken in proportion to Dither Spread, so the matrix period is visible when dither is strong
FORBID: a spring, a second noise field, another channel rotation
A PACKING: ACES display RGBA (C unread)
```
