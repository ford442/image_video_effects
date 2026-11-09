# BRIEFS — fork D (written before WGSL edits)

SHADER: digital-crease (2nd pass)
IDENTITY: radial origami fan of mountain/valley creases over the image, with chromatic folding, paper fibre texture, cursor-driven local folds.
KEEP VERBATIM: radial sine folding + Kawasaki damping, mouse/ripple folds, chromatic R/B split, paper texture, valley AO + wet-glue seam (pass-1 ideas), 4 param roles.
RESCUE: extraBuffer[133..138] spring is zeroed every frame → smoothMouse ≡ (0,0) → the cursor fold was pinned to the top-left corner. Use the live mouse. A.g "paper memory" was computed but never displayed and C.r (|fold|) was read as if it were the mask.
ADD:
  1. Lingering crease scars — the folded-mask EMA (A.g, read back from C.g) leaves grey, fibre-lifted worn lines where creases sat, outliving the moving folds.
  2. Pleated-fan panel lighting — each panel's normal tilts along the azimuthal tangent by cos(baseFold), so alternate panels catch / lose the key light like a pleated fan.
  3. Crease misregistration — the image slides tangentially by signFold across each crease, so the picture breaks and fails to register at every fold line.
FORBID: springs, palettes, new ripple overlays.
A PACKING: [|fold|, crease-memory EMA, shadowFactor, alpha] (C.g read back).

SHADER: crt-scanline-damage (2nd pass)
IDENTITY: damaged CRT: barrel tube, RGB triad, 4-row raster, flicker, roll-band fault, treble snow/scars, click degauss with misconvergence.
KEEP VERBATIM: all HEAD stages + pass-1 ideas (misconvergence swirl, flyback retrace, radial chromatic barrel), packing, 4 param roles.
ADD:
  1. Burnt phosphor patch — a fixed FBM-shaped worn region of the tube face: desaturated, brown-shifted, dimmer, with a coarser smeared raster (dead phosphor).
  2. HV arc flash — rare treble-gated high-voltage arcs: a bright blue-white horizontal streak on one row band, a brief frame-wide brightness pop and a momentary raster shrink.
FORBID: hum bars (crt-tv), beam-current bloom (scanline-wave/phosphor-magnifier), flagging (vhs-tracking), springs.
A PACKING: unchanged (pre-ACES linear RGB + semantic alpha).
