# Idea Cards — cursor/batch-31 fireworks and embers (2026-11-01)

Written before the WGSL edits. Second pass: each file already has a named idea set. These cards add two more, inside the existing main path. Saved params stay byte-exact. No spring, no shared overlay.

Formula rule: Beer-Lambert (§12.2F) is used only on `gen-stardust-nebula`. Hot-band rise is the buoyancy reading of the ember field only (the file already stores age and advects it). No other §12.2 row is shared.

## fireworks-depth-parade

```
SHADER: fireworks-depth-parade
IDENTITY: depth-sorted parade — foreground shells break before midground, then background, tinted by the photo.
KEEP VERBATIM: three layers, layerSep delay, depthMatch gate, image-depth occlusion visibility, atmospheric desat (lf * 0.12), Layer Separation / Launch Speed / Depth Boost / Trail Length, click barrage in the same layer order, B echo.
MECHANISM INTERROGATION:
  tactic 2: a real mortar is in the air before the break; the far layers currently pop in with no climb.
  tactic 6: nearer bursts already own the pixel; their spent light is the smoke the farther shells have to fire through.
  tactic 3: layerDelay is computed and then only used as a skip.
ADD:
  1. Mortar rise — during layerDelay the shell climbs from the image probe to the break, on the auto parade and the click parade.
  2. Foreground smoke veil — layer-0 breaks leave a soft haze that dims and warms the layers behind them.
FORBID: a new solver, springs, IQ palette, changing the three-layer order.
A PACKING: ACES display RGBA; B dimmed echo (unchanged).
```

## fireworks-edge-ignite

```
SHADER: fireworks-edge-ignite
IDENTITY: photo contours are the fuses; shells launch off those lines.
KEEP VERBATIM: Sobel edgeGradient, tangent spread on the shell, sine fuse, click ascent then burst, Edge Sensitivity / Launch Power / Trail Glow / Color Boost, B echo.
MECHANISM INTERROGATION:
  tactic 2: a fuse has a bright bead and a charred trail, not a uniform sine wash.
  tactic 7: the tangent is already the travel direction.
  tactic 8: the light of the fuse leaves a darkened lip in the photo.
ADD:
  1. Fuse bead — a compact hot head rides the contour along the existing tangent.
  2. Char lip — behind that head the photo warms and darkens on the strong edge.
FORBID: replacing the contour launches, springs, a second edge detector.
A PACKING: ACES display RGBA; B dimmed echo (unchanged).
```

## fireworks-patriotic-july4

```
SHADER: fireworks-patriotic-july4
IDENTITY: the photo feeds a red / white / blue shell show with waving flag stripes.
KEEP VERBATIM: patriotColor bands, j%3 tricolor sparks, stripe wave, star diffraction rays, mortar flash, Patriot Mix / Burst Power / Stripe Wave / Sparkle, B echo.
MECHANISM INTERROGATION:
  tactic 2: a patriotic color-changing shell breaks red, then white, then blue — the bands already exist but fire together.
  tactic 4: Stripe Wave is a flat sine; a cloth wave has a dark crease where the slope is steep.
  tactic 5: flag crease is the artifact the stripe is missing.
ADD:
  1. Sequenced break — red sparks, then white, then blue, using the existing band index.
  2. Cloth crease — the stripe darkens where cos(phase) peaks, before shells are added.
FORBID: a canton rectangle, a new palette, springs.
A PACKING: ACES display RGBA; B dimmed echo (unchanged).
```

## fireworks-portrait-burst

```
SHADER: fireworks-portrait-burst
IDENTITY: bright regions of the photo are the cores of detonations in the source color.
KEEP VERBATIM: seven luma probes, thresh gate, dissolve of bright regions, warmth cooling toward ember gold, highlight bloom, Brightness / Burst Size / Dissolve / Warmth, B echo.
MECHANISM INTERROGATION:
  tactic 2: a portrait detonation should keep the catchlight in the face.
  tactic 7: the luma gradient at the probe is the direction the highlight faces; sparks currently leave on a perfect circle.
  tactic 3: pCol and pLum are already computed and then thrown away as a direction.
ADD:
  1. Catchlight pin — the brightest core is spared from the dissolve and stays a small white point.
  2. Outward highlight bias — spark velocity gains a component along the photo luma gradient at the probe.
FORBID: face detection, a new particle system, springs.
A PACKING: ACES display RGBA; B dimmed echo (unchanged).
```

## gen-fireworks-comet-trail

```
SHADER: gen-fireworks-comet-trail
IDENTITY: comet shells — bright head, ion tail anti-velocity, dust trail that falls.
KEEP VERBATIM: head hex core, coma, ion tail, disconnection kink, nucleus jets, peel sparks, Comet Speed / Trail Length / Head Brightness / Color Shift.
MECHANISM INTERROGATION:
  tactic 2: the coma meets the wind in a bow, wider than the jets.
  tactic 4: Trail Length already walks older samples; those samples still use the head's gravity, so the dust does not sag off the ion line.
  tactic 1: the dust trail is the same ballistic integrator with too little g.
ADD:
  1. Bow shock — a thin arc ahead of the head, on the sunward side, wider than the jets.
  2. Dust-tail sag — older trail samples integrate with more gravity than the head.
FORBID: replacing the ion tail, a new comet model, springs.
A PACKING: ACES display RGBA (unchanged).
```

## gen-fireworks-crossette

```
SHADER: gen-fireworks-crossette
IDENTITY: a parent star travels, then forks into four cardinal arms.
KEEP VERBATIM: four-way fork, splitDelay, stagger, X flash, comet sheath, Shell Power / Split Delay / Arm Spread / Hue Shift.
MECHANISM INTERROGATION:
  tactic 2: a real crossette's parent star breaks and the center goes dark.
  tactic 3: armDir is already the axis; it is only used to place sparks, not to leave the cross.
  tactic 8: the split spends the parent.
ADD:
  1. Broken core — after that arm's split time the parent star and its sheath dim out.
  2. Axis ghost — a thin line along the arm lingers after the fork.
FORBID: a fifth arm, a different split count, springs.
A PACKING: ACES display RGBA (unchanged).
```

## gen-fireworks-roman-candle

```
SHADER: gen-fireworks-roman-candle
IDENTITY: stars pumped from fixed tubes along the horizon, with a muzzle flash and a gold fountain between shots.
KEEP VERBATIM: tube row, shot cadence, starCol sequence, muzzle flash, interstitial fountain, gutter flicker, Fire Rate / Star Size / Tube Spread / Trail Length.
MECHANISM INTERROGATION:
  tactic 5: the device is a tube; the shader draws a point of light and no case.
  tactic 2: the apex is a report — a white pop — then the colored sparks. The colored burst is already there.
  tactic 3: tubeX/tubeY are the mouth and are only a glow.
ADD:
  1. Candle tube — a short dark case behind the mouth and a bright lip on the rim.
  2. Apex report — a fast white flash at the burst point, ahead of the colored sparks.
FORBID: changing the tube count, a willow tail, springs.
A PACKING: ACES display RGBA (unchanged).
```

## gen-fireworks-strobe-shell

```
SHADER: gen-fireworks-strobe-shell
IDENTITY: shells whose stars blink, with a true dark interval and a dotted path of past flashes.
KEEP VERBATIM: strobePulse power curve, per-spark phase, dark interval, dotted path, sky veil, Flash Rate / Pulse Power / Afterglow / Color Flash.
MECHANISM INTERROGATION:
  tactic 2: a strobe star has a finite number of blinks, then only the ember afterglow.
  tactic 5: magnesium strobes are white in the core and take color in the fringe.
  tactic 4: Flash Rate already sets the frequency; it should also set how many blinks you get.
ADD:
  1. Blink budget — the live pulse cuts out after a count set by Flash Rate; the dotted path and late embers stay.
  2. White core — a tight magnesium core inside the existing colored bokeh.
FORBID: a second strobe system, frame-hash flashing, springs.
A PACKING: ACES display RGBA (unchanged).
```

## gen-fireworks-kamuro-gold

```
SHADER: gen-fireworks-kamuro-gold
IDENTITY: dense gold and silver glitter that hangs, then falls.
KEEP VERBATIM: kamuroPos hang plateau, per-glitter twinkle, dross satellites, charcoal cooling, Glitter Density / Fall Speed / Gold Mix / Hang Time.
MECHANISM INTERROGATION:
  tactic 4: Fall Speed moves the glitter but the golden haze stays pinned to the break.
  tactic 2: kamuro that hangs a long time is a finer mesh; coarse flakes fall.
  tactic 3: hang is a scalar on the motion only.
ADD:
  1. Cloud sag — the haze center drops with Fall Speed after the hang.
  2. Fine-mesh hang — higher Hang Time draws smaller glitter.
FORBID: adding more sparks inside the inner loop, a new palette, springs.
A PACKING: ACES display RGBA (unchanged).
```

## gen-fireworks-horse-tail

```
SHADER: gen-fireworks-horse-tail
IDENTITY: brocade horse tails — tight at the break, then long parallel gold streamers.
KEEP VERBATIM: drag-integrated tailPos, pinch then parallel rain, tip spark-out, swish, dock knot, Tail Length / Stream Width / Gold Intensity / Fall Speed.
MECHANISM INTERROGATION:
  tactic 2: a burning streamer has a bright running sheen, separate from the sideways swish.
  tactic 8: when the gold cuts off, a dull coal continues past the tip.
  tactic 3: sparkOut already marks the end of the gold and is only a multiplier.
ADD:
  1. Running sheen — a brightness pulse travels down each streamer.
  2. Tip ember — one dull-red coal past the gold cutoff, per streamer, outside the sample loop.
FORBID: turning the tails into kamuro glitter, a new wind model, springs.
A PACKING: ACES display RGBA (unchanged).
```

## ember-drift-dissolve

```
SHADER: ember-drift-dissolve
IDENTITY: bright photo regions lift as embers and advect upward through a heat field.
KEEP VERBATIM: A = (age, lateral, intensity, glow) never tonemapped, exact C loads, rise / spark / heat / decay, furnace, crackle, ash wisps, click ignition, white-hot → amber → ash.
MECHANISM INTERROGATION:
  tactic 2: hot gas rises faster than ash. Age is already in C.r and the vertical flow ignores it.
  tactic 6: C.r is the previous ember; when the glow dies the photo should still show where it burned.
  tactic 1: the advection is the solver; one buoyancy term, not a new solver.
ADD:
  1. Hot-band rise — vertical advection strengthens while age is in the white-hot band and stalls as it becomes ash.
  2. Scorch stain — the photo stays darkened and warmed where last frame's age was high and the glow has faded. Display only.
FORBID: tonemapping A, a new packing channel, springs, plasmaBuffer[1..] used as a new color (the existing band crackle stays).
A PACKING: raw (age, lateral, intensity, glow). ACES on writeTexture only.
```

## gen-stardust-nebula

```
SHADER: gen-stardust-nebula
IDENTITY: an HII nursery — curl-noise gas, H-alpha / OIII / SII emission, dark pillars, proto-stars.
KEEP VERBATIM: fbm5 + curl, pillar column, three emission bands, starField, Cloud Density / Emission / Star Field / Gas Drift, bass on the pillar, treble on the stars.
MECHANISM INTERROGATION:
  tactic 1: pillar darkening is a linear `1 - 0.85*pillar`. Extinction is exponential in column density.
  tactic 3: pillar is a mask; pillar*(1-pillar) is the boundary already implied and thrown away.
  tactic 2: the ionization front is a cyan rim on the dust, not a flat multiply.
ADD:
  1. Beer-Lambert pillar (§12.2F) — replace the linear darken with exp(-tau).
  2. Ionization rim — OIII cyan on the pillar boundary, added after the extinction so the edge stays lit.
FORBID: a new fractal, IQ palette, springs. Prelude migration is floor, not an idea.
A PACKING: ACES display RGBA (C is unread).
```
