SHADER: stella-orbit (1st pass)
IDENTITY: raymarched stella-octangula star field + icosahedral spoke structure, coloured orbit trails, deep-blue glow
KEEP VERBATIM: stellas/structure/rabbit SDFs, orbit cLine loop, camera cuts, gamma pulse, params
RESCUES: did not compile (u_zoom_dummy); sign(0) up-vector -> NaN whole frame; non-unit Rodrigues axes inflated stellas ~10x; upside-down y; fake audio from zoom_config.x
ADD: 1. spoke charge pulses — bands run outward along the 12 spokes in the g2 glow (bass speed/brightness)
     2. stella lattice glints — per-cell hashed glint on the small stars, added after step-count darkening (bass rate)
     3. orbit-line pulse beads — bright bead travelling down each orbit trail (mids speed)
FORBID: ripple rings, palettes, spring cursor
A PACKING: display RGB, alpha = surface/line coverage; depth = 1 - z/30 on hits
Mouse: nudges look-at target (idle 0.5,0.5 = original framing).
