SHADER: gen-prismatic-fractal-dunes
IDENTITY: High-speed raymarched desert of domain-warped fbm dunes on a wind conveyor, ballistic KIFS prism-crystal geysers, per-channel dispersed lighting, mouse gravity crater, sand streaks, click dust fronts, wind-advected temporal trails.
KEEP VERBATIM: hash21/noise/fbm, smax/smin, map dunes + geysers + mouse crater/crystal pull, calcNormal, camera, raymarch, RGB-dispersed diffuse, sand streaks, ripple dust fronts, wind-offset history trail.
ADD (2 native ideas):
  1. Aeolian impact ripples — asymmetric stoss/lee sawtooth ripple lamination added to dune height, oriented across the wind, migrating downwind, noise-driven crest bifurcations; amplitude scales with Wind Speed.
  2. Quartz saltation glints — grains hop (parabolic hop phase) on windward stoss slopes and flash spectral sparkle whose hue spreads with Prism Dispersion (Cauchy-style view-dependent shift); lee slip faces shaded; treble raises grain density.
FLOOR FIXES: textureSampleLevel(dataTextureC) -> manual bilinear of 4 clamped exact textureLoad taps; single clamped-to-2 plasmaBuffer vector split into bass/mids/treble clamped 0..1 with controlled gains (crystal glow 1+2.5*audio -> 1+0.5*bass+0.4*audio); added ACES tone map, trails now max() in display space; hardcoded alpha 1.0 -> fog-thinned terrain coverage / dust density with trail persistence; mouse-held (zoom_config.w) now deepens the crater blowout; header junk removed; JSON gained params array + upgraded-rgba feature. No extraBuffer use, no dataTextureB write.
FORBID: textureSampleLevel on dataTextureC, HDR in A, fake audio sources, replacing dunes/geysers motif.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x,y,z,w live
