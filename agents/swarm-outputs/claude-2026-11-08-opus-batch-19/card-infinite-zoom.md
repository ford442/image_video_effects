SHADER: infinite-zoom (2nd pass)
IDENTITY: Möbius-iterated infinite zoom of the source image with log-polar seam wrap
KEEP VERBATIM: Möbius iteration, mouse-as-pole, log-polar wrap, lattice/j alpha, params, A packing (ACES display RGBA)
ADD: 3. conformal lattice etching — thin silver hex-lattice lines on the pulled-back coordinate show the angle-preserving warp (mids brighten)
     4. pole-proximity chromatic stretch — min |cz+d| over the orbit drives a radial R/B split near the singularity (treble widens)
     5. zoom-level aerial recession — each deeper log-wrap level fades toward cool desaturated haze (bass pulls it back)
FORBID: Droste frame (already in catalog twice), ripple rings, palettes, spring cursor
A PACKING: unchanged
Hygiene: removed dead calculate_mobius_color_alpha (never called); first audio reads (plasmaBuffer[0].xyz); JSON gains audio-reactive.
