# Idea Cards — Grok (cyber HUD twelve, 2026-10-27)

Written before the idea edits. Twelve existing pointer-led cyber, scope, and armor shaders. Each card adds **two** new ideas. Earlier ideas stay. Saved `params` stay byte-exact.

The CPU rewrites all 256 `extraBuffer` floats every frame (`writeExtraBuffer`), so slots `[133..255]` do not survive to the next dispatch. Springs and envelopes stored there are removed or ignored. That is a fix, not an idea. `plasmaBuffer[1..]` is never uploaded; those reads move to `plasmaBuffer[0]`.

Prelude migration on the eleven pasted headers is infrastructure.

Formula rule: soft inverse-square (§12.2F) is used on **one** file (`neon-edge-radar`). No other §12.2 row is shared.

---

## oscilloscope-overlay

IDENTITY: a scope trace of the luma on the scanline under the cursor, with a scan marker, phosphor, and graticule.
KEEP VERBATIM: Amplitude / Thickness / Wave Opacity / Scan Alpha; the scanline luma trace; phosphor mix; grid; peak sparkle; ACES on the display.
MECHANISM:
- tactic 2: a real scope blanks the beam during flyback.
- tactic 6: once A holds the display, C is last frame's trace and can ghost.
ADD:
  1. Flyback blank — the trace cuts out at the right edge. Thickness still sets the spot.
  2. Phosphor tail — last frame's overlay alpha ghosts in the phosphor colour.
FORBID: a new spring, a second waveform, IQ palette.
A PACKING: same vec4 as the display write (premultiplied overlay). C is that image next frame.
FORMULA: none.

## energy-shield

IDENTITY: a hex force field that lights under the cursor, remembers activation, and rings on click.
KEEP VERBATIM: Hex Scale / Ripple Speed / Impact Strength / Decay; hex grid; held tighten; oil-slick edges; Fresnel rim; click rings; trail in A.r.
MECHANISM:
- tactic 3: `gv` is the vector inside the hex and is only used to pick the cell.
- tactic 8: the impact adds light on top of the photo.
ADD:
  1. Facet shade — the side of the hex facing the cursor catches the shield colour.
  2. Impact spend — the photo under the ring desaturates, so the flare is not free light.
FORBID: a new grid, a spring, replacing the oil-slick.
A PACKING: raw `(trail, mouseIntensity, impact, alpha)`. ACES on the display write only.
FORMULA: none.

## laser-burn

IDENTITY: a pointer beam that chars the picture and leaves cooling embers.
KEEP VERBATIM: Beam Size / Burn Intensity / Heal Rate / Heat Glow; char, heat, and ember in A; click brands.
MECHANISM:
- tactic 2: heat conducts past the spot.
- tactic 3: the char field already has an edge that is thrown away.
ADD:
  1. Heat conduction — four neighbours of stored heat bleed into this texel.
  2. Oxide lip — where char differs from those neighbours, the ember brightens.
FORBID: a spring (the buffer does not persist), a new solver.
A PACKING: raw `(char, cooledHeat, ember, alpha)`. ACES on the display write only.
FORMULA: none.

## neon-edge-radar

IDENTITY: a PPI beam that lights luma and depth edges, with a wake, range rings, and a held interrogate.
KEEP VERBATIM: Threshold / Speed / Width / Intensity; wake; three rings; hold-to-park; state texel at (0,0).
MECHANISM:
- tactic 2: a real radar return falls with range.
- tactic 5: the receiver hiss sits in the wake, not on the black field.
ADD:
  1. Soft inverse-square return — contacts dim as range² grows.
  2. Receiver speckle — hash hiss only inside the wake.
FORBID: a second sweep, a spring.
A PACKING: unchanged. (0,0) is the beam angle; other texels are display RGBA.
FORMULA: soft inverse-square (§12.2F). Only this file.

## data-stream

IDENTITY: falling matrix strips of glyphs over the picture, bent by the pointer and by clicks.
KEEP VERBATIM: Flow Speed / Strip Density / Turbulence / Digital Glow; strip flow; glyph mask; green mix; click rings.
MECHANISM:
- tactic 5: a matrix column has a bright head and a fading tail.
- tactic 5: a data link drops whole columns.
ADD:
  1. Leading head — glyph brightness rises toward the bottom of the cell, the direction of the fall.
  2. Column dropout — a strip goes dark for a moment, scaled by Turbulence.
FORBID: the corruption-shader head stored in alpha, a spring.
A PACKING: ACES display RGBA (C unread).
FORMULA: none.

## quantum-cursor

IDENTITY: a round field of mosaic blocks, chromatic split, and click decoherence around the pointer.
KEEP VERBATIM: Radius / Block Size / Aberration / Chaos; block mosaic; channel shuffle; click chaos and ring.
MECHANISM:
- tactic 4: Block Size is a cell pitch, so the field edge can sit on that pitch.
- tactic 2: a "measurement" leaves bright pixels less scrambled than dark ones.
ADD:
  1. Stair boundary — the mask radius quantises to the block pitch.
  2. Bright collapse — highlights inside the field mix back toward the sharp photo as Chaos drops.
FORBID: a spring, a new palette as the look.
A PACKING: ACES display RGBA (C unread).
FORMULA: none.

## signal-tuner

IDENTITY: a TV tuner. Rows wobble and split inside a radius around the pointer, with snow, a multipath ghost, and beat bands.
KEEP VERBATIM: Frequency / Interference / Drift Speed / Static; row wobble; snow; ghost; beat bands; history only inside the zone.
MECHANISM:
- tactic 5: an off-station set shows the horizontal sync pulse at the left of the line.
- tactic 2: unlocked chroma swims vertically, not only sideways.
ADD:
  1. Sync bar — a bright stub at the left of the row, inside the tuning zone, stronger with Frequency.
  2. Chroma swim — the existing red/blue split also steps downward with Static.
FORBID: a second wobble system, a spring.
A PACKING: pre-ACES linear RGB + alpha. ACES on the display write. Unchanged.
FORMULA: none.

## cyber-lattice

IDENTITY: two perspective lattices with thin-film rails and cell traffic, bent by the pointer.
KEEP VERBATIM: Scale / Distortion / Glow / Radius; both grids; thin film; traffic pulses; click waves.
MECHANISM:
- tactic 3: grid coordinates already know where two rails cross.
- tactic 2: the far lattice should hide behind the near one.
ADD:
  1. Solder joints — a bright node where both rails of the near grid cross.
  2. Rail occlusion — the far mask is cut where the near mask is lit.
FORBID: a spring, a third lattice.
A PACKING: pre-ACES linear RGB in A so the history mix is not tone-mapped twice. ACES on the display write.
FORMULA: none.

## cyber-trace

IDENTITY: a neon trail painted by the pointer, with click blooms, kept in C.
KEEP VERBATIM: Decay / Glow / Hue / Size; history accumulate; click stamps; ACES composite.
MECHANISM:
- tactic 7: the trail in C has a direction even though the spring velocity does not persist.
- tactic 8: the neon is added on top of the photo and never darkens it.
ADD:
  1. Paint tangent — the stamp capsule follows the perpendicular of the history gradient, so an existing trail lengthens the arc.
  2. Etched groove — the photo darkens under the trail. A dashed via sits on the brush rim.
FORBID: a new spring, replacing the hue trail.
A PACKING: history RGB in A.rgb; A.a is brush coverage (was a constant 1).
FORMULA: stroke tangent from the paint field (§12.2C). Only this file.

## cursor-aura

IDENTITY: a soft coloured disc around the pointer that picks up photo edges and throws click rings.
KEEP VERBATIM: Aura Size / Glow Intensity / Edge Softness / Color Hue; 4-tap edges; click rings; hue colour.
MECHANISM:
- tactic 8: the glow is added and the photo under it stays full brightness.
- tactic 2: the feather band is a penumbra, not a hard mix.
ADD:
  1. Core spend — the photo inside the disc darkens a little as Intensity rises.
  2. Penumbra bleach — the feather ring pulls the photo toward the glow hue.
FORBID: a spring, a second aura shape.
A PACKING: ACES display RGBA.
FORMULA: none.

## neon-strings

IDENTITY: heated wires across the frame, plucked by the pointer, with nodes and end pins.
KEEP VERBATIM: String Count / Tension / Intensity / Cool Rate; three harmonics; pluck packet; click impulses; nodes; end pins; blackbody.
MECHANISM:
- tactic 2: a real string's partials run slightly sharp (stiffness).
- tactic 2: a pluck shakes the neighbouring string.
ADD:
  1. Inharmonic stiffness — the second and third partials sharpen as Tension drops.
  2. Sympathetic neighbour — the adjacent string takes a fraction of the pluck envelope.
FORBID: a new instrument, a spring.
A PACKING: ACES display RGBA. Unchanged.
FORMULA: none.

## cyber-hex-armor

IDENTITY: hex plates that pull back around the pointer, with seams and circuit traffic.
KEEP VERBATIM: Hex Size / Glow / Reveal Radius / Border; plate retract; bevel; circuits; click wave.
MECHANISM:
- tactic 2: a seam is a gap, so it should shadow, not only glow.
- tactic 5: a retracting plate shows a hinge pin on one flat.
ADD:
  1. Gap shadow — the seam darkens the alloy under the glow line.
  2. Hinge pin — one side of a retracting plate catches a metal highlight.
FORBID: a second tile shape, a spring.
A PACKING: pre-ACES linear RGB in A so history is not tone-mapped twice. ACES on the display write.
FORMULA: none.
