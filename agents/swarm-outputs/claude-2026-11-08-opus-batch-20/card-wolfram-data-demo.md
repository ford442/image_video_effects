SHADER: wolfram-data-demo (1st pass)
IDENTITY: four "scientific constant" modes — phyllotaxis, Airy disk, golden spiral, Rayleigh sky — tinted by blackbody colour
KEEP VERBATIM: modes, constants, bessel/airy/spiral/scatter functions, param roles (mode, scale, density, temp/blend)
RESCUES: phyllotaxis centred at uv=-0.5 (entire default mode black); seeds 4x too large (merged blob); blackbody cubic fit broken (clamped yellow <6600 K, pure blue above) -> Tanner Helland fit; mode slider at 1.0 fell to passthrough; no aspect correction
ADD: 1. parastichy arms — one i mod 21 and one i mod 13 Fibonacci spiral family lit amber, rotating (mids rate); bass swells seeds
     2. Rayleigh-limit twin — second Airy source at the cursor; merges warm when unresolved (<1.22 r), splits cool when resolved
     3. golden rectangle tiling — nested φ-rectangle edges whose pole sits on the golden spiral's pole
FORBID: ripples, palettes, spring cursor
A PACKING: display RGB (ACES), alpha = pattern coverage mixed with input alpha by the blend slider
