# holographic-glitch — implementer notes (card #9)

Files: `public/shaders/holographic-glitch.wgsl`, `shader_definitions/retro-glitch/holographic-glitch.json`.

## Kept verbatim
Value-noise row shear (`row = floor(uv.y*(26+glitch·58))`, `phaseNoise`, `continuousShear` amplitudes), carrier
term, peel fold (`sin(dist·38 − phase)·smoothstep(0.42,0)`, 0.18/1.0 held gain, `peelOffset` scale), click push
(same front/pulse constants), radial chroma (`chromaDir`, `chromaAmount`), 3-tap per-channel history
(`trailVelocity`, `trailMix` clamp), spectrum overlay (`interferencePhase`, `hologram` gain, 0.24 source mix),
scan mask, peel rim spectrum, desync spectrum, slider roles (x glitch, y holographic, z rgbShift,
w flicker → phaseInstability role kept and now also drives flicker).

## A packing
Pre-ACES linear display RGB + transmission alpha. C is read back as that linear colour by the three per-channel
history taps (clamped [0,4]). ACES on `writeTexture` only. HEAD stored the ACES result and re-tone-mapped it
through the trails.

## Ideas (WGSL line ranges)
1. **Emitter flicker** — lines 199-206. `blackout` is a 24 Hz hashed event with probability `w·0.05` per tick
   (default 0.4 → ~2 % of ticks, a blackout every couple of seconds) dimming the frame to 10 %; `sag` is a slow
   value-noise luminance wander of up to `w·0.28`. Alpha also drops during a blackout (line 210).
2. **Grating-order ghosts** — lines 166-181. ±1-order copies of the image displaced along the shear (x) axis by
   `(0.012 + holo·0.045)/aspect`, with per-channel dispersion (R 1.25×, G 1×, B 0.78×) so each order is hue-split;
   the + order is warm-tinted, the − order cool. Gain `holo·(0.14 + phaseNoise·0.12)` follows the row-phase
   troughs like the overlay itself, mids lift it a little. Six extra bilinear taps.
3. **Peel shadow** — `peelFoldAt()` lines 74-77 and lines 187-194. The fold is re-evaluated a little down-screen
   and away from the pointer; where a crest sits there and this pixel is not itself lifted, the pixel is
   darkened by up to 55 % — a soft contact shadow under the raised crest.

## Floor fixes
- Half-texel UV (line 87).
- Phase-jump terms rewritten as `time·k + audio·m`: peel fold (line 106), carrier (line 130), interference (line
  157), scan (line 160).
- `pow(max(…),2.0)` → `rimBase*rimBase` (lines 162-163).
- Alpha `clamp(…,0.08,0.98)` → `source.a × transmission` (lines 209-210), transmission from carrier luma, trail
  alpha and peel rim.
- Pre-ACES in A (line 212), ACES on display only (line 213). No extraBuffer use.

## Deviations from the card
- Emitter flicker odds (`w·0.05` at 24 Hz) and sag (`w·0.28`) are my calibration for "default 0.4 mild"; not
  viewed on a GPU.
- `source.a` is floored at 0.25 in the alpha so the hologram overlay stays visible over transparent source
  regions (HEAD's alpha floor was 0.08 unconditionally).

## JSON
- `params` byte-exact (parsed-array diff and raw text block diff: identical). `updatedParams` already aligned;
  unchanged.
- `description` names the three ideas.
- `features`: removed `ign-dither`, `split-tone`, `film-grain`, `fresnel-rim`, `hue-preserve-clamp` (none
  implemented) and the duplicate `audio-driven`. Kept `upgraded-rgba`, `audio-reactive`, `mouse-driven`,
  `click-reactive`, `depth-aware`, `exact-history`, `three-band-audio`, `held-pointer`, `continuous-motion`,
  `chromatic-aberration`, `temporal-persistence`, `aces-tone-map`, `sci-fi`.
- `feedbackPacking` updated to pre-ACES linear + transmission alpha.

## Gates
- `wgsl_precommit_gate.py --files public/shaders/holographic-glitch.wgsl`: naga OK, bindgroup compatible, 0
  extraBuffer violations.
- `audit_extrabuffer.py`: AUDIT PASS. `audit_dead_sliders.py --files holographic-glitch`: AUDIT PASS.

## GPU risks (no WebGPU on this VM — nothing was viewed)
- The 24 Hz blackout hash is frame-rate independent but a 10 % dim for one tick at 60 fps shows for 2-3 frames;
  at default w it should read as an occasional emitter dropout, not strobing. If it strobes, halve the 0.05.
- Order ghosts add six taps; cost is modest but the ghost gain at holo = 1 (~0.26 of the image) may be strong on
  high-contrast sources.
- Peel shadow only shows while the pointer is near (peelMask ≥ 0.18 unheld); at rest with the pointer away it
  is zero, as intended.
