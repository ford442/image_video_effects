SHADER: gen-grok4-life (3rd pass)
IDENTITY: two-species SmoothLife predator/prey ecosystem, green prey, red predators
KEEP VERBATIM: SmoothLife kernel, LV coupling, zones, prior 4 ideas, raw A packing, params
RESCUES: canvas stayed dead — per-pixel seeding required each pixel to sit in a blob centred on its own hash (~never); coupling = mix(0,0.6,mids) meant zero predators without audio (floor now 0.15). Extinction bloom still reads extraBuffer[133/134] (zeroed each frame, dead) — left, noted.
ADD: 1. spore drops — every pixel agrees on hashed drops per time slot (burst in the first second); Init Density = rate + radius
     2. birth-band membrane — contour where inner avg is in the birth interval glows (bass)
     3. predator scent halo — outer-annulus predator average (mB, was computed then discarded) warms prey nearby
FORBID: new species, palettes, ripples
A PACKING: raw prey/predator/age/activity (unchanged)
