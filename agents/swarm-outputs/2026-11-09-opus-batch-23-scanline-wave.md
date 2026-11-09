SHADER: scanline-wave
IDENTITY: CRT scanlines that wave horizontally with bass, chromatic aberration, phosphor trail, aurora Lissajous bands.
KEEP VERBATIM: per-line sin warp + lissajous, chroma split, persistence trail, aurora bands, blackbody grade, 4 param roles.
RESCUE: extraBuffer 133..138 spring is dead (zeroed) + thread-0 race → raw mouse; writeTexture/A stored colour*alpha (alpha≈0.27) and the trail re-read premultiplied A, compounding to near-black → straight RGB in A (trail state) and writeTexture.
ADD:
  1. Phosphor triad decay — R/G/B phosphors decay at different rates (P22-style: green longest, blue shortest) so trails fringe in colour; extends the existing persistence.
  2. Beam-current bloom — scanline dark gap replaced by a Gaussian beam profile whose width grows with pixel luma; bright content swells its lines like an overdriven gun.
  3. Retrace ringing — damped deflection overshoot from each line's left edge, amplitude by wave amount + bass; adds to the existing horizontal offset.
FORBID: hum bars (crt-tv), shadow-mask triads, spring cursor, new palettes.
A PACKING: straight display RGB (trail state), a = bass envelope (unchanged role).
