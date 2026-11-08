SHADER: gen-art-deco-sky-prismatic (first pass)
IDENTITY: endless Art Deco tower ascent; gold bands, fluted columns, dispersive glass windows
KEEP VERBATIM: map() towers/city grid, Cauchy IOR + wavelengthToRGB, 4 params
ADD:
  1. Cauchy-shifted interior lattice fringes — HEAD computed refractOffset and never used it; each wavelength now sees the interior grid displaced by its own offset, so window lines split into spectral fringes
  2. Dispersed searchlight fans — 3 sweeping sky beams, each split into 4 Cauchy-tilted wavelength sub-beams (bass brightens)
  3. Split-spectrum gold sheen — gold-band highlight broken into 4 wavelength lobes (mids)
RESCUES: upside-down (uv.y + mouse y flipped); grey wash from height fog exp(-p.y*0.1) at camera y=-5; window prism sum un-normalised (pink wash); camera radius range could reach neighbour-cell towers (now 19..25); target raised so sky/beams show; Reinhard → ACES (clamped); no audio / no A write / alpha hard 1 (sky alpha now = glow coverage)
A PACKING: display RGBA
Stats @ JSON defaults (0.5 x4): HEAD meanL 0.482 (grey wash) → 0.331, meanA 1 → 0.98
