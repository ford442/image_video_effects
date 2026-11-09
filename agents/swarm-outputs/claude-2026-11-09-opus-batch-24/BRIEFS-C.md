SHADER: radial-slit-scan
IDENTITY: time-displacement ring radiating from the cursor; outside the ring the picture is frozen at the moment the ring passed.
KEEP VERBATIM: scan radius loop, width/softness update mask, Fade to Now decay, palette ring glow, chroma edge, split-tone, params.
ADD: 1. capture-age strata — A.a stores seconds since last capture; isochrone contours every 0.5 s show the time-rings. 2. age weathering — older strata desaturate/cool.
FORBID: springs, ripples, new palette.
A PACKING: raw composite RGB + A.a = capture age (was graded/ACES'd premultiplied display → packing lie).

SHADER: holographic-sticker (2nd pass)
IDENTITY: iridescent foil disc under the cursor with guilloche + held peel.
KEEP VERBATIM: HSV foil, grating, guilloche, peel, click rings, alpha model, params.
ADD: 3. glitter-flake foil — per-cell grating tilt flashes when aligned with sticker tilt. 4. kinegram emboss — photo luma gradient stamped into foil, relief flips with tilt.x.
FORBID: IQ palette, ripples beyond existing, spring.
A PACKING: ACES display RGBA (unchanged).
