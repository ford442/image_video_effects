# Notes — cyber HUD twelve (2026-10-27)

Prelude migration on eleven pasted headers is infrastructure. `neon-edge-radar` already included `_prelude.wgsl`. Saved `params` were not edited.

`writeExtraBuffer` uploads all 256 floats every frame and only fills `[0..132]`, so springs and envelopes in `[133..255]` never survived a frame. Those reads now use the pointer or `plasmaBuffer[0]`. That is a fix, not an idea. `plasmaBuffer[1..]` is never uploaded; strip, block, sector, and aura shimmer now use the live bass/mids/treble bands.

`cyber-lattice` and `cyber-hex-armor` store pre-ACES linear colour in A. The display write is ACES. Previously A held tone-mapped colour that the next frame tone-mapped again.

Real-GPU visual QA was not run. This VM has no hardware GPU.

## Per shader

### oscilloscope-overlay
Kept: scanline luma trace, phosphor, graticule, sparkle, four sliders.
A packing: the same premultiplied display vec4. C is that image.
In the diff: `flyback` blanks the trace at the right; `phosphorTail` ghosts `prevScope.a`.

### energy-shield
Kept: hex grid, held tighten, oil-slick, Fresnel, click rings, trail in A.r.
A packing: raw `(trail, mouseIntensity, impact, alpha)`.
In the diff: `facet` shades the hex toward the cursor; `spent` desaturates the photo under `impactFlare`.

### laser-burn
Kept: char / heat / ember state, click brands, four sliders.
A packing: raw state. ACES on the display write only. C is `textureLoad`.
In the diff: four-neighbour heat bleed; `charEdge` lifts the ember. The beam is the pointer.

### neon-edge-radar
Kept: wake, three rings, hold-to-park, state texel at (0,0).
A packing: unchanged.
In the diff: `radarFall` is `1/(1+r²)` (§12.2F); `speckle` sits in the wake.

### data-stream
Kept: strip flow, glyphs, green mix, click rings.
A packing: ACES display RGBA.
In the diff: `head` brightens the bottom of the cell; `dropout` darkens a strip by Turbulence.

### quantum-cursor
Kept: mosaic, shuffle, click chaos and ring.
A packing: ACES display RGBA. C unread.
In the diff: `qDist` steps the mask to the block pitch; `sharp` mixes highlights back toward the photo.

### signal-tuner
Kept: wobble, snow, ghost, beat bands, zone-only history.
A packing: pre-ACES linear RGB. Unchanged.
In the diff: `syncBar` at the left of the row; `swim` steps chroma down with Static.

### cyber-lattice
Kept: both grids, thin film, traffic, click waves.
A packing: pre-ACES linear RGB.
In the diff: `joint` at near-rail crossings; `mask1` is cut by `mask0`.

### cyber-trace
Kept: history accumulate, click stamps, hue, ACES composite.
A packing: history RGB; A.a is brush coverage.
In the diff: the capsule follows the paint tangent (§12.2C); `groove` darkens the photo; `viaDash` marks the rim.

### cursor-aura
Kept: 4-tap edges, hue, click rings, four sliders.
A packing: ACES display RGBA.
In the diff: the photo under the disc darkens with Intensity; `penumbra` pulls the feather toward the glow hue.

### neon-strings
Kept: three harmonics, pluck packet, nodes, end pins, blackbody.
A packing: ACES display RGBA.
In the diff: `stiff` sharpens h2 and h3 as Tension drops; `neighbor` shares the pluck envelope.

### cyber-hex-armor
Kept: plate retract, bevel, circuits, click wave.
A packing: pre-ACES linear RGB.
In the diff: `alloy` darkens by `seam`; `hinge` lights one flat while the plate retracts.
