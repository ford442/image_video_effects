SHADER: radial-blur (1st Ideas pass)
IDENTITY: depth-aware radial/zoom blur with bokeh, chromatic dispersion, speed lines + shear
KEEP VERBATIM: sampleChromatic kernel, CoC, bokeh shapes, speed lines/shear, psychedelic fringe, params
ADD: 1. clear-eye focus core — blur ramps from a sharp eye at focus (radius breathes with mids) to full strength
     2. highlight light-trails — highlight taps (luma>0.62) along a 1.6x longer integral add bright streaks (bass gain)
     3. zoom-burst sector spokes — 36 precessing angular sectors vary speed-line length
FORBID: ripple rings, palettes, spring cursor
A PACKING: display RGBA (ACES), unchanged
Note: extraBuffer[133..136] pointer-velocity spring is dead (zeroed every frame) -> velMag ~0; left as-is.
