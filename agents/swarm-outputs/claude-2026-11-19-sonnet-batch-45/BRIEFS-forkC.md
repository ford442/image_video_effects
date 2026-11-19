# BRIEFS fork C — crt-phosphor-decay, rgb-glitch-trail (both second pass)

Written before any WGSL edit. HEAD = origin/main 8c537fe6. HEAD renders (SwiftShader, 192², SRC=img) are healthy: 0 NaN, not blank, all four sliders of both files are read. No defects to rescue found by inspection or render.

---

SHADER: crt-phosphor-decay
IDENTITY (one sentence): the source picture re-drawn as a CRT raster — phosphor persistence in C, scanline + triad mask, halation, interlaced fields — still read by a viewer as "a TV tube".
KEEP VERBATIM: 4 params and roles (decay_rate → decayBase, scanline_intensity → scanlineStr gate for mask/scanline/field/bleed, halation_spread → 5-tap horizontal halation, audio_sensitivity → bass/mids/treble/rowVoice scale); two-rate phosphor knee (Idea 1); triad-aligned grain bleed (Idea 2); interlaced field parity (Idea 3); per-channel decay 0.97/0.94; triadMask phase off coord.x; mouse static + click bloom; ACES on display; A = ACES display RGBA read back as colour history (C.rgb).
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): the scanline term is `sin(uv.y*scanFreq)*0.5+0.5` — a fixed-profile raster. The next-better approximation of the same operator is a beam profile whose width depends on beam current.
  tactic 2 (physics one step further): the tube models phosphor emission. First-order side effects the real tube also shows: (a) beam spot grows with beam current, so bright lines bloom into the gaps and scanlines are most visible on dark/mid content, nearly gone in whites; (b) the three guns are never perfectly converged, and the error grows toward the corners (dynamic convergence).
  tactic 3 (promote an intermediate): `luma`/`boosted` (fresh + halation) is already computed and only used to drive halation mix — it is exactly the "beam current" for the line being drawn.
  tactic 6 (history): C is read as colour; no extra continuity needed beyond the two-rate knee already there — not used for the new ideas.
ADD (2 native ideas):
  4. Beam-current scanline bloom (§12.2B scanline mask + §12.1 tactic 2/3) — the scanline profile `s` is raised to `mix(1.0, 0.3, beam)` with `beam = smoothstep(0.35, 0.95, luma(boosted))`, and the triad-mask depth is eased by the same `beam`: bright lines swell into the dark gap and defocus the triad, dark/mid content keeps the full raster. Rides the existing scanline slider (0 = no raster at all, exactly as before).
  5. Dynamic convergence error (§12.2B Brown–Conrady-style radial term, linear in r² only — no geometry warp) — the R and B guns are sampled at ∓ a radial offset `(uv−0.5)·k·r²ₙ` (≈2 px at a corner, 0 at centre) so fringes grow toward the edges like a real tube. Gated by the existing scanline slider (CRT-ness) so 0 = clean converged picture, same as HEAD.
FORMULA ADMISSION: both rows are the retro/CRT half of the distortion table (scanline/field masks; CRT glass). Both consume quantities that already exist (`boosted` luma; `fresh` + `uv`). No new state/binding/solver/spring/param. Deletion test: deleting either leaves the same CRT; keeping only the idea is not a CRT (idea 4 needs the raster, idea 5 needs the image). Expert test: a TV tech says "bright lines bloom into the scanline gap" and "convergence is worst in the corners".
FORBID on this file: barrel/glass curvature (would break the integer-coord C history and the mouse mapping), springs/ripples beyond what already exists, IQ palettes, new params, any change to decay/knee/bleed/field constants.
A PACKING: ACES display RGBA (unchanged).

---

SHADER: rgb-glitch-trail
IDENTITY (one sentence): a pointer-left trail of fading intensity (A.r) that displaces the picture through a domain-warped FBM field with red/blue channel lag, spectral tint, glitch streak rows and a persistence comet.
KEEP VERBATIM: 4 params and roles (decay_rate → trail decay, radius → stamp radius, shift_strength → RGB shift, chaos → noise/tint/streak); `intensity` accumulation (mouse stamp + ripple spikes); warpedFBM/turbulentFBM displacement; `channelLag` idea (R + along warp, B − along warp·0.65, magnitude (0.35+chaos)); `persistenceComet` idea (C.r at −8px along warpDir, 0.22 tint); spectral tint; streak rows (noise>0.9); alpha = displacement·intensity; A = raw sim (intensity, blendedHue.rg, persistence) — raw, unchanged; ACES on display only; depth passthrough.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): the ghost offset of R and B is linear in `intensity`, so all three primaries collapse back to the picture at the same rate. Per-primary time constants are the next-better approximation of channel delay.
  tactic 2 (physics one step further): real RGB channel-desync / phosphor trails separate by *which primary lingers*: red persists longest, blue snaps back first, so the tail of a trail fringes red before it clears.
  tactic 3 (promote an intermediate): `histCoord`/`prevState` already loads C.r (the trail intensity field). Its spatial gradient is thrown away but encodes where the pointer's head and tail are along the trail.
  tactic 6 (history): C is read as a field (intensity) — the gradient of that field needs 4 more exact textureLoads of C.r, no packing change. A.a (persistence) stays as HEAD writes it.
  tactic 7 (direction, not just magnitude): HEAD ghosts split along a random smooth FBM direction. A trail has an orientation; the fringe should follow it.
ADD (2 native ideas):
  3. Per-primary decay order (§12.1 tactic 2; cf. §12.2B chroma delay) — channel lag magnitude is `shift` scaled per primary from the same `intensity`: R uses `mix(i, sqrt(i), 0.6)`, B uses `i·mix(1, sqrt(i), 0.7)` (both = 1 at i=1, so full-strength trails match HEAD). As the trail decays the blue ghost collapses first and a red-only fringe lingers. No new state.
  4. Tail-aligned fringe (§12.1 tactic 7) — central difference of C.r (±3 px, exact loads) gives the trail's gradient; `-normalize(g)` points down-trail. A fraction of that direction (weighted by smoothstep of |g|, so flat stamp interiors keep HEAD's warp direction) is added to the existing `channelLag`: R drags toward the tail, B leads toward the head, instead of splitting in a random direction. Existing lag/comet code stays; this only adds to the lag vector.
FORMULA ADMISSION: idea 3 is a time-constant-per-primary, deletion test passes both ways (deleting it leaves the HEAD lag; keeping only it is not the effect). Idea 4 uses the intensity field the file already loads each frame; no tensor, no new state. Neither row is used on crt-phosphor-decay (that file's ideas are beam profile + convergence; no latch, no chroma delay line there), and neither overlaps fork C's other file.
FORBID on this file: springs, new ripple fronts, IQ palette, block/macroblock quantisation (data-moshing owns that in fork B), Schmitt latch (would need to repurpose A.a), any new param, any re-meaning of A channels.
A PACKING: raw sim (intensity, blendedHue.rg, persistence) — unchanged; display ACES only on writeTexture.
