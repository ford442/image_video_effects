# BRIEFS — fork A (written before WGSL edits)

SHADER: gen-koch-snowflake-storm (2nd pass; HEAD Ideas: Koch offspring, 22° ice halo)
IDENTITY: warped Koch snowflakes orbiting the pointer with ice glow, offspring and halos.
KEEP VERBATIM: snowflake_sdf, offspring lobes, iceHalo, gust ripples, 4 param roles.
RESCUE: background "outside ice" colour (0.75,0.88,0.95)×1.8 → ACES ≈ white; frame is a white wash (meanL 0.89, std 0.035) and the halo/glow are invisible. Dark storm-sky background.
ADD:
  1. Parallax snowfall — three depth layers of hashed snow particles drifting down, sheared by the turbulence warp; near layer large and soft.
  2. Rime feathers — six thin dendrite ribs inside each flake body (angular comb lines with side barbs), lit by treble.
  3. Thundersnow flash — bass onsets backlight an fbm cloud deck in the sky with a brief blue-white flash.
FORBID: springs, palettes beyond ice blues.
A PACKING: ACES display RGBA (unchanged).

SHADER: page-curl-interactive (2nd pass; HEAD Ideas: backside peek, paper fiber)
IDENTITY: pointer-x page curl cylinder over the image, aurora marbling on the backside, click shockwaves.
KEEP VERBATIM: curl geometry (theta/srcX), backside peek, fiber, aurora, 3-point lighting, ripples, 4 param roles.
RESCUE: A stored sRGB ACES display and C fed it back into linear hdr (re-grade loop when Feedback Amount > 0). A now holds linear pre-grade hdr.
ADD:
  1. Next-page underlay — the uncovered region shows a second sheet (desaturated, aged copy of the image) instead of a void, with the curl's soft cast shadow falling on it.
  2. Paper thickness lip — a thin cream edge line where the sheet turns over (dx≈radius), with a dark under-edge.
  3. Gloss crest streak — a sharp specular stripe along the cylinder crest, brightened by treble.
FORBID: springs.
A PACKING: linear pre-grade hdr RGB + alpha.

SHADER: echo-trace (1st pass)
IDENTITY: Kalman-filtered pointer leaves dashed Mahalanobis prediction trails and brush echoes advected along the image structure tensor.
KEEP VERBATIM: Kalman predict/update maths, structure tensor advection, dashed trail, oil-slick film, click sparks, 4 param roles.
RESCUE: (a) Kalman state in extraBuffer[133..141] is zeroed every frame (+ race) → filter never initialised, velocity always 0. Move state to A texels (0,0)=pos/vel, (1,0)=covariance+sentinel. (b) A held covariance diagnostics but history reads C as colour → frame ≈ black (meanL 0.03), image only under the brush. A now holds trail colour; base is the source; history decays toward it.
ADD:
  1. Kalman lag ghosts — three tinted copies of the image stamped at past positions (pos − vel·k) behind the moving cursor.
  2. Redshift aging — echo hue drifts toward red/amber with age (A.a = echo energy).
  3. 2σ covariance ellipse — a thin outline at Mahalanobis distance 2 around the predicted cursor, widening with uncertainty.
FORBID: extraBuffer state, palettes beyond film.
A PACKING: trail RGB (linear) + echo energy; texels (0,0),(1,0) hold Kalman state.
