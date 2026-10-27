# Idea Cards — Grok (`cursor/reveal-twelve`, 2026-10-27)

Written before WGSL edits. Twelve pointer-led reveal shaders. Each card adds **two** new ideas. Earlier ideas stay. Saved `params` stay byte-exact. No shared spring, shockwave stamp, or IQ palette.

Formula rule: a §12.2 row is used on at most two files here. Soft inverse-square is the only shared row (thermal-touch, neon-flashlight). Both are lights.

Ten pasted headers are migrated to `#include "_prelude.wgsl"` as infrastructure (`sonar-reveal`, `codebreaker-reveal`, `sonar-pulse`, `blueprint-reveal`, `sketch-reveal`, `night-vision-scope`, `motion-revealer`, `thermal-touch`, `digital-reveal`, `neon-flashlight`). `pixel-reveal` and `x-ray-reveal` already include the prelude. That swap is not the upgrade.

Dead `extraBuffer[133..138]` springs are removed where the CPU re-upload zeros that range every frame (`codebreaker-reveal`, `sonar-pulse`, `night-vision-scope`, `digital-reveal`). The pointer was already the raw cursor, or one Euler step off the origin. That is a fix, not an idea. Dead `plasmaBuffer[1..]` reads become a phase of `plasmaBuffer[0]`. Same rule.

`codebreaker-reveal` is tagged `upgraded-rgba` but has no ACES. ACES on the display write is floor, so the tag becomes true. It is not an idea.

---

## sonar-reveal

IDENTITY: a sonar disc around the pointer, dim world outside, expanding ring fronts, a rotating PPI arm, contact blips, and an outward echo.
KEEP VERBATIM: Reveal Size / Ring Intensity / Edge Softness / Echo Mix; three detuned rings; click shocks; PPI arm and afterglow; edge blips; outward C echo. A stays ACES display RGBA.
MECHANISM:
- tactic 2: a PPI scope has fixed range rings, and a real beam gets wider with range.
- tactic 3: `rw` is one width for every ring. `baseSize` only gates the disc.
- tactic 6: neither idea writes new state. The echo path is unchanged.
ADD:
  1. Range rings — two fixed circles at 1/3 and 2/3 of the reveal radius, dim phosphor, not traveling pings. Reveal Size still sets them.
  2. Beam spread — each traveling ring's width grows with distance from the pointer. Edge Softness still sets the near width.
FORBID: a second sweep arm, a spring, an IQ palette, dispersion (sonar-pulse owns that).
A PACKING: ACES display RGBA. C is colour, exact bilinear load, unchanged.
FORMULA: none.

## codebreaker-reveal

IDENTITY: matrix rain covers the photo; a disc at the pointer (and clicks) decrypts it.
KEEP VERBATIM: Reveal Radius / Rain Speed / Code Density / Glow Intensity; column hash rain; cell glyphs; blink; click discs and rims. Bass still widens the disc.
MECHANISM:
- tactic 2: a matrix column has a white head and a green tail. This rain is a flat glyph field.
- tactic 5: the decrypted hole snaps shut. A break stays open until the rain covers it again.
- tactic 6: C is unread. A.a can hold the decrypt mask; C.a is that mask next frame.
ADD:
  1. Head and tail — the leading edge of each falling cell is white; glyphs behind it dim exponentially down the cell. Glow still scales the head.
  2. Decrypt persistence — the open hole is stored in A.a and closes at a rate set by Rain Speed, so the photo lingers after the disc moves on.
FORBID: finite drop-gaps (digital-reveal owns those), a spring, an IQ palette, glyph art from another file.
A PACKING: ACES display RGB + decrypt mask in A.a. Only C.a is read.
FORMULA: none. Dead per-column `plasmaBuffer[bin]` shimmer becomes a treble phase keyed by the column hash.

## sonar-pulse

IDENTITY: radial waves from the cursor that pulse, beat, chroma-split, and ping on click.
KEEP VERBATIM: Wave Speed / Frequency / Intensity / Wave Width; primary sine pulse; secondary beat; chromatic echo; click pings; depth attenuation.
MECHANISM:
- tactic 2: in water, long waves outrun short ones, and a cylindrical wave falls as 1/sqrt(r), not 1/r.
- tactic 3: `waveFreq` only sets the sine. `falloff` is `1/(1+2 dist)` for every frequency.
- tactic 6: C is unread. Both ideas are in the phase and the amplitude.
ADD:
  1. Deep-water dispersion — phase speed is `speed * sqrt(tanh(k)/k)`, so a lower Frequency runs ahead of a higher one. Wave Speed still scales both.
  2. Cylindrical spreading — amplitude is `1/sqrt(1 + d²)`, finite at the origin. Intensity still scales the pulse.
FORBID: PPI range rings and a sweep arm (sonar-reveal owns those), a spring, an IQ palette.
A PACKING: ACES display RGBA. C is not read.
FORMULA: deep-water dispersion (§12.2D). Only this file. Dead `plasmaBuffer[ring+1]` shimmer becomes a treble phase of the ring.

## blueprint-reveal

IDENTITY: a cyanotype blueprint of Sobel edges — bold, thin, and dashed hidden lines — that the pointer and clicks develop back into the photo.
KEEP VERBATIM: Edge Strength / Grid Opacity / Reveal Radius / Edge Softness; Sobel; pen weights; dashed hidden lines; ink mask in C.r; cyanotype fade; depth hatch.
MECHANISM:
- tactic 5: a sheet has major and minor grids, and a registration mark at the station the drafter is reading.
- tactic 3: `gridLineX/Y` is one weight. The pointer is only a reveal radius.
- tactic 6: both ideas are ink on the blueprint. A.r stays the mask.
ADD:
  1. Major grid — every fifth line of the existing grid is heavier. Grid Opacity still scales minor and major.
  2. Registration mark — a small circle and cross at the pointer, drawn only on the unrevealed sheet.
FORBID: a medical collimator cross (x-ray owns that), a spring, an IQ palette, a new stored channel.
A PACKING: raw `(revealMask, 0, 0, alpha)`. C.r is the ink mask. ACES on display only.
FORMULA: none.

## pixel-reveal

IDENTITY: a mosaic that remembers the pointer, refines on a resolution ladder, and dithers colour by that same ladder.
KEEP VERBATIM: Pixel Size / Radius / Edge Softness / Temporal Decay; block memory in A.a (`10 + level`); power-of-two ladder; Bayer colour ladder; held invert; scanlines; threshold gate.
MECHANISM:
- tactic 2: "pixel sort" in this file only gates on luma. A sort streaks the bright pixel along the scan.
- tactic 5: a mosaic has mortar between tiles. The blocks share edges with no seam.
- tactic 6: memory packing is unchanged. Both ideas are display-only.
ADD:
  1. Scanline sort — in the hidden mosaic, a pixel above the existing luma threshold is replaced by the brighter of itself and a tap one block to the right. Pixel Size sets the reach.
  2. Tile mortar — a dark seam on the coarse cell boundary, gone where the live reveal is open.
FORBID: a second decode ladder, a spring, an IQ palette, interlace (not this file's artifact).
A PACKING: display RGB + reveal memory in A.a. Only C.a is read. Unchanged.
FORMULA: none.

## sketch-reveal

IDENTITY: a pencil sketch with tonal hatch layers; the pointer lays a watercolour wash that dries and leaves a pigment rim.
KEEP VERBATIM: Brush Size / Edge Strength / Sketch Contrast / Brush Softness; gradient hatch; three tonal layers; paper tooth; wash in C.g; dried rim; smudge.
MECHANISM:
- tactic 2: a sketch has a contour line as well as hatch, and watercolour granulates in the mid-wash.
- tactic 3: `edge` darkens the graphite but never becomes its own stroke. `paperNoise` tints the sheet, not the wet pigment.
- tactic 6: wash packing is unchanged.
ADD:
  1. Contour pen — a dark outline where the existing edge is strong, under the wash so the photo still covers it. Edge Strength still scales the edge.
  2. Wash granulation — mid wetness is speckled by the existing tooth; dry paper and the pooled rim stay smoother. Brush Softness still sets drying.
FORBID: a new hatch angle family, a spring, an IQ palette, repacking A.
A PACKING: raw `(edge, wash, sketchBase, alpha)`. C.g is the wash. ACES on display only.
FORMULA: paper granulation (§12.2C). Only this file.

## night-vision-scope

IDENTITY: a green intensifier tube, sharp inside a disc that follows the pointer, with grain, scanlines, scintillation, and bloom.
KEEP VERBATIM: Scope Size / Noise Grain / Brightness / Scanlines; barrel pinch; green luma map; MCP sparks; bright-source bloom; click ring; vignette.
MECHANISM:
- tactic 2: P43 phosphor lags, and the tube has fixed-pattern streaks that do not reshuffle every frame.
- tactic 3: grain is one hash of `uv + time`. Bloom is already there. C is written and never read.
- tactic 6: A is display RGBA, so C.g is last frame's phosphor.
ADD:
  1. Phosphor lag — the green channel holds the brighter of this frame and last frame's green, stronger as Brightness (gain) rises.
  2. Fixed-pattern noise — vertical streaks from a hash of x only, under the temporal grain. Noise Grain scales both.
FORBID: a scope reticle (x-ray already has a crosshair; blueprint has a registration mark), a spring, an IQ palette, shot-noise that brightens the highlights.
A PACKING: ACES display RGBA. C.g is read as last frame's green.
FORMULA: none. Dead `plasmaBuffer[scanBin]` becomes treble on the scanline rate.

## motion-revealer

IDENTITY: motion in the photo, the pointer, and clicks opens a streaked, glowing reveal along the optical-flow direction.
KEEP VERBATIM: Motion Sensitivity / Trail Length / Glow Strength / Chromatic Separation; Sobel structure tensor; frame-difference magnitude; six-tap spectral streaks; click fronts; the existing cosine glow.
MECHANISM:
- tactic 3: `lambda_diff` is computed and then used only inside `atan2`. Isotropic patches still get a streak direction.
- tactic 6: A.a already stores motion and C.a is never read. The reveal flickers with single-frame diffs.
- tactic 1: the tensor already is the kernel. Coherence is the missing weight.
ADD:
  1. Coherence gate — streaks follow the tensor only where `(λ1−λ2)/(λ1+λ2)` is high. Flat patches do not invent a direction.
  2. Motion hold — C.a low-passes the motion, so a moving patch stays open for a few frames after it stops. Sensitivity still sets the raw difference.
FORBID: a new palette, a spring, a fluid solver, storing anything but motion in A.a.
A PACKING: `(live RGB, low-passed motion)`. C.rgb is the previous live colour. C.a is the previous motion. ACES on display only.
FORMULA: structure-tensor coherence (§12.2A). Only this file.

## thermal-touch

IDENTITY: the pointer heats the picture; heat cools and the plate is a blackbody image with a glow.
KEEP VERBATIM: Heat Intensity / Radius / Ambient Temp / Cooling Rate; blackbody ramp; local glow; luma as a temperature floor; held enlarges the radius; bass on intensity; mids on shimmer.
MECHANISM:
- tactic 1: diffusion currently blurs the photo, and C is read with a filtering sampler. The stored "heat" is tone-mapped red.
- tactic 2: a touch falls as inverse-square, and a thermal camera draws isotherms.
- tactic 6: once A.r is raw heat, the laplacian has a field to conduct.
ADD:
  1. Stored-field conduction — a 9-point laplacian on exact C.r, then the existing cooling. A.r is raw heat. Display is ACES. The photo is only the temperature floor.
  2. Inverse-square touch and isotherms — the pointer (and clicks) deposit `I/(d²+r0²)` heat, r0 from Radius; a few contour lines ride the heat.
FORBID: a height-field wave, a spring, an IQ palette, tone-mapping the stored heat.
A PACKING: raw heat in A.r. C.r is that heat. ACES on display only. This replaces the old display-colour write, which was read back as heat.
FORMULA: isotropic 9-point Laplacian (§12.2D); soft inverse-square (§12.2F). Inverse-square is shared only with neon-flashlight.

## digital-reveal

IDENTITY: glyph rain hides the photo; a brush (and clicks) open a hole that fades from an exact mask in C.r.
KEEP VERBATIM: Rain Density / Reveal Size / Trail Fade / Rain Speed; glyph bars and dots; column speeds; mask decay; click blobs; held enlarges the brush; depth weights the mask.
MECHANISM:
- tactic 5: digital rain falls as finite drops with gaps, not a continuous field of lit cells.
- tactic 2: characters at the edge of the hole break up instead of only crossfading.
- tactic 6: the mask in C.r already is the hole. The wipe reads it. No new channel.
ADD:
  1. Finite drops — each column is bright for a hash-length run, then dark, so rain is streaks with gaps. Density still sets the grid. Speed still sets the fall.
  2. Glyph dissolve — the reveal mask wipes each glyph from the top of its cell before the photo mix, so characters break apart at the hole.
FORBID: a white head and exponential tail (codebreaker owns those), a spring, an IQ palette, a second mask channel.
A PACKING: reveal mask in A.r (C.r read back). A.a mirrors the mask. ACES on display only.
FORMULA: none. Dead `plasmaBuffer[band+1]` becomes a per-column treble gain from the column hash.

## x-ray-reveal

IDENTITY: a collimated x-ray lens — inverted plate, bone window, penumbra, crosshair, quantum mottle — following the pointer.
KEEP VERBATIM: Lens Size / Edge Strength / Contrast / Lens Edge Softness; Beer-Lambert plate and bone window; Sobel edges; collimator blades and crosshair; dose mottle; click field.
MECHANISM:
- tactic 2: an anode heel darkens one side of the field, and a Bucky grid is a fine one-way line pattern on the plate.
- tactic 3: `rel` is a radius only. Nothing in the field varies with side.
- tactic 6: C is unread. Both ideas are on the plate, inside the mask.
ADD:
  1. Anode heel — transmission falls along +x inside the lens. Contrast still owns the curve.
  2. Anti-scatter grid — faint vertical lines, masked to the collimated field, not a square drafting grid.
FORBID: a second crosshair, a blueprint major-grid, a spring, an IQ palette, changing the bone window.
A PACKING: ACES display RGBA. C is not read. Unchanged.
FORMULA: none.

## neon-flashlight

IDENTITY: a neon beam at the pointer that lights the photo and traces edges, with an umbra, a penumbra, and a specular catch.
KEEP VERBATIM: Beam Radius / Neon Intensity / Edge Threshold / Ambient Light; umbra and penumbra; edge light; specular catch; cone ribs; radial sweep; held squeeze; click fronts; depth-edge alpha.
MECHANISM:
- tactic 2: a real beam is hotter in the core and coloured at the rim, and the core is inverse-square, not a flat disc.
- tactic 3: `beamFalloff` is a smoothstep. `audioNeon` tints the core and the rim the same.
- tactic 6: C is unread. Both ideas rescale the existing falloff and tint.
ADD:
  1. Inverse-square core — umbra brightness is `I/(d²+r0²)` with r0 from Beam Radius, so the hotspot is finite and the cone still ends at the penumbra.
  2. Hot core — the umbra emission desaturates toward white; the penumbra keeps the neon hue.
FORBID: a new palette, a spring, isotherms (thermal owns those), a medical grid.
A PACKING: ACES display RGBA. C is not read. Unchanged.
FORMULA: soft inverse-square (§12.2F). Shared only with thermal-touch.
