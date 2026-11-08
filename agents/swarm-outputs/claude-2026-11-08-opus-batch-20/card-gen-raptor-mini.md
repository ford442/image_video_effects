SHADER: gen-raptor-mini (2nd pass)
IDENTITY: radial pursuit-warped grid of capsule raptors with tails, territory voronoi, scent trails in C
KEEP VERBATIM: pursuit warp, voronoi territory, capsule+tail SDFs, claw rake, scent memory, params
RESCUES: dead extraBuffer[133..138] spring (zeroed each frame + thread-0 write race) replaced by raw pointer (no visual change; velMag terms stay 0 as before)
ADD: 1. head eye glint — blinking hot dot at each body's head along the pursuit dir (treble sharpens)
     2. alpha-leader crest — ~1 in 8 raptors gets a red SDF rim that flares with rage (bass)
     3. footfall stipple — alternating paired prints behind each body, pace = Max Speed, bass stamps
FORBID: ripple rings, palettes, spring cursor
A PACKING: unchanged (pre-ACES display/scent history; ACES on writeTexture)
Silent default ≈ before (meanL 0.232→0.237, meanA 0.323 unchanged).
