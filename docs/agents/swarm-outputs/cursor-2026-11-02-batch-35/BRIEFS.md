# Idea Cards — cursor/batch-35 neon edge and contour (2026-11-02)

Written before the WGSL edits. Twelve neon edge and contour shaders, 130–217 lines. Each file already names ideas; these cards add two more inside that path. Saved params stay byte-exact. No new spring. No shared ripple stamp. No shared palette.

Formula rule: energy-conserving bloom (§12.2F) is only on `neon-edge-diffusion`. Soft inverse-square (§12.2F) is only on `edge-glow-mouse-em`. No other §12.2 row is used. No row is shared.

## neon-contour-drag

```
SHADER: neon-contour-drag
IDENTITY: dual-scale Sobel neon contours pulled toward the cursor, with light running along the edge and a bass-pulsed inverted core.
KEEP VERBATIM: Edge Strength, Warp Radius, Glow Intensity, Color Shift; fine+coarse Sobel; radial warp; tangent streaks; contour runners; hue conveyor; click fronts; bass core; emissive alpha (core 0.3).
MECHANISM INTERROGATION:
  tactic 2: a drag is not only a radial shift. Viscous pull smears the contour sideways, along the pull's tangent.
  tactic 7: the gradient already has a bright side and a dark side. A glass tube lights the wall and leaves the bore dark.
  tactic 3: warpAmount is computed and then thrown away after the UV offset.
ADD:
  1. Drag shear — inside the warp disc, edge strength is the average of two Sobel taps stepped along the pull tangent.
  2. Glass wall — one texel up the gradient is brighter (the wall); the dark side of the same contour is dimmed.
FORBID: a new spring, an IQ palette, inverse-square spotlight (neon-edges already owns that), reading C as history.
A PACKING: ACES display RGBA. C is unread. A matches the display.
```

## neon-contour-interactive

```
SHADER: neon-contour-interactive
IDENTITY: Sobel neon tubes on black. Hue cycles, a pulse rolls out from the cursor, weak tubes flicker, and the palette sits on six tube gases.
KEEP VERBATIM: Edge Thresh, Glow, Color Cycle, Pulse Speed; 3×3 Sobel; local threshold near the cursor; six-tube quantize; radial pulse; starter flicker; mouse glow only on tubes; diagnostic A (isEdge, glowStrength, proximity, alpha).
MECHANISM INTERROGATION:
  tactic 5: a real tube ends in a brighter electrode. The shader has a continuous ridge and no end.
  tactic 3: pulse is a 0–1 sine used as a wash. The crest of that same wave is the bead a mercury tube shows.
  tactic 7: edgeX/edgeY are a direction. The end of a tube is where that direction stops being an edge.
ADD:
  1. Electrode caps — where the gradient holds here and drops a step along the tangent, a white cap lights. Starter flicker still gates it.
  2. Mercury bead — the existing radial pulse keeps its wash; the crest of that pulse is an extra bright bead on the same tubes.
FORBID: a new hue family, a spring, click shockwaves, replacing the diagnostic packing.
A PACKING: diagnostic (unchanged). ACES on writeTexture only.
```

## neon-edge-diffusion

```
SHADER: neon-edge-diffusion
IDENTITY: a shared-tile RGB edge turned into a neon ramp and diffused through a 7-tap hex bokeh, with click ripples on the lit edges.
KEEP VERBATIM: Glow Intensity, Bloom Radius, Ripple Strength, Color Shift; 18×18 tile; edgeAt formula; dilation; luma² hex weights; tangent stretch; mouse boost; ripple loop.
MECHANISM INTERROGATION:
  tactic 3: edgeC (the undilated center) is computed and then replaced by a dilated max. The filament in the middle of the bloom is that center.
  tactic 8: the hex glow adds the neighbour colour on top of the edge. That light left the contour; the core should give some of it back.
  tactic 1: the bloom is a box of seven taps. The next fact about the same bloom is energy, not a new kernel.
ADD:
  1. Filament core — a thin ridge of the undilated edgeC sits on top of the dilated bloom.
  2. Energy-conserving bloom (§12.2F) — the core loses a fraction of the hex spread before the 50/50 mix.
FORBID: a second bokeh shape, a spring, reading C (this file does not own history), thin-film.
A PACKING: ACES display RGBA (unchanged; C unread).
```

## neon-edge-reveal

```
SHADER: neon-edge-reveal
IDENTITY: a flashlight reveals the photo, neon tubes with a hot core and a wide halo glow in the beam, and lit edges burn in after the beam leaves.
KEEP VERBATIM: Intensity, Speed, Scale, Detail; 3×3 Sobel; raw-cursor beam; click flares; hue cycle; gas colour by orientation; hot core; 3 px halo; soft-knee; photo reveal; C burn-in. No spring (removed on purpose).
MECHANISM INTERROGATION:
  tactic 4: Scale is one disc. A flashlight has a bulb and a penumbra at the same outer radius.
  tactic 2: the afterimage is a copy of the tube. The white core dies first; neon red fades before argon blue.
  tactic 6: C is the burn. Channel decay is the one extra continuity that packing affords.
ADD:
  1. Flashlight hotspot — Scale still sets the outer radius. The inner 38% is the bulb; the skirt is dimmer.
  2. Gas afterimage — persisted C fades red fastest and blue slowest, on the same 0.86 decay.
FORBID: putting the spring back, ACES inside A (the burn is already soft-kneed), a new gas palette.
A PACKING: soft-knee display RGBA. C is that burn, exact load. No second tone curve.
```

## neon-edges

```
SHADER: neon-edges
IDENTITY: multi-scale colour and depth Sobel with Mach bands, an inverse-square spotlight, Kelvin isotherms, and current pulses running along the tube.
KEEP VERBATIM: Edge Sensitivity, Mach Strength, Spotlight Radius, Neon Gain; five scales; blackbody isotherms; inverse-square spotlight; current along scale-1 tangent; bright and dark Mach bands.
MECHANISM INTERROGATION:
  tactic 3: five magnitudes are summed and the disagreement between scale 1 and scale 3 is thrown away. Speckle is fine-only; a contour is both.
  tactic 2: the dark Mach band is lateral inhibition. The current should dip through that trough, not paint over it.
  tactic 7: darkBand is a signed notch the halo already uses on the photo. The tube's own current never sees it.
ADD:
  1. Scale agreement — neon gain rises where scale 1 and scale 3 are both strong, and the fine treble detail backs off where scale 3 is empty.
  2. Mach trough — the existing dark band notches the racing current.
FORBID: a new temperature palette, a spring, replacing the five-scale sum, Cauchy.
A PACKING: ACES display RGBA (unchanged).
```

## neon-topology

```
SHADER: neon-topology
IDENTITY: depth contour lines as a neon topo map, with a mouse lens, click quakes, slope hachures, and a hypsometric fill between the lines.
KEEP VERBATIM: Line Density, Height Scale, Mouse Force, Glow Strength; fract contour lines; major every fifth; phantom bass contours; hachures along the slope tangent; hypo fill; lens; quakes; haze.
MECHANISM INTERROGATION:
  tactic 5: an index contour is not a brighter line. It breaks so a label can sit in the gap.
  tactic 4: Height Scale stretches the lines. The fill between them should also know the slope, which gLen already measures.
  tactic 7: slopeDir is used for hachures and nowhere else. The gap runs along that same tangent.
ADD:
  1. Index gap — major contours open a short slot along the slope tangent. Minor lines stay continuous.
  2. Slope shade — the existing hypsometric fill darkens where the depth gradient is steep.
FORBID: a new contour family, a spring, replacing hachures, storing the height field in A.
A PACKING: ACES display RGBA (unchanged).
```

## neon-poly-grid

```
SHADER: neon-poly-grid
IDENTITY: a hex grid that lights under the cursor and leaves a fading trail, with vertex beads and a fill in occupied cells.
KEEP VERBATIM: Grid Scale, Line Width, Glow Strength, Decay Speed; hexDist / hexGrid; the existing pointer spring; click rings; trail in A.r; vertex glow; cell fill; per-cell FFT voice.
MECHANISM INTERROGATION:
  tactic 6: C.r is last frame's trail. A wall between two occupied cells is brighter than a wall with empty space beside it.
  tactic 5: a neon cell that is only decaying flickers. A freshly lit cell does not.
  tactic 3: newTrail mixes fresh activation and history into one scalar, then throws away which part is the tail.
ADD:
  1. Shared wall — a grid edge where this cell and a neighbour both carry trail burns hotter. The stored trail is unchanged.
  2. Dying-tail flicker — only the part of the trail that is not fresh activation flickers, per cell id. A.r stays the clean decay.
FORBID: a second grid, a new spring, baking the flicker into A, plasmaBuffer bins beyond the voice the file already reads.
A PACKING: trail in A.r (unchanged). ACES on writeTexture only.
```

## neon-quantum-lattice

```
SHADER: neon-quantum-lattice
IDENTITY: a three-layer Penrose lattice with phason drift, runners, electron hops on treble, and amber defect tiles.
KEEP VERBATIM: Inflation, Glow, Parallax, Brightness; five-direction penrose distance; defect test; three layers; runners; electron hop; dephase fronts; history advected against the conveyor.
MECHANISM INTERROGATION:
  tactic 2: a phason defect flips a tile. The lines should kink there, not only wear an amber highlight.
  tactic 3: d1 and d2 are both distances. Where they nearly match, two Ammann bars run together and the gap between them is never drawn.
  tactic 1: the defect site is already a mask. The kink is that mask times the phason the file already moves.
ADD:
  1. Phason kink — layer 1's sample point nudges along the existing phason where the defect mask is high. The amber highlight stays.
  2. Ammann beat — a faint ribbon where |d1 − d2| is small and neither layer is already an edge.
FORBID: a fourth layer, a new tiling, a spring, thin-film on the metal.
A PACKING: ACES display RGBA (unchanged; C is that color, exact load).
```

## electric-contours

```
SHADER: electric-contours
IDENTITY: photo edges as plasma, plus equipotentials and field lines of two fixed charges and the cursor, with corona, sparks, and FFT arcs.
KEEP VERBATIM: Edge Threshold, Glow, Field Density, Spark; Sobel; potential and E of the two charges plus the mouse; equipotentials; field lines; corona packets; click-spark charges; held charge; band arcs; diagnostic A (potential, |E|, edge+spark, dielectric/corona).
MECHANISM INTERROGATION:
  tactic 5: a point charge on a field plate is drawn as an electrode, not as zebra packed into the singularity.
  tactic 2: the header calls this dielectric polarization, but the dielectric term is only a colour mix. Polarization is the edge lighting where its normal lines up with E.
  tactic 3: sx/sy and eField are both already on the pixel. Their alignment is the polarization.
ADD:
  1. Electrode discs — metal caps on the two fixed charges and a smaller one on the cursor. Equipotentials stop at the cap.
  2. Dielectric polarization — the existing dielectric tint lights where the Sobel normal aligns with E.
FORBID: a new charge layout, a spring, writing display colour into the diagnostic A, soft inverse-square (edge-glow-mouse-em owns that this batch).
A PACKING: field diagnostics in A, un-tonemapped (unchanged). ACES on writeTexture only.
```

## edge-glow-mouse

```
SHADER: edge-glow-mouse
IDENTITY: unsharp edge glow with a magenta/teal oil-slick, packets racing along the tangent, click rings, and a trail from last frame.
KEEP VERBATIM: Threshold, Glow Radius, Intensity, Color Cycle; 5-tap unsharp; tangent bloom; oil-slick hue; tangent packets; held tighten; click rings; diagnostic A (glowMask, mouseAura, packetEnergy, alpha).
MECHANISM INTERROGATION:
  tactic 6: C is the diagnostic the header names, but the trail reads those channels as if they were RGB. The trail should relight from glowMask and packetEnergy.
  tactic 7: the bloom walks the tangent only. A tube also has a short halo across the edge, and Glow Radius already sets that width.
  tactic 3: edgeNormal is computed for the film phase and never used to place light.
ADD:
  1. Mask trail — last frame's glowMask (C.r) and packetEnergy (C.z) add glow. They are no longer mixed in as a fake colour.
  2. Normal halo — two taps along the existing edge normal, scaled by Glow Radius, added to the tangent bloom.
FORBID: a new spring, replacing the oil-slick, changing A to display RGBA (the trail now matches the documented packing), anti-halo on a different file.
A PACKING: (glowMask, mouseAura, packetEnergy, finalAlpha) unchanged. The read now matches the write.
```

## edge-glow-mouse-em

```
SHADER: edge-glow-mouse-em
IDENTITY: photo edges lit by the cursor's electric field, with a Laplacian corona and a streak advected along the field from last frame.
KEEP VERBATIM: Edge Threshold, Glow Radius, Glow Intensity, Color Cycle; colour-edge magnitude; Laplacian corona; E and B from the cursor; previous-mouse velocity in extraBuffer[133..134]; field-line advection from C; hue rotation by B.
MECHANISM INTERROGATION:
  tactic 1: electricField is charge/r² with a 0.001 floor, so the core is a singularity. The next-better coulomb field is soft inverse-square, and Glow Radius is the core size.
  tactic 2: a moving charge brightens on the side it is heading into. mouseVel is already computed and only feeds B.
  tactic 7: the velocity has a direction. The leading side is the half-plane in front of it.
ADD:
  1. Soft inverse-square (§12.2F) — E uses charge/(r² + core²). Glow Radius sets the core. The far field stays coulomb.
  2. Leading-edge glow — edge light brightens where the cursor is heading. Stationary cursors do not.
FORBID: a full spring, a second charge, rewriting the advection streak, energy-conserving bloom (the diffusion file owns that).
A PACKING: ACES display RGBA (unchanged; C is that colour, exact load).
```

## posterize-neon-edges

```
SHADER: posterize-neon-edges
IDENTITY: the photo crushed into flat luma bands, with a thin Sobel ridge drawn in neon and the band interior held flat.
KEEP VERBATIM: Levels, Edge Threshold, Glow, Hue Shift; luma quantize; band-hold (FBM dies inside the band); Sobel ridge; focus brightening near the cursor; shadow/highlight tints.
MECHANISM INTERROGATION:
  tactic 3: bandProbe is the position inside the posterize band and is only used to kill the FBM. The band boundary itself is a contour.
  tactic 7: the Sobel is a direction. The FBM that wobbles the threshold is isotropic; a poster edge wobbles along the contour.
  tactic 4: Levels sets how many boundaries exist. Lighting those boundaries is the spatial version of the same quantize.
ADD:
  1. Cel filament — a hairline where fract(luma × levels) wraps, in the existing neon hue, beside the Sobel ridge.
  2. Tangent ink waver — the existing FBM samples along the Sobel tangent, and only where the edge mask is up, so flats stay flat.
FORBID: a new posterize mode, a spring, an IQ palette, quantizing a different feature than luma.
A PACKING: ACES display RGBA (unchanged).
```
