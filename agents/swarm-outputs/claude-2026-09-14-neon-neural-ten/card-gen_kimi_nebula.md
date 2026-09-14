SHADER: gen-kimi-nebula
IDENTITY: Purple/blue fbm gas-cloud nebula with domain warp, mids/treble strata drift, twinkling stars with gas-tinted halos, mouse stellar wind swirl, bass chromatic offset.
KEEP VERBATIM: hash3/noise3/fbm3, NebulaControls slider mapping (Intensity gain, Speed timescale, Scale frequency, Detail star cutoff), wind swirl + warp, 3-layer density, 5-colour palette ramp, star/halo logic, bass chromatic offset.
ADD (2 native ideas):
  1. Stromgren-sphere ionization around the mouse O-star: R_s ~ 0.5 Q^(1/3) (n/0.5)^(-2/3) per local density, n^2 recombination glow — [OIII] teal core, H-alpha red sphere, [SII] at the ionization front; mouse-held and bass raise Q.
  2. Dust lanes with 1/lambda extinction (tau * (0.55,0.8,1.25)) dimming/reddening gas, stars and the input layer behind them, plus photoevaporated bright rims on globule faces pointing toward the star (dust gradient along star direction).
FLOOR FIXES: added bounds guard; ordered 13-binding block; plasmaBuffer[0] bands clamped; hardcoded alpha max(input.a,0.85) -> semantic alpha (gas density + emission measure + dust column + stars + shell); dataTextureA now gets the same RGBA as writeTexture (was alpha=density); depth now gas/dust column mixed over input depth (was passthrough); added click response: Sedov-Taylor (R ~ t^0.4) supernova-remnant filament shells that compress gas; no C/B/extraBuffer use.
FORBID: replacing fbm cloud motif, generic bloom/IQ palettes, writing dataTextureB, extraBuffer use, changing slider ids/defaults.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x,y,z,w live (x also scales dust optical depth)
