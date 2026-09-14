SHADER: gen-kimi-crystal
IDENTITY: Hexagonal-grid ice crystals growing/rotating with physical light transmission (IOR 1.31 Fresnel-Schlick, Beer absorption by purity/thickness), gold spectral-dispersion Fresnel edges, vertex sparkles.
KEEP VERBATIM: odd-row hex offset grid, sdHexagon, fresnelSchlick, hueLimit, transmission block (crystalMask/F0/pathLength/absorption/transmission), spectral edge glow with IOR_ICE_R/G/B, slider mappings x..w.
ADD (2 native ideas):
  1. Nakaya habit transition: as growthPhase advances (and treble = supersaturation rises) the hex plate core shrinks and six-fold stellar dendrite arms with 60-degree sidebranches (parallel to neighbour arms) grow out (sdDendrite, wedge-folded).
  2. 22-degree ice halo + parhelia around the mouse "sun": ring radius from minimum deviation through a 60-degree ice prism D = 2 asin(n sin 30deg) - 60deg per channel (1.31/1.32/1.33 -> red inner edge, blue skirt), darker sky inside, sun dogs left/right; mouse-held and purity strengthen, bass lifts.
FLOOR FIXES: fake audio removed (plasmaBuffer[1..8] per-row "FFT" -> plasmaBuffer[0].y mids row shimmer); bass/mids/treble clamped; single ACES on full display (was ACES on crystal then un-tonemapped input mix); semantic alpha (ice opacity via transmission + edge/halo/frost glow) written identically to writeTexture and dataTextureA (A previously held a different alpha); added click-ripple nucleation fronts (cells swept snap to full growth + frost ring flash); header/uniform comments; no C/B/extraBuffer use.
FORBID: replacing hex grid motif, generic bloom/noise overlays, writing dataTextureB, extraBuffer use.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x,y,z,w live (w also sets dendrite arm width)
